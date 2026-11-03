"""Render four registered pipe pictures and independent ground shadows from the master."""
from pathlib import Path
import hashlib,json,math
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'connectors';masters=out/'masters';masters.mkdir(parents=True,exist_ok=True)
scene=bpy.data.scenes['Scene'];root=bpy.data.objects['Connector | rotate this assembly']
scene.render.threads_mode='FIXED';scene.render.threads=12
scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='16'
shadow=bpy.data.scenes.new('Connector ground shadow');shadow.camera=scene.camera;shadow.collection.objects.link(scene.camera)
shadow.render.engine='CYCLES';shadow.cycles.samples=8;shadow.cycles.use_denoising=False
shadow.render.film_transparent=True;shadow.render.resolution_x=shadow.render.resolution_y=2048
shadow.render.resolution_percentage=100;shadow.render.threads_mode='FIXED';shadow.render.threads=12
shadow.render.image_settings.file_format='PNG';shadow.render.image_settings.color_mode='RGBA';shadow.render.image_settings.color_depth='16'
shadow.world=bpy.data.worlds.new('Connector shadow world');shadow.world.color=(0,0,0)
mat=bpy.data.materials.new('Connector black shadow');mat.use_nodes=True;nodes=mat.node_tree.nodes;nodes.clear()
em=nodes.new('ShaderNodeEmission');em.inputs['Color'].default_value=(0,0,0,1)
output=nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(em.outputs[0],output.inputs['Surface'])
results=[]
for index,direction in enumerate(['north','east','south','west']):
    bpy.context.window.scene=scene;root.rotation_euler.z=-index*math.pi/2;root.scale.y=math.sqrt(2) if index%2==0 else 1
    bpy.context.view_layer.update()
    scene.render.image_settings.file_format='OPEN_EXR_MULTILAYER';scene.render.image_settings.exr_codec='ZIP'
    scene.render.filepath=str(masters/f'{direction}.exr');bpy.ops.render.render(write_still=True)
    scene.render.image_settings.file_format='PNG'
    bpy.data.images['Render Result'].save_render(str(masters/f'{direction}.png'),scene=scene)
    center=root.matrix_world@Vector((0,root['socket_distance'],root['height']))
    projected=world_to_camera_view(scene,scene.camera,center)
    screen=[(projected.x-.5)*2.5,(.5-projected.y)*2.5+root['picture_shift_y']]
    target=[(0,-.5),(.5,0),(0,.5),(-.5,0)][index]
    assert abs(screen[0]-target[0])<1e-5 and abs(screen[1]-(target[1]-.025))<1e-5
    # The metal barrel's projected width must match the independently measured ~0.61tile.
    dg=bpy.context.evaluated_depsgraph_get()
    barrel=bpy.data.objects['Standard bore pipe neck'];evaluated=barrel.evaluated_get(dg);mesh=evaluated.to_mesh()
    axis=0 if index%2==0 else 1
    projected_barrel=[world_to_camera_view(scene,scene.camera,barrel.matrix_world@v.co)[axis]*2.5 for v in mesh.vertices]
    screen_width=max(projected_barrel)-min(projected_barrel);evaluated.to_mesh_clear()
    assert .60<=screen_width<=.64, (direction,screen_width)
    vertices=[];faces=[];dg=bpy.context.evaluated_depsgraph_get()
    for obj in root.children:
        evaluated=obj.evaluated_get(dg);mesh=evaluated.to_mesh();offset=len(vertices)
        for v in mesh.vertices:
            p=obj.matrix_world@v.co;vertices.append((p.x+p.z*.5,p.y+p.z*2/3,.001))
        faces.extend(tuple(offset+i for i in face.vertices) for face in mesh.polygons);evaluated.to_mesh_clear()
    mesh=bpy.data.meshes.new('Pipe ground projection');mesh.from_pydata(vertices,[],faces);mesh.materials.append(mat)
    obj=bpy.data.objects.new('Pipe shadow',mesh);shadow.collection.objects.link(obj)
    shadow.render.filepath=str(masters/f'{direction}-shadow.png');bpy.ops.render.render(write_still=True,scene=shadow.name)
    bpy.data.objects.remove(obj,do_unlink=True);bpy.data.meshes.remove(mesh)
    results.append({'direction':direction,'registered_seam':screen,'barrel_width_tiles':screen_width})
record={'source_sha256':hashlib.sha256((ROOT/'source/pipe-connector.blend').read_bytes()).hexdigest(),
        'renderer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'resolution':2048,'samples':scene.cycles.samples,
        'ortho_scale':2.5,'game_scale':32*2.5/512,'picture_shift':[0,float(root['picture_shift_y'])],
        'shadow_shift':[0,0],'registration':results,'reference_commit':'7f40d810b0e7d19624e9aee69e0205ff40f9ea4b'}
(masters/'render-inputs.json').write_text(json.dumps(record,indent=2)+'\n')
print('RENDERED and registered4 pipe pictures',flush=True)
