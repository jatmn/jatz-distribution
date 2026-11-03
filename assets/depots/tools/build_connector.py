"""Build the untinted pipe-picture master using the current depot material library."""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/liquid-provider-3.blend'))
scene=bpy.data.scenes['Scene'];bpy.context.window.scene=scene
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
for other in list(bpy.data.scenes):
    if other!=scene:bpy.data.scenes.remove(other)
for aov in list(scene.view_layers[0].aovs):scene.view_layers[0].aovs.remove(aov)
scene.view_layers[0].name='Connector'
root=bpy.data.objects.new('Connector | rotate this assembly',None);scene.collection.objects.link(root)
steel=bpy.data.materials['BASE | dark cast steel'];edge=bpy.data.materials['BASE | worn steel edges']
copper=bpy.data.materials['BASE | aged copper'];black=bpy.data.materials['BASE | deep recess']
# Screenshot measurement: 49..51 px metal width at80px/tile, center about-.025 tile.
# Physical source height is an art choice, not inferred from that photograph.
height=.36
root['barrel_radius']=.305;root['flange_radius']=.36;root['height']=height
root['socket_entry']=.34;root['socket_distance']=.50;root['screen_center_y']=-.025
root['picture_shift_y']=height/math.sqrt(2)-.025
root['registration']='N/S axial length compensates camera foreshortening; cross sections remain circular'
def cylinder(name,y,radius,depth,material,x=0,z=height,vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=(x,y,z),rotation=(math.pi/2,0,0))
    obj=bpy.context.object;obj.name=name;obj.parent=root;obj.data.materials.append(material)
    for poly in obj.data.polygons:poly.use_smooth=len(poly.vertices)==4
    bevel=obj.modifiers.new('Worn machined edges','BEVEL');bevel.width=.008;bevel.segments=2
    obj.data.materials.append(edge);bevel.material=1
    return obj
cylinder('Broad cast mounting socket',.38,.36,.08,steel)
cylinder('Standard bore pipe neck',.415,.305,.07,steel)
cylinder('Gasket reveal',.43,.33,.025,black)
cylinder('Bronze bolted mating flange',.475,.36,.075,copper)
cylinder('Dark open bore',.517,.265,.012,black)
# A thin machined rim, around a dark recessed bore.
bpy.ops.mesh.primitive_torus_add(major_segments=64,minor_segments=12,major_radius=.283,minor_radius=.018,location=(0,.526,height),rotation=(math.pi/2,0,0))
obj=bpy.context.object;obj.name='Rolled socket mouth';obj.parent=root;obj.data.materials.append(edge)
for poly in obj.data.polygons:poly.use_smooth=True
for i in range(10):
    a=math.tau*i/10;x=.326*math.cos(a);z=height+.326*math.sin(a)
    cylinder('Recessed flange fastener',.52,.024,.018,edge,x,z,6)
    cylinder('Fastener socket',.531,.011,.005,black,x,z,6)
bpy.ops.object.camera_add(location=(0,-16,16));camera=bpy.context.object
camera.name='CAMERA | pipe picture registration';camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=2.5;scene.camera=camera
bpy.ops.object.light_add(type='SUN',location=(-6,-8,12));sun=bpy.context.object
sun.rotation_euler=(-sun.location).to_track_quat('-Z','Y').to_euler();sun.data.energy=2.2;sun.data.angle=math.radians(4)
bpy.ops.object.light_add(type='AREA',location=(-5,-7,11));fill=bpy.context.object
fill.rotation_euler=(Vector((0,0,1))-fill.location).to_track_quat('-Z','Y').to_euler();fill.data.energy=1200;fill.data.shape='DISK';fill.data.size=7
scene.render.resolution_x=scene.render.resolution_y=2048;scene.render.resolution_percentage=100
scene.cycles.samples=64;scene.cycles.use_denoising=False;scene.render.film_transparent=True
scene['reference']='assets/depots/README.md (pipe alignment)'
scene['depot_fidelity_pass']=bpy.data.scenes['Scene']['fidelity_pass']
root.scale.y=math.sqrt(2)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/pipe-connector.blend'))
print('BUILT shared pipe-picture master',flush=True)
