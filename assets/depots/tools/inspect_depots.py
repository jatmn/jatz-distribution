"""Verify editable geometry bounds, socket markers and screen/tile projection."""
import hashlib
import json
import math
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
results=[]
def roof_signature():
    prefixes=('Provider sealed circular lid','Hatch locking bridge','Central rotary lock','Segmented outer lock ring',
              'Heavy orange radial lock clamp','Radial lock reinforcement','Raised north south roof lock')
    parts={o.name:[[round(c,6) for c in o.matrix_basis@v.co] for v in o.data.vertices]
           for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(prefixes)}
    return hashlib.sha256(json.dumps(parts,sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/provider-3.blend'))
roof_reference=roof_signature()


def inspect_transfer_paths(scene, role, size):
    """Probe usable cargo/fuel paths and open-frame bays in logical tile coordinates."""
    factor=size/3
    bpy.data.objects['PROJECTION | tile grid compensation'].scale.y=1
    bpy.data.objects['Depot | rotate this assembly'].rotation_euler.z=0
    bpy.context.view_layer.update()
    graph=bpy.context.evaluated_depsgraph_get();clear_paths=0
    def clear(a,b):
        nonlocal clear_paths
        a,b=Vector(a)*factor,Vector(b)*factor
        hit,location,normal,index,obj,matrix=scene.ray_cast(graph,a,(b-a).normalized(),distance=(b-a).length)
        assert not hit,(role,size,'blocked transfer/frame path',tuple(a),tuple(b),obj.name if obj else None)
        clear_paths+=1
    belt_heights=[]
    if role in ['provider','request','buffer']:
        lanes=[(-.49,.68),(.49,.68)] if role=='buffer' else [(0,1.36)]
        for x,width in lanes:
            for dx in [-width*.28,0,width*.28]:
                for z in [.30,.75,1.20]:clear((x+dx,1.55,z),(x+dx,-.75,z))
            for y in [-.65,0,.90,1.40]:
                hit,point,*_=scene.ray_cast(graph,Vector((x,y,.22))*factor,Vector((0,0,-1)),distance=.22*factor)
                assert hit and .14*factor <= point.z <= .20*factor,(role,size,'missing/raised conveyor',y,point)
                belt_heights.append(round(point.z/factor,5))
        assert not any('roller' in obj.name.lower() for obj in scene.objects), (role,size,'exposed roller geometry')
    elif role=='fuel':
        # Fuel is mirrored in the source; solid hopper is at positive X.
        for x in [.52,.64,.76]:
            clear((x,.20,1.77),(x,.20,.95))
            clear((x,.20,.9073),(x,1.44,.3436))
    else:
        for sign in [-1,1]:
            # Buffer's front-side bays now carry full-width pipes. Sample the
            # remaining open bay behind each port and between the two front drops.
            for y in [-1.08 if role=='liquid-buffer' else -.95,.95]:
                if role=='liquid-buffer' and y>0:
                    # Front pipe bays are occupied; the open central frame remains clear.
                    clear((sign*.40,1.49,.48),(sign*.40,1.23,.48))
                else:clear((sign*1.49,y,.48),(sign*1.10,y,.48))
            xs=[-.15,.15] if role=='liquid-buffer' and sign==1 else [-1.04,1.04]
            for x in xs:clear((x,sign*1.49,.48),(x,sign*(1.23 if role=='liquid-buffer' and sign==1 else 1.11),.48))
    return {'clear_path_probes':clear_paths,'conveyor_surface_heights_large_equivalent':belt_heights}

for metadata_path in sorted(ROOT.glob('*/3/asset.json')):
    meta=json.loads(metadata_path.read_text())
    source=ROOT/meta['source']
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene=bpy.data.scenes['Scene']
    bpy.context.window.scene=scene
    root=bpy.data.objects['Depot | rotate this assembly']
    root.rotation_euler.z=0
    bpy.context.view_layer.update()
    depsgraph=bpy.context.evaluated_depsgraph_get()
    minimum=Vector((100,100,100));maximum=Vector((-100,-100,-100))
    mesh_objects=0
    for obj in root.children:
        if obj.type not in {'MESH','CURVE'}: continue
        evaluated=obj.evaluated_get(depsgraph)
        mesh=evaluated.to_mesh()
        for vertex in mesh.vertices:
            world=obj.matrix_world @ vertex.co
            point=Vector((world.x,world.y/math.sqrt(2),world.z))
            for axis in range(3):
                minimum[axis]=min(minimum[axis],point[axis])
                maximum[axis]=max(maximum[axis],point[axis])
        evaluated.to_mesh_clear()
        mesh_objects+=1
    half=meta['size']/2
    assert max(abs(minimum.x),abs(minimum.y),abs(maximum.x),abs(maximum.y))<=half+.015, (source,minimum,maximum)
    assert minimum.z>=-.01
    markers=[obj for obj in root.children if obj.name.startswith('SOCKET |')]
    assert len(markers)==len(meta['ports'])
    checked=0
    for heading in range(4):
        root.rotation_euler.z=-heading*math.pi/2
        bpy.context.view_layer.update()
        for port in meta['ports']:
            marker=next(item for item in markers if item['direction']==port['direction'] and list(item['tile_anchor'])==port['position'])
            x,y=port['seam']
            for _ in range(heading): x,y=-y,x
            world=marker.matrix_world.translation
            assert abs(world.x-x)<1e-5 and abs(-world.y/math.sqrt(2)-y)<1e-5
            ground=Vector((world.x,world.y,0))
            projected=world_to_camera_view(scene,scene.camera,ground)
            screen_x=(projected.x-.5)*meta['ortho_scale']
            screen_y=(.5-projected.y)*meta['ortho_scale']
            assert abs(screen_x-x)<1e-5 and abs(screen_y-y)<1e-5
            checked+=1
    if meta['role'] in ['provider','request','buffer']:
        assert not any(o.name.startswith(('Split hatch','Chamfered colored access panel','Buffer circular lid','Central roof spine','Spine roof')) for o in root.children)
        assert roof_signature()==roof_reference, (meta['role'],'roof differs from preserved Provider geometry')
    transfer=inspect_transfer_paths(scene,meta['role'],meta['size'])
    assert all(image.packed_file or image.source in {'GENERATED','VIEWER'} for image in bpy.data.images), 'External image dependency'
    results.append({'role':meta['role'],'size':meta['size'],'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'functional_geometry':transfer,'geometry_objects':mesh_objects,'logical_bounds':[list(minimum),list(maximum)],'socket_projection_checks':checked})
    print('GEOMETRY PASSED',meta['role'],meta['size'],flush=True)
(ROOT/'geometry-validation.json').write_text(json.dumps({'status':'passed','variants':len(results),'results':results},indent=2)+'\n')
