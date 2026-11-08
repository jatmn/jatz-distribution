# SPDX-License-Identifier: LGPL-3.0-only
"""Wreck a depot or freighter master into its remnants, the corpse left when it is destroyed.

The remnants are the building or vehicle itself, broken: everything above its lower body is
crushed down and crumpled, a blast caves one side in and tears holes in its panels, loose parts
are thrown off and lie tumbled around it, bent shards of its own plating and paint lie about,
everything is sooted and stripped of paint, and the ground under it is scorched. Base Factorio's
destroyed assembling machine, chemical plant and storage tank were the reference for how much
survives: the footprint and the lower body stay recognisable, nothing stands tall.

The committed master and this script are the remnants' source (nothing here is drawn by hand):
the result is never saved over the master, only to the file given with --output, which
render_remnants.py renders and package_remnants.py packages. Every random choice comes from the
seed in the remnants' asset.json, so the same master and seed always make the same wreck.

  blender -b assets/depots/source/provider-3.blend --python-exit-code 1 \
    --python assets/depots/tools/build_remnants.py -- --profile depot --seed 3 --output <file>
"""
import argparse
import math
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

parser = argparse.ArgumentParser()
parser.add_argument('--profile', choices=['depot', 'freighter'], required=True)
parser.add_argument('--seed', type=int, required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])

# How hard each kind of master is wrecked, in fractions of its own size so the same rules fit
# a 3x3 depot and the much larger freighter model. reach: how far from the centre anything may
# land, in the master's own units, so nothing leaves the sprite frame. crush: how much of the height above the
# pivot is left; blast: radius of the caved-in side, as a fraction of the footprint's half
# diagonal; detach: chance a high part near the blast is thrown off.
PROFILES = {
    'depot': {
        'root': 'Depot | rotate this assembly', 'pivot': 0.17, 'crush': 0.42, 'sag': 0.9,
        'splay': 0.35, 'blast': 0.85, 'crumple': 0.035, 'lean': 0.1, 'detach': 0.45, 'detach_far': 0.05,
        'throw': (0.05, 0.5), 'shards': 40, 'scorch': 1.1, 'holes': 0.52, 'reach': 2.3,
    },
    'freighter': {
        'root': 'Freighter | rotate this assembly', 'pivot': 0.2, 'crush': 0.5, 'sag': 0.55,
        'splay': 0.2, 'blast': 0.6, 'crumple': 0.05, 'lean': 0.08, 'detach': 0.35, 'detach_far': 0.04,
        'throw': (0.03, 0.25), 'shards': 30, 'scorch': .75, 'holes': 0.45, 'reach': 6.4,
    },
}
profile = PROFILES[args.profile]
rng = random.Random(args.seed)
noise_offset = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))

root = bpy.data.objects[profile['root']]
scene = bpy.data.scenes['Scene']
# The renderer turns the assembly from heading 0 (north); the freighter master is saved turned.
root.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
to_root = root.matrix_world.inverted()


def kept_as_is(obj):
    # Pipe adapters keep their shape keys, which keep them round in every direction, so they
    # stay whole: the stub of a pipe left standing, as on the game's own wrecked tanks.
    return obj.type == 'MESH' and obj.data.shape_keys is not None


# Everything else becomes a plain mesh with its modifiers (bevels, solidify, arrays) applied,
# so the wreck bends the finished surfaces, and curves (tubes, cables) bend like the rest.
for obj in list(root.children_recursive):
    if obj.type not in {'MESH', 'CURVE'} or kept_as_is(obj):
        continue
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                           depsgraph=depsgraph)
    if obj.type == 'MESH':
        obj.modifiers.clear()
        old = obj.data
        obj.data = mesh
        if old.users == 0:
            bpy.data.meshes.remove(old)
    else:
        replacement = bpy.data.objects.new(obj.name, mesh)
        for collection in obj.users_collection:
            collection.objects.link(replacement)
        replacement.parent = obj.parent
        replacement.matrix_world = obj.matrix_world.copy()
        bpy.data.objects.remove(obj)

