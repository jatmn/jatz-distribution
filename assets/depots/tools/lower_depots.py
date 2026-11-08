# SPDX-License-Identifier: LGPL-3.0-only
"""Lower a depot master: squash the building above its pipes and belts, keeping its footprint.

The depots stood taller than the game's own 3x3 buildings, hiding what stood behind them.
Every point above PIVOT moves down to PIVOT + (height - PIVOT) * scale; nothing below it
moves, so pipe ports, the pipes' shape-keyed adapters, belts and the loading floor stay
exactly where the junction and geometry inspectors expect them. Run it once per master,
from the repository root, then re-inspect, re-render and re-package (README.md):

  blender -b assets/depots/source/<role>-3.blend --python-exit-code 1 \
    --python assets/depots/tools/lower_depots.py -- --scale 0.6

The builder (build_depots.py) doesn't reproduce these masters, so this edits them in place.
The scale and pivot are recorded on the assembly, and a lowered master is never lowered again.
"""
import argparse
import sys

import bpy

# Pipe routes and their adapters reach 0.71 (ports at 0.36), belts and the loading floor 0.26.
PIVOT = 0.75
ROOT_NAME = 'Depot | rotate this assembly'

parser = argparse.ArgumentParser()
parser.add_argument('--scale', type=float, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert 0 < args.scale <= 1, 'scale must be in (0, 1]'

root = bpy.data.objects[ROOT_NAME]
assert 'height_scale' not in root, f'{bpy.data.filepath} is already lowered'
assert tuple(root.rotation_euler) == (0, 0, 0), 'save the master unrotated'


def warp(z):
    return z if z <= PIVOT else PIVOT + (z - PIVOT) * args.scale


def lower(point, to_assembly, to_local):
    """A point in the object's space, moved in the assembly's space (its +Z is up)."""
    moved = to_assembly @ point
    moved.z = warp(moved.z)
    return to_local @ moved


for obj in root.children_recursive:
    to_assembly = root.matrix_world.inverted() @ obj.matrix_world
    to_local = to_assembly.inverted()
    if obj.type == 'MESH':
        mesh = obj.data
        heights = [(to_assembly @ v.co).z for v in mesh.vertices]
        if mesh.shape_keys:
            # Shape keys keep the pipes round in every direction; they all sit below the pivot.
            assert max(heights, default=0) <= PIVOT, f'{obj.name}: shape-keyed mesh above the pivot'
            continue
        for vertex in mesh.vertices:
            vertex.co = lower(vertex.co, to_assembly, to_local)
        mesh.update()
    elif obj.type == 'CURVE':
        for spline in obj.data.splines:
            for point in spline.bezier_points:
                point.co = lower(point.co, to_assembly, to_local)
                point.handle_left = lower(point.handle_left, to_assembly, to_local)
                point.handle_right = lower(point.handle_right, to_assembly, to_local)
            for point in spline.points:
                moved = lower(point.co.xyz, to_assembly, to_local)
                point.co = (*moved, point.co.w)
    elif obj.type == 'EMPTY':
        # Pipe port markers; anything higher would need moving with the building.
        assert to_assembly.translation.z <= PIVOT, f'{obj.name}: marker above the pivot'
    else:
        raise AssertionError(f'{obj.name}: unhandled {obj.type} in the assembly')

root['height_scale'] = args.scale
root['height_pivot'] = PIVOT
bpy.ops.wm.save_mainfile(compress=False)
print('LOWERED', bpy.data.filepath, args.scale, flush=True)
