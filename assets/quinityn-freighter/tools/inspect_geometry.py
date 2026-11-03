"""Check fan clearance on evaluated geometry and render an overhead inspection.

Run with Blender and the editable .blend loaded; the source file is not saved.
"""
from pathlib import Path
import hashlib,json
import bpy
from mathutils import Vector
asset=Path(__file__).resolve().parents[1]
root=bpy.data.objects['Freighter | rotate this assembly']
scene=bpy.data.scenes['Scene']
root.rotation_euler[2]=0
bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()
def bounds(name):
 o=bpy.data.objects[name].evaluated_get(dg)
 pts=[o.matrix_world@Vector(p) for p in o.bound_box]
 return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
fan=bounds('Brass fan surround');cargo=bounds('Freight vault inner shell');cab=bounds('Cab shell')
clearance={'cargo':fan[0][1]-cargo[1][1],'cab':cab[0][1]-fan[1][1]}
assert min(clearance.values())>.04,clearance
assert abs((fan[1][0]-fan[0][0])-(fan[1][1]-fan[0][1]))<.00001,fan
report={'status':'passed','model_sha256':hashlib.sha256((asset/'source/quinityn-freighter.blend').read_bytes()).hexdigest(),'fan_world_bounds':fan,'cargo_front_y':cargo[1][1],'cab_rear_y':cab[0][1],'clearance_blender_units':clearance,'circular_xy_extent':True,'description':'Evaluated mesh bounds at north orientation; complete fan rim clears both bodies by >0.04 Blender units.'}
(asset/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report),flush=True)
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGBA'
scene.render.image_settings.color_depth='8'
scene.render.resolution_x=scene.render.resolution_y=1024
scene.cycles.samples=48
scene.render.threads_mode='FIXED';scene.render.threads=8
root.rotation_euler[2]=0
scene.camera.location=(0,1.74,15)
scene.camera.rotation_euler=(0,0,0)
scene.camera.data.ortho_scale=4.2
scene.render.filepath=str(asset/'previews/service-bay-clearance.png')
bpy.ops.render.render(write_still=True)