parts = [obj for obj in root.children_recursive if obj.type == 'MESH']
# Bring every part into the assembly's space (vertices included), parented straight to the
# assembly: the renderer projects shadows from the assembly's direct children.
for obj in parts:
    matrix = to_root @ obj.matrix_world
    if not kept_as_is(obj):
        obj.data.transform(matrix)
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
    else:
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = matrix


def bounds(objects):
    low, high = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_basis @ Vector(corner)
            low = Vector(map(min, low, point))
            high = Vector(map(max, high, point))
    return low, high


low, high = bounds(parts)
height = high.z
half = Vector(((high.x - low.x) / 2, (high.y - low.y) / 2, 0))
centre = Vector(((high.x + low.x) / 2, (high.y + low.y) / 2, 0))
diagonal = half.length
pivot = profile['pivot'] * height
# The blast comes from one side, never dead centre, so one side caves in and the other stands.
angle = rng.uniform(0, math.tau)
blast = centre + Vector((math.cos(angle) * half.x * .55, math.sin(angle) * half.y * .55, 0))
blast_radius = profile['blast'] * diagonal
lean = Vector((-math.cos(angle), -math.sin(angle), 0)) * profile['lean']


def drift(point):
    """A smooth random vector field, from three Perlin samples a fixed way apart.

    Never mathutils.noise.noise_vector: it adds an offset drawn from Blender's own random state,
    which differs from one run to the next, so the same master and seed made different wrecks.
    noise.noise is a pure function of the point.
    """
    return Vector(noise.noise(point + Vector(offset)) for offset in ((0, 0, 0), (31.4, 0, 0), (0, 47.9, 0)))


def within_reach(point):
    """The point on the ground, moved in towards the centre if it lies beyond the reach."""
    offset = Vector((point.x - centre.x, point.y - centre.y, 0))
    if offset.length > profile['reach']:
        offset *= profile['reach'] / offset.length
    return centre + offset


def blast_weight(point):
    distance = (Vector((point.x, point.y, 0)) - blast).length
    return max(0.0, 1 - distance / blast_radius) ** 1.5


def warp(point):
    """Where a point of the standing master ends up in the wreck."""
    z = point.z
    if z > pivot:
        z = pivot + (z - pivot) * profile['crush']
    weight = blast_weight(point)
    rise = max(0.0, z - pivot) / max(height - pivot, 1e-6)
    z -= weight * profile['sag'] * max(0.0, z - 0.02 * height)
    away = Vector((point.x, point.y, 0)) - blast
    away = away.normalized() if away.length > 1e-6 else Vector((1, 0, 0))
    moved = Vector((point.x, point.y, z))
    moved += away * weight * profile['splay'] * diagonal * rise
    moved += lean * z
    # Crumpling grows with height: the base stands on the ground, the top took the blast. It
    # depends on the ground position only, so plates lying on each other (paint on a roof) bend
    # together instead of passing through each other.
    ground = Vector((point.x, point.y, 0)) * (5 / diagonal) + noise_offset
    crumple = drift(ground) * profile['crumple'] * diagonal
    moved += crumple * (0.25 + rise)
    moved.z = max(moved.z, min(point.z, 0.004 * height))
    return moved


def material_named(prefix):
    return next((m for m in bpy.data.materials if m.name.startswith(prefix)), None)


# Parts high up near the blast are thrown off; the smallest of them (fasteners, lenses) are lost.
thrown, lost = [], []
for obj in parts:
    if kept_as_is(obj):
        continue
    part_low, part_high = bounds([obj])
    size = (part_high - part_low).length
    middle = (part_low + part_high) / 2
    # Only loose fittings fly: lids, roofs and walls stay to be recognised, broken.
    if part_low.z < pivot or size > diagonal * 0.4:
        continue
    chance = profile['detach'] * blast_weight(middle) + profile['detach_far']
    if rng.random() < chance:
        (lost if size < 0.035 * diagonal and rng.random() < 0.7 else thrown).append(obj)
for obj in lost:
    parts.remove(obj)
    bpy.data.objects.remove(obj)



