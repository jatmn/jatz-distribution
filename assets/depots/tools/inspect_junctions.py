"""Check full-bore tank routes, native projected diameter, joints and service clearance."""
import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view
repo=Path(__file__).resolve().parents[3];results=[]
# Independent mating geometry from the common connector master; its outside calibration remains fixed.
bpy.ops.wm.open_mainfile(filepath=str(repo/'assets/depots/source/pipe-connector.blend'))
connector_source=repo/'assets/depots/source/pipe-connector.blend'
connector=bpy.data.objects['Connector | rotate this assembly']
native_radius=float(connector['barrel_radius']);picture_shift=float(connector['picture_shift_y'])
mount=bpy.data.objects['Broad cast mounting socket']
mount_axis=[(mount.matrix_basis@v.co).y for v in mount.data.vertices]
entry=min(mount_axis);mount_front=max(mount_axis)
vectors=[(0,-1),(1,0),(0,1),(-1,0)]
for role in ['fuel','liquid-provider','liquid-request','liquid-buffer']:
 source=repo/f'assets/depots/source/{role}-3.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
 scene=bpy.data.scenes['Scene'];bpy.context.window.scene=scene
 root=bpy.data.objects['Depot | rotate this assembly'];projection=root.parent
 root.rotation_euler.z=0;projection.scale.y=1;bpy.context.view_layer.update()
 dg=bpy.context.evaluated_depsgraph_get();cache={}
 def tree(name):
  if name not in cache:
   obj=bpy.data.objects[name];ev=obj.evaluated_get(dg);mesh=ev.to_mesh()
   cache[name]=BVHTree.FromPolygons([obj.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons]);ev.to_mesh_clear()
  return cache[name]
 assert not any(o.name.startswith(('Manway forged clamp dog','Low manway retaining tab','Factory socket cast reducer')) for o in scene.objects)
 assert not any('pump' in o.name.lower() for o in scene.objects), 'Obstructing lower pump remains'
 if role=='fuel':
  for obj in root.children:
   if obj.type=='MESH' and obj.name.startswith(('Foundation edge chip','WEAR |')):
    for face in obj.data.polygons:
     assert not any(-1.565<p.x<-.315 and -.60<p.y<.60 and p.z<.25
                    for p in (obj.matrix_world@obj.data.vertices[i].co for i in face.vertices)), 'Floating Fuel pan decal'
 routes=[o for o in root.children if o.name.startswith('Factory full bore tank route')]
 necks=[o for o in root.children if o.name.startswith(('Welded tank neck |','Bolted tank adapter |'))]
 assert len(necks)==len(routes),(role,'missing seated weld neck')
 assert len(routes)==(2 if role=='liquid-buffer' else 1),(role,'missing tank route')
 markers=[o for o in root.children if o.name.startswith('SOCKET |')]
 tanks=[o for o in root.children if o.name.startswith('Broad domed pressure vessel')]
 assert len(tanks)==1,(role,'requires one pressure vessel')
 assert not any(o.name.startswith(('Full bore intertank bridge','Instrument enclosure mounting foot','Protected automation instrument enclosure')) for o in root.children)
 obstacles=[o for o in root.children if o.type=='MESH' and o.name.startswith((
  'Open ','Rear ','Side structural','Tank load','Pressure shell base','Tank foot','Orange frame','Machinery frame',
  'Cast octagonal','Bolted skid','Low steel foundation','Hopper ','Fuel hopper','Chute ','Connected open',
  'Protected automation','Instrument enclosure','Heavy lower shell flange','Midsection binding |'))]
 route_checks=[];pairs=[]
 for route in routes:
  bm=bmesh.new();bm.from_mesh(route.data)
  assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True)>0,(role,route.name,'invalid pipe solid');bm.free()
  centers=[Vector(p) for p in json.loads(route['pipe_centerline'])];count=route['pipe_ring_size']
  assert abs(route['native_pipe_radius']-native_radius)<1e-6
  for i,center in enumerate(centers):
   for vertex in route.data.vertices[i*count:(i+1)*count]:
    assert abs((vertex.co-center).length-native_radius)<1e-5,(role,route.name,'bore reduction',i)
  start=route.matrix_world@centers[0];end=route.matrix_world@centers[-1]
  owner=min(tanks,key=lambda o:abs(sum((o.matrix_world@v.co).x for v in o.data.vertices[64:128])/64-start.x))
  # Actual shell cross section at each vertex height, including the capsule
  # and the lower bevel. No radius assumption can hide a detached wide-tank inlet.
  def inlet_clearance(owner,points):
   ring0=[owner.matrix_world@v.co for v in owner.data.vertices[:64]]
   ring1=[owner.matrix_world@v.co for v in owner.data.vertices[64:128]]
   bottom=ring0[0].z;shoulder=(owner.matrix_world@owner.data.vertices[128].co).z
   depths=[]
   for point in points:
    assert bottom+.005<point.z<shoulder-.005,(role,'inlet outside tank height',point.z,bottom,shoulder)
    t=max(0,min(1,(point.z-bottom)/(ring1[0].z-bottom)))
    polygon=[a.lerp(b,t) for a,b in zip(ring0,ring1)]
    inside=False;distance=100
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
     if (a.y>point.y)!=(b.y>point.y) and point.x<(b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x:inside=not inside
     edge=Vector((b.x-a.x,b.y-a.y));delta=Vector((point.x-a.x,point.y-a.y))
     if edge.length_squared>1e-12:
      distance=min(distance,(delta-edge*max(0,min(1,delta.dot(edge)/edge.length_squared))).length)
    assert inside and distance>.005,(role,'inlet ring outside pressure shell',tuple(point),distance)
    depths.append(distance)
   return depths
  inlet_depth=inlet_clearance(owner,[route.matrix_world@v.co for v in route.data.vertices[:count]])
  marker=min(markers,key=lambda o:(o.location-end).length)
  dx,dy=vectors[marker['direction']//4];outward=Vector((dx,-dy,0))
  ax,ay=marker['tile_anchor'];anchor=Vector((ax,-ay,.36));join=(end-anchor).dot(outward)
  assert ((end-anchor)-outward*join).length<1e-5,(role,'off-axis connector entry')
  assert entry+.05<join<mount_front+.005,(role,'insufficient straight sleeve overlap',join,entry)
  assert len(centers)==2 and all(abs(c.z-.36)<1e-6 for c in centers),(role,'must be one straight ground-level barrel')
  assert (end-start).normalized().dot(outward)>.99999,(role,'route is not coaxial')
  if role=='liquid-buffer':assert marker['direction']==0 and list(marker['tile_anchor']) in [[-1,-1],[1,-1]], 'Buffer ports must both face front'
  pairs += [(route.name,o.name) for o in obstacles]
  neck=next(o for o in necks if o['source_route']==route.name)
  pairs += [(neck.name,o.name) for o in obstacles]
  adapters=[o for o in root.children if o.name.startswith('Buffer adapter ') and o.get('source_route')==route.name]
  if role=='liquid-buffer':
   assert len(adapters)==3 and neck.name.startswith('Bolted tank adapter |'), 'Buffer requires bolted adapter, gasket and heads'
   pairs += [(part.name,o.name) for part in adapters for o in obstacles]
  pairs += [(route.name,o.name) for o in tanks if o!=owner]
  route_checks.append({'route':route.name,'tank':owner.name,'socket_direction':marker['direction'],'diameter_tiles':2*native_radius,'minimum_inlet_embed':min(inlet_depth),'constant_radius_rings':len(centers),'anchor':[ax,ay],'join_distance':join,'straight_route_length':(end-start).length})
 flanges=[o for o in root.children if 'machined flange' in o.name]
 if role=='liquid-buffer':
  # Pressure-shell clearance includes the retained elevated service rails.
  rails=[o for o in root.children if o.name.startswith(('Rear service bay rail','Open scaffold diagonal','Rear scaffold rail'))]
  pairs += [(o.name,tanks[0].name) for o in rails]
 for obj in flanges:
  bm=bmesh.new();bm.from_mesh(obj.data)
  assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True)>0,(role,obj.name,'invalid annular plate');bm.free()
 for a,b in pairs:
  overlaps=tree(a).overlap(tree(b));assert not overlaps,(role,a,b,len(overlaps))
 covers=[o for o in root.children if o.name.startswith('Bolted manway lid')]
 assert len(covers)==len(tanks)
 assert all(o.dimensions.z<.051 for o in covers),(role,'raised tank cover')
 # Audit actual evaluated projections at both ends, not just the radius parameter.
 widths=[];registrations=[];seats=[];visibility=[];weld_checks=[];service_gaps=[];projection.scale.y=math.sqrt(2)
 for heading in range(4):
  root.rotation_euler.z=-heading*math.pi/2;bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
  cache.clear()
  for a,b in pairs:assert not tree(a).overlap(tree(b)),(role,heading,a,b,'projected geometry collision')
  for route,record in zip(routes,route_checks):
   ev=route.evaluated_get(dg);mesh=ev.to_mesh();count=route['pipe_ring_size']
   if role=='fuel' and heading in [0,2,3]:
    # Physical clearance alone missed the frame hiding the short fitting.
    toward=scene.camera.matrix_world.to_quaternion()@Vector((0,0,1));bands=[]
    for t in [.80,.90,.95,.99]:
     visible=0;contact_seam=0;blocked=[]
     for i in range(count):
      point=route.matrix_world@mesh.vertices[i].co.lerp(mesh.vertices[i+count].co,t)
      hit,location,normal,index,obj,matrix=scene.ray_cast(dg,point+toward*20,-toward)
      if hit and (obj.original==route or obj.name.startswith('Welded tank neck |')):visible+=1
      elif hit and t==.80 and obj.name.startswith('Tank rolled seam'):contact_seam+=1
      elif hit:blocked.append(obj.name)
     # The root can meet the tank's own rolled seam; no frame/strap may hide it.
     assert not blocked and visible>=(24 if t==.80 else 30),(role,heading,t,'obscured exposed fitting',visible,blocked)
     bands.append({'route_fraction':t,'visible_samples':visible,'samples':count,'tank_contact_seam_samples':contact_seam,'blocking_objects':blocked})
    visibility.append({'heading':heading,'bands':bands})
   for which,direction,vertices in [('tank',record['socket_direction'],mesh.vertices[:count]),('socket',record['socket_direction'],mesh.vertices[-count:])]:
    axis=0 if (direction//4+heading)%2==0 else 1
    points=[world_to_camera_view(scene,scene.camera,route.matrix_world@v.co)[axis]*scene.camera.data.ortho_scale for v in vertices]
    width=max(points)-min(points);assert abs(width-2*native_radius)<.008,(role,heading,which,'projected bore mismatch',width)
    widths.append(width)
   tail=[sum((route.matrix_world@v.co for v in mesh.vertices[i*count:(i+1)*count]),Vector())/count
         for i in [len(mesh.vertices)//count-2,len(mesh.vertices)//count-1]]
   x,y=record['anchor'];dx,dy=vectors[record['socket_direction']//4]
   for _ in range(heading):x,y=-y,x;dx,dy=-dy,dx
   outward=Vector((dx,-dy,0));axial_scale=math.sqrt(2) if dy else 1
   entry_world=Vector((x+dx*entry,-(y+dy*entry)*math.sqrt(2)-picture_shift*math.sqrt(2),.36))
   if role=='fuel' and heading in [0,2]:
    # A ray-visible but two-pixel-long fitting remained unreadable in-game.
    # Measure actual tank silhouette to sleeve space at native 32px/tile.
    outer=max((tanks[0].matrix_world@v.co).dot(outward) for v in tanks[0].data.vertices)
    exposed_pixels=(entry_world.dot(outward)-outer)*32
    assert exposed_pixels>=8,(role,heading,'insufficient side-view fitting exposure',exposed_pixels)
    service_gaps.append({'heading':heading,'native_exposed_pixels':exposed_pixels})
   join_world=entry_world+outward*(record['join_distance']-entry)*axial_scale
   error=(tail[1]-join_world).length
   assert error<1e-5,(role,heading,'native socket entry misalignment',error)
   assert (tail[1]-tail[0]).normalized().dot(outward)>.99999,(role,heading,'tilted mating tail')
   assert abs(tail[0].z-tail[1].z)<1e-6,(role,heading,'route changes height')
   inlet_clearance(tanks[0],[route.matrix_world@v.co for v in mesh.vertices[:count]])
   neck=next(o for o in necks if o['source_route']==route.name)
   evaluated_neck=neck.evaluated_get(dg);neck_mesh=evaluated_neck.to_mesh()
   roots=[neck.matrix_world@v.co for v in neck_mesh.vertices[:count]]
   root_embed=min(inlet_clearance(tanks[0],roots))
   tips=[neck.matrix_world@v.co for v in neck_mesh.vertices[-count:]]
   for point in tips:
    delta=point-tail[1];radial=delta-outward*delta.dot(outward)
    assert abs(radial.length-native_radius)<1e-5,(role,heading,'weld neck narrows barrel')
   if neck['exposed_in_cardinal_views'][heading]:
    assert max((point-entry_world).dot(outward) for point in tips)<-.01,(role,heading,'weld neck intersects connector')
   else:
    # Do not trust the pose label to exempt a protruding neck from clearance.
    inlet_clearance(tanks[0],[neck.matrix_world@v.co for v in neck_mesh.vertices])
   weld_checks.append({'heading':heading,'route':route.name,'root_embed':root_embed,'exposed':bool(neck['exposed_in_cardinal_views'][heading]),'tail_radius':native_radius})
   evaluated_neck.to_mesh_clear()
   if role=='liquid-buffer':
    for part in [o for o in root.children if o.name.startswith('Buffer adapter ') and o.get('source_route')==route.name]:
     ev_part=part.evaluated_get(dg);part_mesh=ev_part.to_mesh()
     pts=[part.matrix_world@v.co for v in part_mesh.vertices]
     assert min(p.z for p in pts)>.004, (part.name,heading,'hardware enters ground')
     if neck['exposed_in_cardinal_views'][heading]:
      assert max((p-entry_world).dot(outward) for p in pts)<-.005,(part.name,heading,'adapter intersects native sleeve')
     if 'machined flange' in part.name:
      radii=[((p-tail[1])-outward*(p-tail[1]).dot(outward)).length for p in pts]
      assert abs(min(radii)-native_radius)<1e-5 and max(radii)<.376,(part.name,'flange changes bore or is oversized')
      thickness=max((pts[3*count+i]-pts[i]).dot(outward) for i in range(count))
      assert thickness<.031,(part.name,'oversized plate thickness')
      if neck['exposed_in_cardinal_views'][heading]:
       front = [point.dot(outward) for point in pts[2*count:]]
       assert max(front)-min(front)<1e-5,(part.name,heading,'retaining face is not planar')
       assert max(radii)-native_radius>.04,(part.name,'retaining lip blends into barrel')
     if 'hex bolts' in part.name:
      assert len(pts)==6*12,(part.name,'missing fasteners')
      for i in range(6):
       head=pts[i*12:(i+1)*12]
       assert max((p-q).length for p in head for q in head)<.04,(part.name,'oversized bolt head')
     ev_part.to_mesh_clear()
   # Full inlet-ring containment proves positive volume contact even when a
   # short fitting is wholly inside the tank; surface-only BVH misses that case.
   overlap=(tail[1]-entry_world).dot(outward)
   assert overlap>.05*axial_scale,(role,heading,'no sleeve overlap')
   registrations.append(error);seats.append({'heading':heading,'horizontal_route':True,'straight_overlap':overlap,'axis_alignment':(tail[1]-tail[0]).normalized().dot(outward)})
   ev.to_mesh_clear()
 results.append({'role':role,'size':3,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'connected_routes':route_checks,'nonintersecting_pairs':len(pairs),'projected_nonintersecting_pairs':4*len(pairs),'closed_outward_flange_meshes':len(flanges),'pressure_vessels':len(tanks),'flat_tank_covers':len(covers),'projected_endpoint_diameters':widths,'native_socket_entry_errors':registrations,'connector_seats':seats,'fuel_exposed_fitting_visibility':visibility,'fuel_side_service_gaps':service_gaps,'weld_necks':weld_checks,'status':'passed'})
 print('FULL BORE / TANK JOINT / CLEARANCE PASSED',role,len(pairs),flush=True)
(repo/'assets/depots/junction-validation.json').write_text(json.dumps({'status':'passed','connector_source_sha256':hashlib.sha256(connector_source.read_bytes()).hexdigest(),'connector_rear_entry':entry,'native_diameter_tiles':2*native_radius,'variants':len(results),'nonintersecting_pairs':sum(r['nonintersecting_pairs'] for r in results),'scope':'Every pipe ring retains native radius; full inlet ring enters tank; routes overlap straight rotating connector sleeves. All routes are horizontal and straight at ground-pipe height; complete inlet rings remain inside the single actual pressure-shell cross section in every heading. Native overlap and diameter checked. Structural/flange clearance and flat covers checked. Intentional tank welds excluded; not a hydraulic simulation or full-client acceptance.','results':results},indent=2)+'\n')
