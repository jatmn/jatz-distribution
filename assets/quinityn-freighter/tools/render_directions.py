"""Render neutral beauty/AOV masters and geometric shadow silhouettes.

blender -b source/quinityn-freighter.blend --python tools/render_directions.py -- --start 0 --end 64
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--start", type=int, default=0)
parser.add_argument("--end", type=int, default=64)
parser.add_argument("--resolution", type=int, default=1024)
parser.add_argument("--samples", type=int, default=48)
parser.add_argument("--threads", type=int, default=8)
parser.add_argument("--hero", action="store_true")
parser.add_argument("--asset-root", type=Path)
parser.add_argument("--root-object", default="Freighter | rotate this assembly")
parser.add_argument("--direction-count", type=int, default=64)
parser.add_argument("--projection-y-scale", type=float, default=1)
args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
if args.asset_root:
    ROOT = args.asset_root.resolve()
scene = bpy.data.scenes["Scene"]
root = bpy.data.objects[args.root_object]
shadow_scene = bpy.data.scenes["Ground shadow"]
scene.cycles.samples = args.samples
scene.cycles.use_denoising = False
scene.render.threads_mode = "FIXED"
scene.render.threads = args.threads
scene.render.resolution_x = scene.render.resolution_y = args.resolution
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "OPEN_EXR_MULTILAYER"
scene.render.image_settings.color_depth = "16"
scene.render.image_settings.exr_codec = "ZIP"

if args.hero:
    root.rotation_euler[2] = math.radians(-225)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "16"
    scene.render.filepath = str(ROOT / "masters" / "hero-default-palette.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    sys.exit(0)

for material in bpy.data.materials:
    if "paint_channel" in material:
        ramp = material.node_tree.nodes["Surface pigment"].color_ramp
        ramp.elements[0].color = (.30, .30, .30, 1)
        ramp.elements[1].color = (1, 1, 1, 1)

# Rigid assets can reuse one evaluated mesh. Driven shape keys (depot pipes)
# must be evaluated again at each heading before projecting their shadows.
root.rotation_euler[2] = 0
bpy.context.window.scene = scene
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
dynamic_geometry = any(obj.type == "MESH" and obj.data.shape_keys and
                       obj.data.shape_keys.animation_data and
                       obj.data.shape_keys.animation_data.drivers for obj in root.children)
shadow_sources = []
all_vertices = []
all_faces = []
offset = 0
for obj in root.children:
    if obj.type not in {"MESH", "CURVE"}:
        continue
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    vertices = np.empty(len(mesh.vertices)*3, dtype=np.float32)
    mesh.vertices.foreach_get("co", vertices)
    vertices = vertices.reshape(-1,3)
    matrix = np.array(obj.matrix_world)
    vertices = vertices @ matrix[:3,:3].T + matrix[:3,3]
    shadow_sources.append((obj, len(mesh.vertices)))
    all_vertices.append(vertices)
    all_faces.extend(tuple(offset+i for i in p.vertices) for p in mesh.polygons)
    offset += len(vertices)
    evaluated.to_mesh_clear()
vertices = np.concatenate(all_vertices)
# Depot scenes compensate the camera's ground-plane foreshortening using a
# parent transform. Rotate in logical tile coordinates before reapplying it.
vertices[:,1] /= args.projection_y_scale
shadow_mesh = bpy.data.meshes.new("Projected vehicle shadow geometry")
shadow_mesh.from_pydata(vertices.tolist(), [], all_faces)
shadow_material = bpy.data.materials.get("SHADOW | black silhouette")
if shadow_material is None:
    shadow_material = bpy.data.materials.new("SHADOW | black silhouette")
    shadow_material.use_nodes = True
    nodes = shadow_material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (0, 0, 0, 1)
    shadow_material.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
shadow_mesh.materials.append(shadow_material)
shadow_object = bpy.data.objects.new("Directional light ground projection", shadow_mesh)
shadow_scene.collection.objects.link(shadow_object)
shadow_scene.render.resolution_x = shadow_scene.render.resolution_y = args.resolution
shadow_scene.render.threads_mode = "FIXED"
shadow_scene.render.threads = args.threads
shadow_scene.cycles.samples = 8
shadow_scene.render.image_settings.file_format = "PNG"
shadow_scene.render.image_settings.color_mode = "RGBA"
shadow_scene.render.image_settings.color_depth = "16"
shadow_dir = ROOT / "masters" / "shadow-silhouettes"
shadow_dir.mkdir(exist_ok=True)

for direction in range(args.start, args.end):
    angle = -math.tau * direction / args.direction_count
    root.rotation_euler[2] = angle
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()
    target = ROOT / "masters" / "exr" / f"direction-{direction:02d}.exr"
    if not target.exists():
        scene.render.filepath = str(target)
        bpy.ops.render.render(write_still=True, scene=scene.name)
    shadow_target = shadow_dir / f"direction-{direction:02d}.png"
    if not shadow_target.exists():
        projected = np.empty_like(vertices)
        if dynamic_geometry:
            depsgraph = bpy.context.evaluated_depsgraph_get()
            offset = 0
            for obj, count in shadow_sources:
                evaluated = obj.evaluated_get(depsgraph)
                mesh = evaluated.to_mesh()
                assert len(mesh.vertices) == count, "Shadow topology changed between headings"
                points = np.empty(count*3, dtype=np.float32)
                mesh.vertices.foreach_get("co", points)
                matrix = np.array(obj.matrix_world)
                points = points.reshape(-1,3) @ matrix[:3,:3].T + matrix[:3,3]
                projected[offset:offset+count,0] = points[:,0] + points[:,2]*0.5
                projected[offset:offset+count,1] = points[:,1] + points[:,2]*(2/3)
                offset += count
                evaluated.to_mesh_clear()
        else:
            cosine, sine = math.cos(angle), math.sin(angle)
            projected[:,0] = cosine*vertices[:,0] - sine*vertices[:,1] + vertices[:,2]*0.5
            projected[:,1] = (sine*vertices[:,0] + cosine*vertices[:,1])*args.projection_y_scale + vertices[:,2]*(2/3)
        projected[:,2] = 0.001
        shadow_mesh.vertices.foreach_set("co", projected.astype(np.float32).ravel())
        shadow_mesh.update()
        shadow_scene.render.filepath = str(shadow_target)
        bpy.ops.render.render(write_still=True, scene=shadow_scene.name)
    print(f"COMPLETED DIRECTION {direction:02d}", flush=True)