def dice(obj, longest):
    """Split the faces into small triangles, so large flat plates can bend and tear too."""
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        # The masters' weighted normals would keep the bent plates lit as if flat.
        if obj.data.has_custom_normals:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    work = bmesh.new()
    work.from_mesh(obj.data)
    bmesh.ops.triangulate(work, faces=list(work.faces))
    for _ in range(6):
        long = [edge for edge in work.edges if edge.calc_length() > longest]
        if not long:
            break
        bmesh.ops.subdivide_edges(work, edges=long, cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(work, faces=[face for face in work.faces if len(face.verts) > 3])
    work.to_mesh(obj.data)
    work.free()


for obj in parts:
    if kept_as_is(obj) or obj in thrown:
        continue
    dice(obj, 0.07 * diagonal)
    mesh = obj.data
    for vertex in mesh.vertices:
        vertex.co = warp(vertex.co)
    mesh.set_sharp_from_angle(angle=math.radians(35))
    mesh.update()

# Holes torn in the plating near the blast, ragged at the edges, showing the burnt inside.
for obj in parts:
    if kept_as_is(obj) or obj in thrown or len(obj.data.polygons) < 24:
        continue
    work = bmesh.new()
    work.from_mesh(obj.data)
    doomed = []
    for face in work.faces:
        point = face.calc_center_median()
        if point.z < pivot * 0.8:
            continue
        ragged = noise.noise(point * (9 / diagonal) + noise_offset * 2)
        if blast_weight(point) + ragged * 0.35 > profile['holes']:
            doomed.append(face)
    if doomed and len(doomed) < len(work.faces):
        bmesh.ops.delete(work, geom=doomed, context='FACES')
        work.to_mesh(obj.data)
        obj.data.update()
    work.free()

# The burnt-out inside, seen through the holes: a heap of charred debris filling the lower body.
char_material = bpy.data.materials.new('WRECK | charred inside')
char_material.use_nodes = True
shader = char_material.node_tree.nodes['Principled BSDF']
shader.inputs['Roughness'].default_value = 1
shader.inputs['Specular IOR Level'].default_value = .15
pattern = char_material.node_tree.nodes.new('ShaderNodeTexNoise')
pattern.inputs['Scale'].default_value = 40 / diagonal
pattern.inputs['Detail'].default_value = 4
ramp = char_material.node_tree.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].color = (.003, .0028, .0026, 1)
ramp.color_ramp.elements[1].color = (.022, .017, .013, 1)
char_material.node_tree.links.new(pattern.outputs['Fac'], ramp.inputs['Fac'])
char_material.node_tree.links.new(ramp.outputs['Color'], shader.inputs['Base Color'])
work = bmesh.new()
bmesh.ops.create_grid(work, x_segments=24, y_segments=24, size=1)
for vertex in work.verts:
    point = Vector((centre.x + vertex.co.x * half.x * .88, centre.y + vertex.co.y * half.y * .88, 0))
    lumps = noise.noise(point * (8 / diagonal) + noise_offset * 3) * .5 + .5
    vertex.co = Vector((point.x, point.y, pivot * (.75 + .6 * lumps)))
mesh = bpy.data.meshes.new('WRECK | burnt-out inside')
work.to_mesh(mesh)
work.free()
mesh.materials.append(char_material)
char = bpy.data.objects.new(mesh.name, mesh)
scene.collection.objects.link(char)
char.parent = root

# Thrown parts tumble and come to rest on the ground around the wreck, away from the blast.
for obj in thrown:
    part_low, part_high = bounds([obj])
    middle = (part_low + part_high) / 2
    mesh = obj.data
    mesh.transform(Matrix.Translation(-middle))
    tumble = Euler((rng.uniform(-1.3, 1.3), rng.uniform(-1.3, 1.3), rng.uniform(0, math.tau))).to_matrix().to_4x4()
    mesh.transform(Matrix.Diagonal((1, 1, rng.uniform(.45, .8), 1)) @ tumble)
    away = Vector((middle.x, middle.y, 0)) - blast
    direction = math.atan2(away.y, away.x) + rng.uniform(-.9, .9)
    reach = rng.uniform(*profile['throw']) * diagonal
    edge = Vector((math.cos(direction) * half.x, math.sin(direction) * half.y, 0))
    target = centre + edge * rng.uniform(.55, 1.0) + Vector((math.cos(direction), math.sin(direction), 0)) * reach
    mesh.transform(Matrix.Translation(within_reach(target)))
    resting = min(v.co.z for v in mesh.vertices)
    mesh.transform(Matrix.Translation((0, 0, -resting + 0.002 * height)))
    mesh.update()

# Materials: sooted and burnt, paint flaked off down to bare metal, lenses dark.
soot_strength = {'PAINT': .9, 'BASE': .75}


def soot(material):
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    if shader is None:
        return
    shader.inputs['Emission Strength'].default_value = 0
    base = shader.inputs['Base Color']
    coordinates = nodes.new('ShaderNodeTexCoord')
    coordinates.object = root
    mapping = nodes.new('ShaderNodeMapping')
    mapping.inputs['Location'].default_value = noise_offset
    links.new(coordinates.outputs['Object'], mapping.inputs['Vector'])
    pattern = nodes.new('ShaderNodeTexNoise')
    pattern.name = 'WRECK | soot'
    pattern.inputs['Scale'].default_value = 7 / diagonal
    pattern.inputs['Detail'].default_value = 6
    pattern.inputs['Roughness'].default_value = .65
    links.new(mapping.outputs['Vector'], pattern.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = .4
    ramp.color_ramp.elements[0].color = (.035, .032, .03, 1)
    ramp.color_ramp.elements[1].position = .58
    ramp.color_ramp.elements[1].color = (.8, .76, .72, 1)
    links.new(pattern.outputs['Fac'], ramp.inputs['Fac'])
    darken = nodes.new('ShaderNodeMixRGB')
    darken.blend_type = 'MULTIPLY'
    kind = material.name.split(' |')[0]
    darken.inputs['Fac'].default_value = soot_strength.get(kind, .75)
    if base.is_linked:
        links.new(base.links[0].from_socket, darken.inputs['Color1'])
    else:
        darken.inputs['Color1'].default_value = base.default_value
    links.new(ramp.outputs['Color'], darken.inputs['Color2'])
    links.new(darken.outputs['Color'], base)
    roughness = shader.inputs['Roughness']
    if not roughness.is_linked:
        roughness.default_value = min(1, roughness.default_value + .2)
    if 'paint_channel' in material:
        # More of the paint burnt off: the flake threshold decides what is still painted.
        threshold = nodes.get('Math')
        if threshold is not None and threshold.operation == 'GREATER_THAN':
            threshold.inputs[1].default_value = max(.45, threshold.inputs[1].default_value - .05)


for material in bpy.data.materials:
    if material.use_nodes and material.name.split(' |')[0] in soot_strength:
        soot(material)


# Bent shards of the master's own plating, paint included, scattered around the wreck.
shard_materials = [m for m in (material_named('PAINT | cargo'), material_named('PAINT | cab'),
                               material_named('BASE | dark cast steel'), material_named('BASE | worn steel edges'),
                               material_named('PAINT | trim')) if m is not None]
for index in range(profile['shards']):
    length = rng.uniform(.05, .26) * min(diagonal, 2.5 * half.x)
    width = rng.uniform(.03, .12) * min(diagonal, 2.5 * half.x)
    work = bmesh.new()
    bmesh.ops.create_grid(work, x_segments=5, y_segments=3, size=.5)
    for vertex in work.verts:
        vertex.co.x *= length
        vertex.co.y *= width
        vertex.co.z = (noise.noise(vertex.co * (20 / diagonal) + Vector((index, 0, 0))) * .35 +
                       (vertex.co.x / length) ** 2 * rng.uniform(-.6, .6)) * width
    extruded = bmesh.ops.extrude_face_region(work, geom=list(work.faces))
    for element in extruded['geom']:
        if isinstance(element, bmesh.types.BMVert):
            element.co.z += .012 * diagonal
    mesh = bpy.data.meshes.new(f'WRECK | shard {index:02}')
    work.to_mesh(mesh)
    work.free()
    mesh.materials.append(shard_materials[index % len(shard_materials)])
    tilt = Euler((rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(0, math.tau))).to_matrix().to_4x4()
    direction = angle + math.pi + rng.uniform(-2.2, 2.2)
    edge = Vector((math.cos(direction) * half.x, math.sin(direction) * half.y, 0))
    spot = centre + edge * rng.uniform(.35, 1.0) + Vector((math.cos(direction), math.sin(direction), 0)) * rng.uniform(0, .3) * diagonal
    mesh.transform(Matrix.Translation(within_reach(spot)) @ tilt)
    resting = min(v.co.z for v in mesh.vertices)
    mesh.transform(Matrix.Translation((0, 0, -resting + 0.002 * height)))
    shard = bpy.data.objects.new(mesh.name, mesh)
    scene.collection.objects.link(shard)
    shard.parent = root

# Scorched ground under the wreck. It doesn't cast a shadow, so it hangs from the assembly's
# parent (the depots' projection; the freighter's world), not the assembly: the renderer projects
# shadows only from the assembly's children, and a burnt patch is round enough not to turn.
scorch_material = bpy.data.materials.new('WRECK | scorched ground')
scorch_material.use_nodes = True
scorch_material.blend_method = 'BLEND'
nodes, links = scorch_material.node_tree.nodes, scorch_material.node_tree.links
nodes.clear()
output = nodes.new('ShaderNodeOutputMaterial')
shader = nodes.new('ShaderNodeBsdfPrincipled')
shader.inputs['Base Color'].default_value = (.018, .016, .014, 1)
shader.inputs['Roughness'].default_value = 1
shader.inputs['Specular IOR Level'].default_value = .15
transparent = nodes.new('ShaderNodeBsdfTransparent')
mix = nodes.new('ShaderNodeMixShader')
coordinates = nodes.new('ShaderNodeTexCoord')
gradient = nodes.new('ShaderNodeTexGradient')
gradient.gradient_type = 'SPHERICAL'
pattern = nodes.new('ShaderNodeTexNoise')
pattern.inputs['Scale'].default_value = 4
pattern.inputs['Detail'].default_value = 5
combine = nodes.new('ShaderNodeMath')
combine.operation = 'MULTIPLY'
lumpy = nodes.new('ShaderNodeMapRange')
lumpy.inputs['To Min'].default_value = .5
lumpy.inputs['To Max'].default_value = 1.5
links.new(coordinates.outputs['Generated'], pattern.inputs['Vector'])
mapping = nodes.new('ShaderNodeMapping')
# Generated coordinates run 0 to 1 across the patch; centre them, flat (its height is nothing).
mapping.inputs['Location'].default_value = (-1, -1, 0)
mapping.inputs['Scale'].default_value = (2, 2, 0)
links.new(coordinates.outputs['Generated'], mapping.inputs['Vector'])
links.new(mapping.outputs['Vector'], gradient.inputs['Vector'])
links.new(gradient.outputs['Fac'], combine.inputs[0])
links.new(pattern.outputs['Fac'], lumpy.inputs['Value'])
links.new(lumpy.outputs['Result'], combine.inputs[1])
ramp = nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = .06
ramp.color_ramp.elements[1].position = .5
ramp.color_ramp.elements[1].color = (.85, .85, .85, 1)
links.new(combine.outputs['Value'], ramp.inputs['Fac'])
links.new(ramp.outputs['Color'], mix.inputs['Fac'])
links.new(transparent.outputs['BSDF'], mix.inputs[1])
links.new(shader.outputs['BSDF'], mix.inputs[2])
links.new(mix.outputs['Shader'], output.inputs['Surface'])

reach = profile['scorch'] * diagonal
work = bmesh.new()
bmesh.ops.create_grid(work, x_segments=2, y_segments=2, size=reach)
mesh = bpy.data.meshes.new('WRECK | scorched ground')
work.to_mesh(mesh)
work.free()
mesh.materials.append(scorch_material)
scorch = bpy.data.objects.new(mesh.name, mesh)
scene.collection.objects.link(scorch)
scorch.parent = root.parent
scorch.matrix_world = root.matrix_world @ Matrix.Translation((centre.x, centre.y, 0.001 * height))

root['remnants_of'] = bpy.path.basename(bpy.data.filepath)
root['remnants_seed'] = args.seed
bpy.ops.wm.save_as_mainfile(filepath=args.output, compress=False, copy=False)
print('WRECKED', bpy.data.filepath, args.profile, args.seed, flush=True)
