"""Build editable depot masters. Blender 4.3+, no external texture files."""
import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--role', default='all')
parser.add_argument('--size', type=int, choices=[1, 3], default=3)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
ROLES = ['provider','request','buffer','fuel','liquid-provider','liquid-request','liquid-buffer']
ROLE_COLORS = {'provider':[.64,.23,.18], 'request':[.23,.42,.69], 'buffer':[.42,.52,.24], 'fuel':[.83,.58,.15]}
# The road network monitor (prototypes/road-monitor.lua): a 1x1 combinator in the liquid
# depots' finish, grey housing on a bronze skid, with a brown band where they have their role
# colour (the owner, November 5, 2026). Build it alone: --role road-monitor --size 1.
MONITOR = 'road-monitor'
MONITOR_PALETTE = {'cab':[.36,.26,.17], 'trim':[.80,.38,.12], 'cargo':[.43,.43,.40]}
# Where its wires meet its two terminal posts and its status lens sits, in model units (three
# to a tile, +Y north, +Z up), before the 1x1 build scales them to a tile; the prototype's wire
# points and activity LED are these, projected for each direction (monitor_points).
MONITOR_POSTS = {'red':(-.46,.42,1.60), 'green':(.46,.42,1.60)}
MONITOR_LENS = (.60,-.40,1.28)
# The road tunnel portal (prototypes/road-tunnel.lua): a low 1x1 arched hood in the same finish,
# its mouth to the north (+Y), where freighters drive in from the road and go under ground.
# Build it alone: --role road-tunnel --size 1.
TUNNEL = 'road-tunnel'
TUNNEL_PALETTE = MONITOR_PALETTE
# The hood's arch, in model units (three to a tile): its axis height, outer radius and shell.
TUNNEL_ARCH = (.10,1.24,.16)


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.parent = root
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new('Machined edge radius','BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        if mat in (steel, housing, rolepaint, trim):
            obj.data.materials.append(edge)
            modifier.material = 1
        obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return obj


def box(name, loc, dims, mat, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    finish(obj,name,mat,bevel)
    # Flat bare-metal faces have a local perimeter patina; curved parts use
    # the same bronze finish with a soft grazing-angle falloff instead.
    panel=bpy.data.materials.get('BASE | bronze panel patina')
    if mat==steel and panel:obj.data.materials[0]=panel
    return obj


def cylinder(name, loc, radius, depth, mat, axis='Z', vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
    obj = bpy.context.object
    if axis=='X': obj.rotation_euler[1]=math.pi/2
    if axis=='Y': obj.rotation_euler[0]=math.pi/2
    for polygon in obj.data.polygons: polygon.use_smooth=len(polygon.vertices)==4
    return finish(obj,name,mat,.008)


def torus(name,loc,radius,tube,mat,axis='Z'):
    bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=10,major_radius=radius,minor_radius=tube,location=loc)
    obj=bpy.context.object
    if axis=='X': obj.rotation_euler[1]=math.pi/2
    if axis=='Y': obj.rotation_euler[0]=math.pi/2
    for face in obj.data.polygons: face.use_smooth=True
    return finish(obj,name,mat)


def pipe(name,points,radius=.045,mat=None):
    curve=bpy.data.curves.new(name,'CURVE')
    curve.dimensions='3D'
    curve.bevel_depth=radius
    curve.bevel_resolution=3
    curve.resolution_u=12
    spline=curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for point,co in zip(spline.bezier_points,points):
        point.co=co
        point.handle_left_type=point.handle_right_type='AUTO'
    obj=bpy.data.objects.new(name,curve)
    scene.collection.objects.link(obj)
    return finish(obj,name,mat or copper)


def rigid_pipe(name,points,radius=.20,bend=.26,native=False):
    # Explicit tangent sections prevent automatic Bezier handles bowing away from unions.
    points=[Vector(p) for p in points];path=[points[0]]
    tangents=[(points[1]-points[0]).normalized()]
    for i in range(1,len(points)-1):
        incoming=points[i]-points[i-1];outgoing=points[i+1]-points[i]
        distance=min(bend,incoming.length*(.9 if i==1 else .45),outgoing.length*(.9 if i==len(points)-2 else .45))
        before=points[i]-incoming.normalized()*distance
        path.append(before)
        u=incoming.normalized();v=outgoing.normalized();tangents.append(u)
        assert abs(u.dot(v))<1e-6, 'Bulk elbow requires orthogonal tangent sections'
        assert distance>radius, 'Elbow centerline radius must exceed tube radius'
        center=before+v*distance
        for step in range(1,17):
            angle=math.pi/2*step/16
            path.append(center-v*distance*math.cos(angle)+u*distance*math.sin(angle))
            tangents.append(v*math.sin(angle)+u*math.cos(angle))
    path.append(points[-1]);tangents.append((points[-1]-points[-2]).normalized())
    if native:
        # Centerlines follow the logical tile grid. Cross sections keep native
        # circular dimensions instead of inheriting the grid's Y stretch.
        verts=[];faces=[];centers=[];count=32
        previous=None;u=None
        for i,center in enumerate(path):
            tangent=tangents[i]  # exact arc tangent; uneven ring spacing must not skew the bore
            if previous is None:
                u=tangent.cross(Vector((0,0,1))).normalized()
                if u.length<.1:u=Vector((1,0,0))
            else:u=previous.rotation_difference(tangent)@u
            v=tangent.cross(u).normalized();previous=tangent
            for j in range(count):
                angle=math.tau*j/count
                verts.append(center+radius*(u*math.cos(angle)+v*math.sin(angle)));centers.append(center)
            if i:
                for j in range(count):faces.append(((i-1)*count+j,(i-1)*count+(j+1)%count,i*count+(j+1)%count,i*count+j))
        faces += [tuple(reversed(range(count))),tuple((len(path)-1)*count+j for j in range(count))]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);finish(obj,name,steel)
        for face in mesh.polygons:face.use_smooth=len(face.vertices)==4
        obj['native_pipe_radius']=radius;obj['pipe_ring_size']=count
        obj['pipe_centerline']=json.dumps([list(p) for p in path])
        native_cross_sections(obj,centers)
        if name.startswith('Factory full bore tank route'):
            # A straight ground-level barrel moves as a rigid unit to the native
            # picture's screen calibration. Its deep inlet stays within the tank.
            assert len(path)==2, 'Ground-level factory routes must be straight'
            for axis,label in [(0,'Native seam X'),(1,'Native seam Y')]:
                key=obj.shape_key_add(name=label);key.slider_min=-1
                for vertex in key.data:vertex.co[axis]+=1
        return obj
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D'
    curve.bevel_depth=radius;curve.bevel_resolution=4;curve.use_fill_caps=True
    spline=curve.splines.new('POLY');spline.points.add(len(path)-1)
    for point,co in zip(spline.points,path):point.co=(*co,1)
    obj=bpy.data.objects.new(name,curve);scene.collection.objects.link(obj)
    return finish(obj,name,steel)


def native_cross_sections(obj,centers):
    obj.shape_key_add(name='Basis')
    factor=1/math.sqrt(2)-1
    for axis,name in [(1,'Native circle north south'),(0,'Native circle east west')]:
        key=obj.shape_key_add(name=name)
        for vertex,center in zip(key.data,centers):vertex.co[axis]+=(vertex.co[axis]-center[axis])*factor


def native_nozzle_parts(parts,center):
    # The flange, gasket and fasteners share the pipe's circular projection.
    for obj in parts:
        if obj.type!='MESH':continue
        transform=obj.matrix_basis.copy();inverse=transform.inverted();centers=[]
        for vertex in obj.data.vertices:
            point=transform@vertex.co
            centers.append(inverse@Vector((center[0],point.y,center[2])))
        # Work in logical coordinates so rotated bolt meshes share the same radial frame.
        obj.data.transform(transform);obj.matrix_basis=Matrix.Identity(4)
        native_cross_sections(obj,[transform@c for c in centers])


def bolt(loc,axis='Z',radius=.028):
    head=cylinder('Brass hex fastener',loc,radius,.025,brass,axis,6)
    center=Vector(loc);center['XYZ'.index(axis)]+=.014
    cylinder('Fastener recessed hex socket',center,radius*.43,.004,black,axis,6)
    return head


def bolt_ring(x,y,z,r,count=12):
    for i in range(count):
        angle=math.tau*i/count
        bolt((x+r*math.cos(angle),y+r*math.sin(angle),z))


def lens(x,y,z):
    cylinder('Protected status bezel',(x,y,z),.09,.06,edge,'Y')
    cylinder('Status lens dark gasket',(x,y+.030,z),.067,.012,black,'Y')
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=(x,y+.037,z))
    obj=bpy.context.object;obj.scale=(.055,.023,.055)
    for face in obj.data.polygons:face.use_smooth=True
    finish(obj,'Convex coated violet status lens',violet)


def rod(name,a,b,r,mat):
    a,b=Vector(a),Vector(b)
    obj=cylinder(name,(a+b)/2,r,(b-a).length,mat)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return obj


def beam(name,a,b,width,depth,mat):
    a,b=Vector(a),Vector(b)
    obj=box(name,(a+b)/2,(width,depth,(b-a).length),mat,.018)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return obj


def taper(name,loc,bottom,top,height,mat,cut=.12):
    # Clipped corners and sloping shoulders, not a rounded primitive cube.
    def outline(w,d):
        c=min(cut,w/3,d/3)
        return [(-w/2+c,-d/2),(w/2-c,-d/2),(w/2,-d/2+c),(w/2,d/2-c),(w/2-c,d/2),(-w/2+c,d/2),(-w/2,d/2-c),(-w/2,-d/2+c)]
    verts=[(x+loc[0],y+loc[1],loc[2]+z) for w,d,z in [(*bottom,-height/2),(*top,height/2)] for x,y in outline(w,d)]
    faces=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
    return finish(obj,name,mat,.012)


def ring_arc(name,x,y,z,inner,outer,start,end,mat,depth=.10):
    steps=max(6,int((end-start)*24));verts=[]
    for zz in [z-depth/2,z+depth/2]:
        for r in [inner,outer]:
            for i in range(steps+1):
                a=start+(end-start)*i/steps;verts.append((x+r*math.cos(a),y+r*math.sin(a),zz))
    n=steps+1;faces=[]
    for i in range(steps):
        faces += [(i,i+1,n+i+1,n+i),(2*n+i,3*n+i,3*n+i+1,2*n+i+1),(i,2*n+i,2*n+i+1,i+1),(n+i,n+i+1,3*n+i+1,3*n+i)]
    faces += [(0,n,3*n,2*n),(n-1,2*n-1,4*n-1,3*n-1)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
    return finish(obj,name,mat,.012)


def chevron(x,y,z,width,mat,up=False,double=True,relief=0):
    for step in ([0,.15] if double else [0]):
        sign=-1 if up else 1
        pts=[(-.5,.18), (0,-.12),(.5,.18),(.5,.02),(0,-.28),(-.5,.02)]
        mesh=bpy.data.meshes.new('Role direction stencil')
        mesh.from_pydata([(x+a*width,y,z+sign*(b*width+step)) for a,b in pts],[],[tuple(range(6))]);mesh.update()
        obj=bpy.data.objects.new('Inset directional chevron',mesh);scene.collection.objects.link(obj);finish(obj,obj.name,mat)
        if relief:
            solid=obj.modifiers.new('Raised metal emblem','SOLIDIFY');solid.thickness=relief;solid.offset=0


def hinge(x,y,z,axis='X',width=.28):
    cylinder('Hinge hardened pin',(x,y,z),.063,width+.08,edge,axis)
    for offset in [-width/2,width/2]:
        loc=(x+offset,y,z) if axis=='X' else (x,y+offset,z)
        box('Orange hinge ear',loc,(.09,.19,.22) if axis=='X' else (.19,.09,.22),trim,.022)
        cylinder('Hinge cap',loc,.075,.105,steel,axis)


def foundation(role):
    if role.startswith('liquid-'):
        # Open steel skid: individual rails and crossmembers, no solid slab/skirt.
        for x in [-1.32,1.32]:
            box('Open skid longitudinal rail',(x,0,.0175 if role=='liquid-buffer' else .16),(.15,2.76,.035 if role=='liquid-buffer' else .18),steel,.012)
        for y in [-1.30,1.30]:
            box('Open skid transverse rail',(0,y,.0175 if role=='liquid-buffer' else .16),(2.52,.15,.035 if role=='liquid-buffer' else .18),steel,.018)
        for x in [-.72,.72]:
            box('Tank load bearing crossmember',(x,0,.010 if role=='liquid-buffer' else .30),(.16,2.70,.020 if role=='liquid-buffer' else .20),steel,.016)
        for x in [-1.25,1.25]:
            for y in [-1.25,1.25]:
                taper('Bolted skid foot',(x,y,.015 if role=='liquid-buffer' else .14),(.34,.34),(.27,.27),.030 if role=='liquid-buffer' else .26,steel,.06)
                bolt((x,y,.041 if role=='liquid-buffer' else .29),radius=.045)
    else:
        taper('Low steel foundation pan',(0,0,.07),(2.91,2.91),(2.84,2.84),.14,steel,.19)
        for x in [-1.25,1.25]:
            for y in [-1.25,1.25]:
                taper('Cast octagonal corner shoe',(x,y,.30),(.43,.43),(.35,.35),.40,steel,.10)
                bolt((x,y,.52),radius=.06)
        for sign in [-1,1]:
            box('Side structural sill',(sign*1.34,0,.28),(.14,2.26,.28),steel,.018)
        box('Rear structural sill',(0,-1.34,.28),(2.26,.14,.28),steel,.018)


def cargo_loading(role):
    # Built after case compression: the belt surface stays 0.18 tiles above ground.
    mouths=[(-.49,.68),(.49,.68)] if role=='buffer' else [(0,1.36)]
    if role=='buffer':
        box('Buffer central loading jamb',(0,1.13,.98),(.14,.24,1.63),steel,.018)
        marking=edge.copy();marking.name='BASE | worn ochre conveyor chevrons'
        ramp=marking.node_tree.nodes['Surface pigment'].color_ramp
        ramp.elements[0].color=(.18,.14,.055,1);ramp.elements[1].color=(.46,.35,.12,1)
        marking.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.08
    for index,(x,width) in enumerate(mouths):
        box('Continuous conveyor carcass',(x,.24,.105),(width,2.46,.10),rubber,.035)
        box('Continuous conveyor carrying belt',(x,.24,.158),(width-.045,2.46,.034),rubber,.012)
        for i in range(20):
            y=-.90+i*.12
            box('Conveyor flat tread',(x,y,.178),(width-.075,.092,.012),steel,.004)
            # Direction marks belong to the belt, with Buffer's two lanes opposed.
            if i%4==1:
                sign=-1 if role=='request' or (role=='buffer' and index==1) else 1
                if role=='buffer':
                    # Native belts repeat small stemless chevrons on dark treads.
                    points=[(-.16,-.07),(0,.035),(.16,-.07),(.16,.005),(0,.11),(-.16,.005)]
                    mesh=bpy.data.meshes.new('Stemless belt chevron stencil')
                    mesh.from_pydata([(x+dx,y+sign*dy,.191) for dx,dy in points],[],[tuple(range(6)) if sign>0 else tuple(reversed(range(6)))]);mesh.update()
                    obj=bpy.data.objects.new('Buffer outbound belt chevron' if sign>0 else 'Buffer inbound belt chevron',mesh)
                    scene.collection.objects.link(obj);finish(obj,obj.name,marking)
                else:
                    for side in [-1,1]:
                        beam('Conveyor painted direction chevron',(x+side*width*.24,y-sign*.025,.187),(x,y+sign*.035,.187),.024,.006,rolepaint)
        for side in [-1,1]:
            xx=x+side*(width/2+.045)
            box('Low conveyor side channel',(xx,.23,.16),(.075,2.44,.18),steel,.012)
            box('Loading vertical guide',(xx,1.10,.83),(.105,.20,1.30),steel,.015)
            box('Orange guide wear shoe',(xx,1.215,.38),(.11,.04,.34),trim,.009)
            for z in [.25,.52,1.26]:bolt((xx,1.245,z),'Y',.025)
        box('Retracted loading shutter',(x,1.08,1.60),(width,.17,.44),housing,.022)
        box('Loading shutter identity band',(x,1.172,1.65),(width-.06,.022,.21),rolepaint,.004)
        chevron(x,1.188,1.62,width*.52,edge,role=='request' or (role=='buffer' and index==1),double=False)
        box('Loading lintel',(x,1.12,1.365),(width+.14,.24,.09),steel,.012)
        panel_fasteners(x,1.185,1.76,width-.13,.06)
        # A dark rear wall is behind the usable throat, not immediately inside it.
        box('Loading bay rear lining',(x,-.93,.81),(width,.035,1.22),black,.008)
        for side in [-1,1]:
            cylinder('Enclosed belt drive endcap',(x+side*(width/2+.045),.96,.18),.065,.025,copper,'X')


def fuel_hopper():
    # Four open tapered walls feed a real outlet; no solid pedestal fills the throat.
    top=[(-1.19,-1.08,1.80),(-.09,-1.08,1.80),(-.09,.64,1.80),(-1.19,.64,1.80)]
    bottom=[(-.93,-.16,1.05),(-.35,-.16,1.05),(-.35,.36,1.05),(-.93,.36,1.05)]
    mesh=bpy.data.meshes.new('Open fuel funnel');mesh.from_pydata(bottom+top,[],[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)]);mesh.update()
    obj=bpy.data.objects.new('Hollow tapered solid fuel hopper',mesh);scene.collection.objects.link(obj);finish(obj,obj.name,housing,.008)
    wall=obj.modifiers.new('Hopper plate thickness','SOLIDIFY');wall.thickness=.045;wall.offset=-1
    for x in [-1.165,-.115]:box('Hopper upper side wall',(x,-.22,2.02),(.05,1.72,.44),housing,.018)
    for y in [-1.055,.615]:box('Hopper upper end wall',(-.64,y,2.02),(1.0,.05,.44),housing,.018)
    box('Hopper outlet back wall',(-.64,-.16,.97),(.58,.055,.20),steel,.008)
    for x in [-.93,-.35]:box('Hopper outlet side wall',(x,.10,.97),(.05,.52,.20),steel,.008)
    # A bounded open trough begins below the throat and exits the front edge.
    verts=[(-.93,.04,.88),(-.35,.04,.88),(-.35,1.36,.28),(-.93,1.36,.28),
           (-.93,.04,1.16),(-.35,.04,1.16),(-.35,1.36,.56),(-.93,1.36,.56)]
    mesh=bpy.data.meshes.new('Fuel discharge trough');mesh.from_pydata(verts,[],[(0,3,2,1),(0,4,7,3),(1,2,6,5)]);mesh.update()
    obj=bpy.data.objects.new('Connected open fuel discharge chute',mesh);scene.collection.objects.link(obj);finish(obj,obj.name,steel,.008)
    wall=obj.modifiers.new('Chute plate thickness','SOLIDIFY');wall.thickness=.045;wall.offset=0
    for x in [-.93,-.35]:
        beam('Chute side wear rail',(x,.04,1.16),(x,1.36,.56),.055,.055,edge)
        box('Outlet gate guide',(x,.40,1.13),(.09,.12,.47),steel,.012)
        box('Orange outlet gate actuator',(x,.40,1.39),(.10,.15,.18),trim,.012)
        bolt((x,.49,1.38),'Y',.024)
    box('Raised hopper metering gate',(-.64,.40,1.30),(.50,.055,.30),steel,.012)
    box('Chute discharge wear lip',(-.64,1.365,.285),(.61,.065,.04),edge,.008)
    for x in [-.90,-.38]:beam('Chute support leg',(x,1.17,.15),(x,1.17,.39),.09,.10,steel)


def cargo_body(role):
    # A true recess: side walls and a back plate leave the transfer mouth open.
    box('Cargo rear wall',(0,-1.09,1.35),(2.38,.23,1.86),housing,.055)
    for x in [-1.08,1.08]:
        box('Cargo side armored wall',(x,-.05,1.35),(.22,2.22,1.86),housing,.045)
        box('Wide side identification belt',(x*1.113,-.07,1.44),(.025,2.06,.42),rolepaint,.005)
        for y in [-.65,.35]:
            box('Side panel expansion seam',(x*1.115,y,1.31),(.027,.026,1.58),black,.002)
        box('Side sill vent recess',(x*1.117,-.15,.61),(.035,1.51,.18),black,.006)
        for y in [i*.12-.78 for i in range(12)]:
            box('Side sill grille slat',(x*1.139,y,.61),(.025,.025,.15),edge,.003)
    box('Interior rear bulkhead',(0,-.95,1.22),(2.1,.05,1.52),black)
    box('Cargo roof casting',(0,0,2.25),(2.48,2.45,.19),steel,.055)
    for x in [-1.19,1.19]:
        for y in [-1.16,1.16]:
            taper('Full height corner casting',(x,y,1.23),(.50,.44),(.50,.44),1.66,steel,.075)
            taper('Sloped armored shoulder',(x,y,2.17),(.54,.54),(.40,.40),.43,steel,.09)
            cylinder('Recessed corner cap',(x,y,2.403),.106,.045,edge)
            cylinder('Corner cap center',(x,y,2.432),.071,.018,steel)
            box('Corner painted belt',(x,y,1.43),(.505,.445,.43),rolepaint,.03)
            # Solid armor plates leave the belt at mid-height.
            box('Corner latch plate',(x,y+.195,1.91),(.22,.07,.23),steel)
            hinge(x,y+.24,1.89,width=.14)
            box('Orange vertical lock',(x,y+.22,1.70),(.07,.08,.23),trim,.012)
            bolt((x,y+.195,.71),'Y',.04)
    for x in [-1.17,1.17]:
        rod('Roof longitudinal actuator',(x,-.92,2.28),(x,.92,2.28),.055,edge)
        for y in [-.80,.80]:
            cylinder('Actuator bronze gland',(x,y,2.28),.085,.16,copper,'Y')
            hinge(x,y,2.29,'Y',.16)
    # Shared single circular roof, tinted by depot role.
    for x in [-.80,.80]:
        for y in [-.78,.78]:
            taper('Red roof quarter backing',(x,y,2.374),(.52,.53),(.48,.49),.06,rolepaint,.08)
            bolt((x,y,2.42))
    cylinder('Hatch shadow reveal',(0,0,2.38),1.05,.06,black,vertices=64)
    cylinder('Provider sealed circular lid',(0,0,2.43),.87,.11,rolepaint,vertices=64)
    ring_arc('Inner machined seat',0,0,2.48,.78,.87,0,math.tau,edge,.07)
    for quadrant in range(4):
        a=quadrant*math.pi/2+.08
        ring_arc('Segmented outer lock ring',0,0,2.51,.91,1.09,a,a+math.pi/2-.16,steel,.20)
        for offset in [.20,.67,1.15]:
            mid=a+offset;bolt((math.cos(mid),math.sin(mid),2.64),radius=.035)
    box('Hatch locking bridge',(0,0,2.56),(1.85,.22,.15),steel,.035)
    cylinder('Central rotary lock surround',(0,0,2.62),.29,.12,edge)
    cylinder('Central rotary lock',(0,0,2.69),.22,.05,steel)
    box('Lock screwdriver slot',(0,0,2.72),(.27,.035,.012),black,.002)
    for x in [-.96,.96]:
        hinge(x,0,2.53,'Y',.36)
        box('Heavy orange radial lock clamp',(x,0,2.64),(.20,.40,.10),trim,.018)
        cylinder('Radial clamp hardened cross pin',(x,0,2.71),.063,.45,edge,'Y')
    for y in [-.99,.99]: hinge(0,y,2.44,width=.35)
    bolt_ring(0,0,2.50,.72,12)
    if role=='request': lens(-1.19,1.435,1.91)
    for x in [-.80,.80]:
        box('Rear armored service hatch',(x,-1.222,1.23),(.58,.05,1.10),steel,.025)
        for z in [.87,1.0,1.13,1.26]: box('Rear louver',(x,-1.26,z),(.41,.035,.045),edge,.006)
    # Side accumulator tank makes the silhouette mechanically specific.
    for sign in [-1,1]:
        cylinder('Side hydraulic accumulator',(sign*1.28,-.57,.94),.12,.63,steel)
        for z in [.65,.80,1.18,1.27]:cylinder('Accumulator collar',(sign*1.28,-.57,z),.135,.045,copper)
        pipe('Accumulator return tube',[(sign*1.28,-.73,.66),(sign*1.32,-.81,1.18),(sign*1.18,-.86,1.87)],.025,copper)


def tank_cap_settings(role,r):
    # Radius multiplier before the existing lid/collar proportions; long axis
    # follows each capsule. Buffer lid area stays approximately unchanged.
    if role=='fuel':return r*1.20,.16,1
    if role=='liquid-buffer':return .28/.38,.095,0
    return r*.76,0,0


def form_obround_cap(obj,x,y,span,axis):
    transform=obj.matrix_basis.copy();inverse=transform.inverted();center=[x,y][axis]
    for vertex in obj.data.vertices:
        point=transform@vertex.co;offset=point[axis]-center
        if abs(offset)>1e-7:point[axis]+=math.copysign(span,offset)
        vertex.co=inverse@point


def vessel(x,y,r,height,dome=.42,span=0,depth_span=0):
    before=set(root.children)
    bottom=.035; shoulder=height-dome*r
    profile=[(r*.94,bottom),(r,bottom+.08),(r,shoulder)]
    for i in range(1,17):
        t=math.pi/2*i/16;profile.append((r*math.cos(t),shoulder+dome*r*math.sin(t)))
    verts=[(x+radius*math.cos(i*math.tau/64),y+radius*math.sin(i*math.tau/64),z) for radius,z in profile for i in range(64)]
    faces=[(j*64+i,j*64+(i+1)%64,(j+1)*64+(i+1)%64,(j+1)*64+i) for j in range(len(profile)-1) for i in range(64)]
    mesh=bpy.data.meshes.new('Rolled pressure shell');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('Broad domed pressure vessel',mesh);scene.collection.objects.link(obj);finish(obj,obj.name,housing)
    for face in mesh.polygons:face.use_smooth=True
    belt=.41+.53*(height-.41)
    cylinder('Wide tank identification belt',(x,y,belt),r+.009,.32,rolepaint,vertices=64)
    for z in [belt-.17,belt+.17,shoulder+.015]:torus('Tank rolled seam',(x,y,z),r+.012,.012,edge)
    cylinder('Heavy lower shell flange',(x,y,.025),r+(.018 if span else .045),.020,steel,vertices=64)
    bolt_ring(x,y,.055,r-.04,20 if r>.8 else 14)
    before_lid=set(root.children)
    top=height
    cap_r,cap_span,cap_axis=tank_cap_settings(root['role'],r)
    for name,radius,z,depth,material in [('Manway machined collar',cap_r*.40,top+.005,.018,copper),('Bolted manway lid',cap_r*.38,top+.030,.045,steel)]:
        part=cylinder(name,(x,y,z),radius,depth,material)
        if cap_span:form_obround_cap(part,x,y,cap_span,cap_axis)
    for i in range(12):
        a=math.tau*i/12;point=[x+cap_r*.30*math.cos(a),y+cap_r*.30*math.sin(a),top+.065]
        offset=point[cap_axis]-[x,y][cap_axis]
        if abs(offset)>1e-7:point[cap_axis]+=math.copysign(cap_span,offset)
        bolt(point)
    lid=set(root.children)-before_lid
    for i in range(4):
        a=([math.pi/3,2*math.pi/3,4*math.pi/3,5*math.pi/3][i] if depth_span else math.pi/4+i*math.pi/2);dx,dy=math.cos(a),math.sin(a)
        # Ribbon follows the actual elliptical dome rather than cutting through it.
        profile=[(r+.04,.78),(r+.04,shoulder)]
        for k in range(1,12):
            t=(math.pi/2)*k/16
            profile.append((r*math.cos(t)+.04,shoulder+dome*r*math.sin(t)+.015))
        width=.20 if r>.8 else .14
        verts=[]
        for radius,z in profile:
            for side in [-1,1]:
                verts.append((x+dx*radius-side*dy*width/2,y+dy*radius+side*dx*width/2,z))
        mesh=bpy.data.meshes.new('Continuous formed tank strap')
        mesh.from_pydata(verts,[],[(2*k,2*k+1,2*k+3,2*k+2) for k in range(len(profile)-1)]);mesh.update()
        obj=bpy.data.objects.new('Continuous armored retaining strap',mesh);scene.collection.objects.link(obj)
        finish(obj,obj.name,steel)
        solid=obj.modifiers.new('Strap plate thickness','SOLIDIFY');solid.thickness=.045;solid.offset=1
        bevel=obj.modifiers.new('Strap worn edge','BEVEL');bevel.width=.008;bevel.segments=2
        obj.data.materials.append(edge);bevel.material=1
        for radius,z in [profile[0],profile[-1]]:bolt((x+dx*radius,y+dy*radius,z+.05),radius=.04)
        box('Orange strap buckle',(x+dx*(r+.045),y+dy*(r+.045),shoulder-.05),(.14,.14,.19),trim)
    if span or depth_span:
        # One capsule shell, band and four corner straps; the independently
        # shaped service cover and its bolt heads stay outside this deformation.
        for part in set(root.children)-before-lid:
            transform=part.matrix_basis.copy();inverse=transform.inverted()
            for vertex in part.data.vertices:
                point=transform@vertex.co
                if abs(point.x-x)>1e-7:point.x+=math.copysign(span,point.x-x)
                if span:point.y=y+(point.y-y)*1.3
                elif abs(point.y-y)>1e-7:point.y+=math.copysign(depth_span,point.y-y)
                vertex.co=inverse@point
    return top


def pump(x,y,z=.69,scale=1):
    start=set(root.children)
    box('Pump foundation skid',(x+.24,y,.48),(1.28,.51,.15),steel,.025)
    cylinder('Ribbed electric motor',(x,y,z),.23,.53,steel,'X')
    for a in range(12):
        t=a*math.tau/12
        box('Motor longitudinal cooling fin',(x,y+.235*math.cos(t),z+.235*math.sin(t)),(.47,.025,.025),edge,.004)
    for dx in [-.26,.26]:cylinder('Motor end bell',(x+dx,y,z),.25,.075,steel,'X')
    cylinder('Cast pump volute',(x+.54,y,z),.30,.52,steel,'X')
    cylinder('Pump volute bolted end cover',(x+.815,y,z),.26,.03,copper,'X')
    for i in range(8):
        a=i*math.tau/8;bolt((x+.838,y+.22*math.cos(a),z+.22*math.sin(a)),'X',.025)
    for dx in [-.16,.16,.54]:
        box('Pump seated mounting cradle',(x+dx,y,.60),(.14,.40,.14),steel,.02)
    cylinder('Motor fan cover',(x-.31,y,z),.22,.06,steel,'X')
    for d in [i*.035 for i in range(-5,6)]:
        length=2*math.sqrt(.19**2-d*d)
        box('Fan cross grille',(x-.345,y,z+d),(.015,length,.007),edge,.002)
        box('Fan cross grille',(x-.345,y+d,z),(.015,.007,length),edge,.002)
    for dx in [-.33,.33]:
        for dy in [-.18,.18]:bolt((x+dx,y+dy,.58),radius=.035)
    parts=list(set(root.children)-start)
    if scale!=1:
        pivot=Vector((x,y,.405))
        transform=Matrix.Translation(pivot)@Matrix.Diagonal((scale,scale,scale,1))@Matrix.Translation(-pivot)
        for obj in parts:obj.matrix_basis=transform@obj.matrix_basis
    return parts


def actuator(x,y,z,width=.34):
    # Enclosed motor/gear housing, with no hand-operated stem or wheel.
    box('Sealed automatic flow actuator',(x,y,z),(width,.32,.26),steel,.04)
    box('Actuator armored access lid',(x,y,z+.15),(width+.03,.34,.055),housing,.015)
    for dx in [-width*.32,width*.32]:bolt((x+dx,y,z+.19),radius=.026)
    box('Actuator role stripe',(x,y+.167,z),(width*.72,.025,.06),rolepaint,.005)


def fluids(role):
    for x in [-1.24,1.24]:
        for y in [-1.24,1.24]:
            taper('Machinery frame upright',(x,y,.56),(.23,.23),(.18,.18),.62,steel,.04)
            bolt((x,y,.89),radius=.035)
            beam('Orange frame knee brace',(x*.84,y,.25),(x,y,.65),.075,.09,trim)
    if role=='fuel':
        # Keep the hopper-side edge and full length; expose the side pipe neck.
        vessel(.56,0,.50,2.03,dome=.25,depth_span=.67)
        fuel_hopper()
        box('Fuel front yellow band',(-.64,.651,1.98),(1.0,.026,.24),rolepaint)
        for x in [-1.203,-.077]: box('Fuel side yellow band',(x,-.22,1.98),(.026,1.62,.24),rolepaint)
        taper('Hopper cast rim',(-.64,-.22,2.28),(1.21,1.83),(1.08,1.70),.18,steel,.09)
        taper('Armored hopper top hatch',(-.64,-.22,2.40),(.94,1.53),(.87,1.46),.10,housing,.10)
        box('Fuel hopper roof identification strip',(-.64,-.22,2.456),(.22,1.28,.012),rolepaint,.004)
        for y in [-.91,.48]:hinge(-.64,y,2.40,width=.55)
        for x in [-1.18,-.10]:
            for y in [-1.02,.58]:
                beam('Hopper support post',(x,y,.45),(x,y,2.24),.11,.13,steel)
                box('Hopper post clamp',(x,y,1.24),(.16,.18,.13),trim)
        beam('Hopper diagonal brace',(-1.10,-.65,.56),(-.15,-.65,1.50),.10,.10,steel)
    elif role=='liquid-buffer':
        vessel(0,0,.88,2.05,span=.60)
        lens(-1.24,1.335,.73)
    else:
        vessel(0,0,1.15,2.20)
        lens(1.24,1.335,.73)


def roof_wear(role):
    # The old flat-roof scratches no longer match the reconstructed lids.
    pass


def flange(name,loc,r,axis='Z',mat=None,bore=None):
    x,y,z=loc
    inner=bore if bore is not None else r*.55;verts=[]
    for axial in [-.0375,.0375]:
        for radius in [inner,r]:
            for i in range(48):
                a=i*math.tau/48;u=radius*math.cos(a);v=radius*math.sin(a)
                verts.append((axial,u,v) if axis=='X' else ((u,axial,v) if axis=='Y' else (u,v,axial)))
    faces=[]
    for i in range(48):
        j=(i+1)%48
        faces.extend([(i,j,48+j,48+i),(96+i,144+i,144+j,96+j),(i,96+i,96+j,j),(48+i,48+j,144+j,144+i)])
    if axis=='Y':faces=[tuple(reversed(face)) for face in faces]
    mesh=bpy.data.meshes.new(name+' annular plate');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(name+' machined flange',mesh);scene.collection.objects.link(obj);obj.location=loc
    finish(obj,obj.name,mat or copper,.006)
    torus(name+' gasket seam',loc,r*.82,.016,black,axis)
    for i in range(8):
        a=i*math.tau/8
        if axis=='Z': point=(x+r*.79*math.cos(a),y+r*.79*math.sin(a),z+.05)
        elif axis=='Y':point=(x+r*.79*math.cos(a),y+.05,z+r*.79*math.sin(a))
        else:point=(x+.05,y+r*.79*math.cos(a),z+r*.79*math.sin(a))
        bolt(point,axis,max(.018,r*.11))


def panel_fasteners(x,y,z,w,h,axis='Y'):
    for a in [-1,1]:
        for b in [-1,1]:
            if axis=='Y':point=(x+a*w/2,y,z+b*h/2)
            elif axis=='X':point=(x,y+a*w/2,z+b*h/2)
            else:point=(x+a*w/2,y+b*h/2,z)
            cylinder('Recessed screw washer',point,.034,.014,black,axis)
            bolt(point,axis,.024)


def louvers(x,y,z,w,h,axis='Y'):
    dims=(w,.055,h) if axis=='Y' else (.055,w,h)
    box('Recessed maintenance vent',(x,y,z),dims,black,.012)
    for i in range(5):
        dims=(w*.80,.06,.025) if axis=='Y' else (.06,w*.80,.025)
        box('Angled louver blade',(x,y,z-h*.36+i*h*.18),dims,edge,.004)


def cargo_mechanics(role):
    if role=='provider':
        taper('Armored sensor pod',(0,1.15,2.18),(.50,.32),(.40,.24),.25,steel,.04)
        lens(0,1.36,2.17)
    # Repeated plate joints, hard stops and hydraulic anchors are visible on every side.
    for sign in [-1,1]:
        for y in [-.70,.28]:
            box('Side lower inset armor',(sign*1.208,y,.96),(.035,.80,.51),steel,.018)
            panel_fasteners(sign*1.235,y,.96,.68,.39,'X')
        for y in [-1.16,1.16]:
            for z in [.61,2.18]:
                box('Corner bolt socket plate',(sign*1.19,y+.265,z),(.25,.055,.22),steel,.018)
                cylinder('Corner socket machined washer',(sign*1.19,y+.30,z),.07,.025,edge,'Y')
                bolt((sign*1.19,y+.32,z),'Y',.043)
            for z in [.80,1.82]:
                box('Corner orange clamp shoe',(sign*1.19,y+.255,z),(.26,.075,.14),trim,.018)
                panel_fasteners(sign*1.19,y+.302,z,.17,.07)
        for y in [-.68,.68]:
            box('Roof perimeter overlay plate',(sign*1.06,y,2.375),(.22,.53,.035),steel,.015)
            panel_fasteners(sign*1.06,y,2.40,.13,.39,'Z')
    for a in [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]:
        for offset in [-.07,.07]:
            dx,dy=math.cos(a),math.sin(a)
            beam('Radial lock reinforcement',(dx*.99-dy*offset,dy*.99+dx*offset,2.48),(dx*1.31-dy*offset,dy*1.31+dx*offset,2.42),.075,.075,steel)
    for x in [-.57,.57]:
        box('Roof locking bridge end plate',(x,0,2.65),(.28,.25,.025),edge,.015)
        for y in [-.08,.08]:bolt((x,y,2.68),radius=.023)
    for sign in [-1,1]:
        # Accumulator mounting saddle and external protected service pipe.
        for z in [.79,1.13]:
            box('Accumulator steel saddle',(sign*1.28,-.57,z),(.27,.22,.065),steel,.01)
        pipe('Rigid external service line',[(sign*1.31,-.86,.57),(sign*1.31,-.86,1.52),(sign*1.17,-.88,2.11)],.023,copper)
        for z in [.75,1.15,1.55]:
            box('Service line retaining clip',(sign*1.31,-.86,z),(.065,.085,.06),trim,.006)


def fluid_mechanics(role):
    # Narrow rails leave open space between skid, tank mounts and corner posts.
    for sign in [-1,1]:
        service = role=='liquid-buffer' or sign==(1 if role in ['fuel','liquid-provider'] else -1)
        if not service:box('Open side scaffold rail',(sign*1.34,0,.77),(.085,2.39,.09),steel,.012)
        else:box('Rear service bay rail',(sign*1.34,-.79,.77),(.085,.80,.09),steel,.012)
        if sign==1:box('Rear scaffold rail',(0,-1.34,.65),(2.39,.085,.09),steel,.012)
        for y in ([-.87] if service else [-.87,.87]):
            # Keep Fuel's projected fitting and Buffer's enlarged shell clear.
            if role=='fuel' and sign==1:continue
            beam('Open scaffold diagonal',(sign*1.34,-1.18 if role=='liquid-buffer' else y,.25),(sign*1.34,-.86 if role=='liquid-buffer' else y*.65,.73),.065,.065,steel)
    if role=='fuel':
        pass  # Front service bay carries the full-bore pipe.
    else:
        for x in [-.96,.96]:
            box('Front open frame rail',(x,1.40,.14),(.44,.085,.10),steel,.012)
    tanks=[(.56,0,.50,2.03)] if role=='fuel' else ([(0,0,.88,2.05)] if role=='liquid-buffer' else [(0,0,1.15,2.20)])
    for x,y,r,_height in tanks:
        for a in ([math.pi/3,2*math.pi/3,4*math.pi/3,5*math.pi/3] if role=='fuel' else [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]):
            dx,dy=math.cos(a),math.sin(a)
            if role=='fuel' and dx>0:continue
            if role=='fuel':y=math.copysign(.67,dy)
            if role=='liquid-buffer':
                if dy>0:continue
                x=math.copysign(.60,dx);dy*=1.3
            beam('Pressure shell base foot',(x+dx*(r+.04),y+dy*(r+.04),.43),(x+dx*(r+.025),y+dy*(r+.025),.73),.16,.14,steel)
    if role=='fuel':
        for y in [-.77,.30]:
            for x in [-1.01,-.27]:
                box('Fuel hopper top hold-down',(x,y,2.46),(.12,.22,.07),trim,.012)
                panel_fasteners(x,y,2.505,.06,.13,'Z')
        box('Hopper inspection access cover',(-.64,.04,2.467),(.55,.40,.035),steel,.025)
        panel_fasteners(-.64,.04,2.49,.42,.27,'Z')
        for y in [-1.02,.58]:
            for x in [-1.18,-.10]:
                taper('Hopper shoulder armor',(x,y,2.18),(.23,.27),(.20,.24),.35,steel,.05)
                bolt((x,y+.15,2.18),'Y',.04)
        lens(1.24,1.335,.73)


def reference_cargo_hardware(role):
    for x in [-1.19,1.19]:
        for y in [-1.16,1.16]:
            taper('Stepped armored pillar foot',(x,y,.58),(.55,.50),(.49,.44),.34,steel,.09)
            cylinder('Corner lifting eye recess',(x,y+.255,.57),.066,.018,black,'Y')
            torus('Corner lifting eye lip',(x,y+.267,.57),.066,.012,edge,'Y')
            # Segmented outer post faces and a wraparound retaining band.
            box('Pillar face recessed panel',(x,y+.225,1.03),(.22,.028,.47),black,.014)
            box('Pillar face cast insert',(x,y+.243,1.03),(.17,.018,.40),steel,.01)
            for z in [.88,1.18]:bolt((x,y+.262,z),'Y',.026)
            taper('Orange pillar retention band',(x,y,1.66),(.515,.455),(.515,.455),.10,trim,.08)
    for y in [-.99,.99]:
        box('Raised north south roof lock',(0,y,2.60),(.34,.20,.12),trim,.018)
        for x in [-.11,.11]:bolt((x,y,2.68),radius=.027)


def reference_fluid_hardware(role):
    tanks=[(.56,0,.50,2.03)] if role=='fuel' else ([(0,0,.88,2.05)] if role=='liquid-buffer' else [(0,0,1.15,2.20)])
    for x,y,r,top in tanks:
        shoulder=top-(.25 if role=='fuel' else .42)*r
        cap_r,cap_span,cap_axis=tank_cap_settings(role,r)
        gasket=torus('Manway dark compression gasket',(x,y,top+.012),cap_r*.385,.006,black)
        if cap_span:form_obround_cap(gasket,x,y,cap_span,cap_axis)
        for a in ([math.pi/3,2*math.pi/3,4*math.pi/3,5*math.pi/3] if role=='fuel' else [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]):
            dx,dy=math.cos(a),math.sin(a)
            if role=='liquid-buffer':x=math.copysign(.60,dx);dy*=1.3
            if role=='fuel':y=math.copysign(.67,dy)
            for z in [.82,shoulder-.19]:
                start=(x+dx*(r+.055),y+dy*(r+.055),z)
                end=(x+dx*(r+.085),y+dy*(r+.085),z)
                rod('Strap transverse rivet',start,end,.033,brass)
            shoe=box('Shoulder strap lock shoe',(x+dx*(r+.05),y+dy*(r+.05),shoulder-.035),(.22,.12,.17),trim,.018)
            shoe.rotation_euler.z=a+math.pi/2
            # A second cast brace at the base is anchored to the pressure flange.
            if (role=='liquid-buffer' and dy>0) or (role=='fuel' and dx>0):continue
            beam('Tank foot diagonal gusset',(x+dx*(r+.105),y+dy*(r+.105),.44),(x+dx*(r+.03),y+dy*(r+.03),.79),.12,.12,steel)
    if role=='fuel':
        for x in [-1.18,-.10]:
            for y in [-1.02,.58]:
                taper('Fuel hopper armored lower post',(x,y,.97),(.19,.22),(.15,.19),.94,steel,.035)
                for z in [.64,1.30]:bolt((x,y+.125,z),'Y',.028)
    elif role=='liquid-provider':
        # A protected indicator on the dome corresponds to the concept's violet pod.
        cylinder('Dome instrument socket',(.52,.27,2.13),.10,.08,brass)
        cylinder('Violet pressure beacon',(.52,.27,2.22),.070,.16,violet)
        cylinder('Beacon armored top cap',(.52,.27,2.315),.10,.035,steel)
        for dx in [-.07,.07]:
            for dy in [-.07,.07]:rod('Beacon brass cage',(.52+dx,.27+dy,2.16),(.52+dx,.27+dy,2.30),.012,brass)

def monitor_body():
    """The road network monitor, at depot scale (3 units to a tile) for the 1x1 build to scale."""
    # Bronze skid: two rails and four bolted feet, as under the liquid depots' tanks.
    for y in (-.62,.62):
        box('Monitor skid rail',(0,y,.08),(2.10,.20,.16),steel,.018)
    for x in (-.92,.92):
        for y in (-.62,.62):
            taper('Bolted monitor foot',(x,y,.09),(.30,.30),(.24,.24),.18,steel,.05)
            bolt((x,y,.19),radius=.04)
    # Grey housing and lid, the liquid provider's tank shell, with a brown band around the walls,
    # a bronze rim round the lid and a bronze strap across it, as the tank has its straps.
    box('Monitor housing shell',(0,0,.66),(1.80,1.40,1.00),housing,.06)
    box('Monitor identification band',(0,0,.70),(1.86,1.46,.22),rolepaint,.03)
    box('Monitor housing lid',(0,0,1.20),(1.84,1.44,.10),housing,.03)
    for loc,dims in [((0,-.74,1.21),(1.96,.08,.14)),((0,.74,1.21),(1.96,.08,.14)),
                     ((-.94,0,1.21),(.08,1.40,.14)),((.94,0,1.21),(.08,1.40,.14))]:
        box('Monitor bronze lid rim',loc,dims,steel,.012)
    box('Monitor bronze lid strap',(0,.02,1.265),(1.90,.18,.03),steel,.008)
    for x in (-.80,.80):
        bolt((x,.02,1.285),radius=.03)
    # Clasps holding the lid on, two to a long side.
    for x in (-.58,.58):
        for y,sign in ((-.75,-1),(.75,1)):
            box('Monitor lid clasp',(x,y+sign*.02,1.00),(.16,.06,.34),trim,.012)
            bolt((x,y+sign*.055,1.08),'Y',radius=.025)
    # Front gauge window: a dark recess with a gauge face. The status lens is on the lid, where
    # it shows whichever way the monitor faces.
    box('Monitor gauge recess',(-.18,-.715,.92),(.86,.04,.34),black,.01)
    box('Monitor gauge face',(-.18,-.73,.92),(.78,.02,.26),dial,.006)
    for i in range(5):
        box('Monitor gauge tick',(-.48+i*.15,-.742,.95),(.02,.006,.12),black,0)
    x,y,z=MONITOR_LENS
    cylinder('Monitor status bezel',(x,y,z-.02),.12,.06,edge)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=(x,y,z))
    obj=bpy.context.object;obj.scale=(.08,.08,.045)
    for face in obj.data.polygons:face.use_smooth=True
    finish(obj,'Monitor convex status lens',violet)
    # Two terminal posts on the north side of the lid, red then green, for the wires.
    for colour,(x,y,top) in MONITOR_POSTS.items():
        cylinder(f'Monitor {colour} terminal flange',(x,y,1.29),.13,.08,copper)
        for i,z in enumerate((1.36,1.43,1.50)):
            cylinder(f'Monitor {colour} terminal insulator disc',(x,y,z),.085-.01*i,.05,black,'Z',24)
        cylinder(f'Monitor {colour} terminal stud',(x,y,1.55),.05,.08,brass)
        bolt((x,y,top-.012),radius=.035)
    # Road cue: a brass road-tile plate on the front band.
    box('Monitor road plate',(.55,-.735,.92),(.40,.02,.20),brass,.008)


def arch(name,y0,y1,radius,thickness,mat,z=TUNNEL_ARCH[0],segments=40):
    """A half-pipe shell along Y from y0 to y1, standing on the ground: the part of a ring of
    `radius` (outer) and `thickness` around an axis `z` high that is above the ground."""
    inner=radius-thickness
    start=math.asin(max(-1,min(1,-z/radius)))
    start_inner=math.asin(max(-1,min(1,-z/inner)))
    verts=[];faces=[]
    for i in range(segments+1):
        t=i/segments
        a=start+(math.pi-2*start)*t
        b=start_inner+(math.pi-2*start_inner)*t
        for y in (y0,y1):
            verts.append((radius*math.cos(a),y,z+radius*math.sin(a)))
            verts.append((inner*math.cos(b),y,z+inner*math.sin(b)))
    # Per segment: outer front, inner front, outer back, inner back.
    for i in range(segments):
        o0,i0,O0,I0=4*i,4*i+1,4*i+2,4*i+3
        o1,i1,O1,I1=o0+4,i0+4,O0+4,I0+4
        faces += [(o0,O0,O1,o1),(i0,i1,I1,I0),(o0,o1,i1,i0),(O0,I0,I1,O1)]
    last=4*segments
    faces += [(0,1,3,2),(last,last+2,last+3,last+1)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    mesh.validate()
    shell_mesh=bmesh.new();shell_mesh.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(shell_mesh,faces=shell_mesh.faces)
    shell_mesh.to_mesh(mesh);shell_mesh.free()
    for face in mesh.polygons:face.use_smooth=True
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj)
    return finish(obj,name,mat)


def tunnel_body():
    """The road tunnel portal, at depot scale (3 units to a tile) for the 1x1 build to scale."""
    z,radius,shell=TUNNEL_ARCH
    # Bronze skid under the hood, as under the monitor and the liquid depots' tanks.
    for x in (-1.12,1.12):
        box('Tunnel skid rail',(x,-.10,.06),(.26,2.70,.12),steel,.018)
    for x in (-1.12,1.12):
        for y in (-1.20,1.00):
            taper('Bolted tunnel foot',(x,y,.07),(.34,.34),(.28,.28),.14,steel,.05)
            bolt((x,y,.15),radius=.04)
    # The grey hood, a half-pipe from the back of the tile to its mouth, with bronze ribs over it.
    arch('Tunnel hood shell',-1.30,1.05,radius,shell,housing)
    for y in (-1.05,-.35):
        arch('Tunnel bronze rib',y-.07,y+.07,radius+.05,shell+.07,steel)
    # Its brown band near the mouth, and a heavy bronze collar round the mouth itself.
    arch('Tunnel identification band',.30,.62,radius+.03,shell+.05,rolepaint)
    arch('Tunnel mouth collar',.95,1.25,radius+.09,shell+.20,steel)
    # Back wall closing the hood.
    arch('Tunnel back plate',-1.38,-1.30,radius,radius-.01,housing)
    # The dark way in, going down under the ground: a deep recess in the mouth, and the ramp's floor.
    arch('Tunnel mouth darkness',.20,1.06,radius-shell+.005,radius-shell-.10,black)
    arch('Tunnel deep darkness',.15,.25,radius-shell+.005,radius-shell-.005,black)
    box('Tunnel ramp floor',(0,.62,.012),(1.80,.86,.024),black,0)
    # Orange clasps holding the collar to the skid, and brass bolts along the collar's foot.
    # Orange clasps at both ends, so each view shows some.
    for x in (-1.22,1.22):
        for y in (1.10,-1.28):
            box('Tunnel collar clasp',(x,y,.22),(.16,.34,.30),trim,.012)
            bolt((x+math.copysign(.085,x),y,.28),'X',radius=.03)
    for i in range(9):
        a=math.pi*(i+1)/10
        bolt((math.cos(a)*(radius+.05),1.255,z+math.sin(a)*(radius+.05)),'Y',radius=.03)
    # A violet status lens on the crown of the collar, as the depots have.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=(0,1.10,z+radius+.12))
    obj=bpy.context.object;obj.scale=(.09,.09,.05)
    for face in obj.data.polygons:face.use_smooth=True
    finish(obj,'Tunnel convex status lens',violet)
    cylinder('Tunnel status bezel',(0,1.10,z+radius+.10),.13,.05,edge)
    # Road cue: a brass road-tile plate on the back of the hood.
    box('Tunnel road plate',(0,-1.385,.45),(.50,.02,.24),brass,.008)


def monitor_points(size):
    """Screen offsets, in tiles, of the posts and lens for each direction (north, east, south, west):
    the camera's projection (rotate, then x stays, up is y + z/sqrt(2)) and the ground shadow's
    (x + z/2, up y + (2/3)z/sqrt(2)), as tools/render_directions.py draws them."""
    scale=size/3
    def place(point,direction,shadow=False):
        x,y,z=(v*scale for v in point)
        angle=-math.tau*direction/4
        rx,ry=x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle)
        if shadow:
            return [round(rx+z/2,4),round(-(ry+z*2/3/math.sqrt(2)),4)]
        return [round(rx,4),round(-(ry+z/math.sqrt(2)),4)]
    return {
        'wire':[{colour:place(point,d) for colour,point in MONITOR_POSTS.items()} for d in range(4)],
        'wire_shadow':[{colour:place(point,d,True) for colour,point in MONITOR_POSTS.items()} for d in range(4)],
        'lens':[place(MONITOR_LENS,d) for d in range(4)],
    }


def configure_depot_materials():
    # Local material copies only: the approved freighter master stays untouched.
    settings=[(steel,(.145,.14,.12),.72,.50,.78),(edge,(.30,.285,.25),.76,.36,.62),
              (copper,(.32,.15,.065),.78,.38,.65),(brass,(.42,.29,.12),.75,.38,.62)]
    for mat,color,metal,rough_min,rough_max in settings:
        nodes=mat.node_tree.nodes
        ramp=nodes['Surface pigment'].color_ramp
        ramp.elements[0].color=(*(c*(.30 if mat==steel else .50) for c in color),1)
        ramp.elements[1].color=(*color,1)
        nodes['Principled BSDF'].inputs['Metallic'].default_value=metal
        for node in nodes:
            if node.type=='MAP_RANGE':
                node.inputs['To Min'].default_value=rough_min;node.inputs['To Max'].default_value=rough_max
    for mat in [steel,edge,copper,brass,rolepaint,trim,housing]:
        nodes=mat.node_tree.nodes
        paint='paint_channel' in mat
        nodes['Uneven coating and oxidation'].inputs['Scale'].default_value=18 if paint else 26
        nodes['Fine abrasion'].inputs['Scale'].default_value=115
        ramp=nodes['Surface pigment'].color_ramp
        ramp.elements[0].position=.22;ramp.elements[1].position=.78
        for node in nodes:
            if node.type=='AMBIENT_OCCLUSION':node.inputs['Distance'].default_value=.11
            if node.type=='BUMP':
                node.inputs['Strength'].default_value=.27
                node.inputs['Distance'].default_value=.0035
        if paint:
            nodes['Principled BSDF'].inputs['Metallic'].default_value=.48
            nodes['Scattered flaked paint'].inputs['Scale'].default_value=28
            for node in nodes:
                if node.type=='MATH' and node.operation=='GREATER_THAN':node.inputs[1].default_value=.595
                if node.type=='MAP_RANGE':
                    node.inputs['To Min'].default_value=.48;node.inputs['To Max'].default_value=.74
            substrate=nodes['Exposed oxidized steel (never tinted)'].color_ramp
            substrate.elements[0].color=(.055,.039,.024,1)
            substrate.elements[1].color=(.24,.19,.13,1)
    for mat in [steel,edge,copper,brass]:
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        shader=nodes['Principled BSDF'];old=shader.inputs['Base Color'].links[0].from_socket
        ao=next(node for node in nodes if node.type=='AMBIENT_OCCLUSION')
        invert=nodes.new('ShaderNodeMath');invert.operation='SUBTRACT';invert.inputs[0].default_value=1
        links.new(ao.outputs['AO'],invert.inputs[1])
        scale=nodes.new('ShaderNodeMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=.65
        links.new(invert.outputs[0],scale.inputs[0])
        stain=nodes.new('ShaderNodeMixRGB');stain.name='Oxide accumulated in joints';stain.inputs[2].default_value=(.085,.040,.018,1)
        links.new(scale.outputs[0],stain.inputs[0]);links.new(old,stain.inputs[1]);links.new(stain.outputs[0],shader.inputs['Base Color'])
    # Rounded, coated violet lenses have a restrained glow and physical highlights.
    shader=violet.node_tree.nodes['Principled BSDF']
    shader.inputs['Metallic'].default_value=.10
    shader.inputs['Roughness'].default_value=.18
    shader.inputs['Coat Weight'].default_value=.45
    shader.inputs['Emission Strength'].default_value=.20
    shader.inputs['Emission Color'].default_value=(.16,.012,.32,1)
    ramp=violet.node_tree.nodes['Surface pigment'].color_ramp
    ramp.elements[0].color=(.025,.003,.055,1);ramp.elements[1].color=(.16,.012,.32,1)


def warm_fluid_metal():
    # Pale bronze exposed faces, dark oxide at boundaries and contacts. This
    # changes untinted metal only; paint pigments, coverage and lights stay fixed.
    for mat,color,low in [(steel,(.60,.47,.29),(.36,.255,.14)),
                          (edge,(.24,.14,.055),(.06,.031,.012)),
                          (copper,(.49,.30,.12),(.27,.14,.055)),
                          (brass,(.62,.44,.20),(.36,.23,.09))]:
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        ramp=nodes['Surface pigment'].color_ramp
        ramp.elements[0].color=(*low,1);ramp.elements[1].color=(*color,1)
        nodes['Principled BSDF'].inputs['Metallic'].default_value=.82
        for node in nodes:
            if node.type=='MAP_RANGE':
                node.inputs['To Min'].default_value=.30;node.inputs['To Max'].default_value=.52
            if node.type=='BUMP':node.inputs['Strength'].default_value=.10
        nodes['Oxide accumulated in joints'].inputs[2].default_value=(.075,.030,.012,1)
        # Broad highlight across the barrel, not brown noise over its entire face.
        # Physical lighting and existing AO still shade this editable patina.
        pigment=nodes['Surface pigment'].outputs['Color']
        consumers=[link.to_socket for link in list(pigment.links)]
        geometry=nodes.new('ShaderNodeNewGeometry')
        dot=nodes.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT'
        links.new(geometry.outputs['Normal'],dot.inputs[0]);links.new(geometry.outputs['Incoming'],dot.inputs[1])
        absolute=nodes.new('ShaderNodeMath');absolute.operation='ABSOLUTE';links.new(dot.outputs['Value'],absolute.inputs[0])
        facing=nodes.new('ShaderNodeMapRange');facing.name='Broad exposed metal';facing.interpolation_type='SMOOTHERSTEP'
        facing.inputs['From Min'].default_value=.08;facing.inputs['From Max'].default_value=.75
        links.new(absolute.outputs[0],facing.inputs['Value'])
        patina=nodes.new('ShaderNodeMixRGB');patina.name='Dark boundary to light bronze'
        patina.inputs[1].default_value=(.065,.033,.014,1)
        links.new(facing.outputs[0],patina.inputs[0]);links.new(pigment,patina.inputs[2])
        for target in consumers:links.new(patina.outputs[0],target)
    # Generated coordinates are normalized to each box, including rotated rails.
    # On a face one coordinate is at its bound; the second-largest absolute
    # coordinate measures proximity to the remaining face edges without seams.
    panel=steel.copy();panel.name='BASE | bronze panel patina'
    nodes=panel.node_tree.nodes;links=panel.node_tree.links
    coords=nodes.new('ShaderNodeTexCoord');split=nodes.new('ShaderNodeSeparateXYZ')
    links.new(coords.outputs['Generated'],split.inputs[0])
    def math_node(operation,a,b=None):
        node=nodes.new('ShaderNodeMath');node.operation=operation
        for i,value in enumerate([a,b] if b is not None else [a]):
            if isinstance(value,(int,float)):node.inputs[i].default_value=value
            else:links.new(value,node.inputs[i])
        return node.outputs[0]
    axes=[math_node('MULTIPLY',math_node('ABSOLUTE',math_node('SUBTRACT',v,.5)),2) for v in split.outputs]
    pairs=[math_node('MINIMUM',axes[i],axes[(i+1)%3]) for i in range(3)]
    perimeter=math_node('MAXIMUM',math_node('MAXIMUM',pairs[0],pairs[1]),pairs[2])
    fade=nodes.new('ShaderNodeMapRange');fade.name='Recessed panel perimeter';fade.interpolation_type='SMOOTHERSTEP'
    fade.inputs['From Min'].default_value=.60;fade.inputs['From Max'].default_value=.98
    fade.inputs['To Min'].default_value=1;fade.inputs['To Max'].default_value=.18
    links.new(perimeter,fade.inputs['Value'])
    exposed=math_node('MULTIPLY',fade.outputs[0],nodes['Broad exposed metal'].outputs[0])
    links.new(exposed,nodes['Dark boundary to light bronze'].inputs[0])


def detail_weather(role):
    # Editable mesh decals, not baked default-color paint. All are untinted metal/oxide.
    groups={}
    def polygon(name,points,mat):
        key=mat.name
        if key not in groups:groups[key]=[[],[],mat]
        verts,faces,_=groups[key];offset=len(verts);verts.extend(points);faces.append(tuple(range(offset,offset+len(points))))
    def plane(center,u,v,width,height,count):
        center,u,v=Vector(center),Vector(u),Vector(v)
        for i in range(count):
            a=random.uniform(-.48,.48)*width;b=random.uniform(-.48,.48)*height
            if i%3==0:a=random.choice([-1,1])*random.uniform(.41,.48)*width
            length=random.uniform(.008,.065);thick=random.uniform(.0015,.006)
            if i%5==0:length*=.5;thick*=2.3
            points=[]
            for j in range(7):
                angle=j*math.tau/7;f=random.uniform(.60,1)
                aa=max(-width*.49,min(width*.49,a+math.cos(angle)*length*f))
                bb=max(-height*.49,min(height*.49,b+math.sin(angle)*thick*f))
                points.append(tuple(center+u*aa+v*bb))
            polygon('Coating loss',points,rust if i%4==0 else edge)
    # Foundation scuffs follow the actual low pan or narrow open skid rails.
    if not role.startswith('liquid-'):
        for sign in [-1,1]:
            plane((0,sign*1.438,.07),(1,0,0),(0,0,1),2.30,.07,45)
    else:
        for sign in [-1,1]:
            plane((sign*1.401,0,.16),(0,1,0),(0,0,1),2.20,.12,45)
    if role in ['provider','request','buffer']:
        for x in [-1.19,1.19]:
            for y in [-1.16,1.16]:
                plane((x,y+math.copysign(.224,y),1.22),(1,0,0),(0,0,1),.26,1.28,100)
        for sign in [-1,1]:
            for y in [-.70,.28]:plane((sign*1.229,y,.96),(0,1,0),(0,0,1),.68,.39,55)
        for i in range(200):
            a=random.uniform(0,math.tau);r=random.uniform(.30,.75);x,y=r*math.cos(a),r*math.sin(a)
            if abs(y)<.15:continue
            length=random.uniform(.008,.065);w=random.uniform(.001,.004)
            polygon('Sealed lid handling scar',[(x-length,y,2.486),(x,y-w,2.486),(x+length*.5,y,2.486),(x,y+w,2.486)],edge if i%4 else rust)
        for sign in [-1,1]:pipe('Provider lid quadrant seam',[(0,sign*.31,2.489),(0,sign*.74,2.489)],.006,black)
        for x in [-1.07,1.07]:
            for y in [-.68,.68]:plane((x,y,2.395),(1,0,0),(0,1,0),.14,.41,25)
    else:
        if role=='fuel':
            plane((-.64,-.22,2.451),(1,0,0),(0,1,0),.73,1.27,180)
            plane((-.64,.666,1.98),(1,0,0),(0,0,1),.89,.20,70)
        tanks=[(.56,0,.50,2.03)] if role=='fuel' else ([(0,0,.88,2.05)] if role=='liquid-buffer' else [(0,0,1.15,2.20)])
        for x,y,r,height in tanks:
            dome=.25 if role=='fuel' else .42
            shoulder=height-dome*r
            def shell(a,z,offset=.015):
                radius=r if z<=shoulder else r*math.sqrt(max(0,1-((z-shoulder)/(dome*r))**2))
                return (x+(radius+offset)*math.cos(a)+(math.copysign(.60,math.cos(a)) if role=='liquid-buffer' and abs(math.cos(a))>1e-7 else 0),y+(radius+offset)*math.sin(a)*(1.3 if role=='liquid-buffer' else 1)+(math.copysign(.67,math.sin(a)) if role=='fuel' and abs(math.sin(a))>1e-7 else 0),z)
            for i in range(360):
                a=random.uniform(0,math.tau);z=random.uniform(.67,height-.10)
                da=random.uniform(.007,.035)/r;dz=random.uniform(.0015,.007)
                if i%6==0:da*=.22;dz*=24
                points=[]
                for j in range(7):
                    t=j*math.tau/7;f=random.uniform(.5,1)
                    points.append(shell(a+math.cos(t)*da*f,min(height-.04,z+math.sin(t)*dz*f)))
                polygon('Pressure shell scuff or oxide run',points,rust if i%3==0 else edge)
            for a in [0,math.pi/2,math.pi,3*math.pi/2]:
                points=[shell(a,shoulder+dome*r*math.sin(t),.007) for t in [i*math.pi/2/18 for i in range(2,15)]]
                pipe('Dome welded panel seam',points,.0045,edge)
            for i in range(20):
                a=i*math.tau/20
                pipe('Flange oxide drip',[shell(a,.65),shell(a+.007,.60),shell(a+.012,.54)],.004,rust)
    for name,(verts,faces,mat) in groups.items():
        mesh=bpy.data.meshes.new('Localized wear mesh');mesh.from_pydata(verts,[],faces);mesh.update()
        obj=bpy.data.objects.new('WEAR | '+name,mesh);scene.collection.objects.link(obj);finish(obj,obj.name,mat)


def surface_wear(role):
    # Low pan edge chips; liquid skids receive rail-local wear above.
    if role.startswith('liquid-'):return
    for i in range(64):
        x=random.uniform(-1.32,1.32)
        y=random.choice([-1.401,1.401])
        z=random.uniform(.025,.10)
        length=random.uniform(.025,.12)
        mesh=bpy.data.meshes.new('Irregular edge wear')
        verts=[]
        for j in range(7):
            a=math.tau*j/7;w=random.uniform(.6,1)
            verts.append((x+math.cos(a)*length*w,y,z+math.sin(a)*.014*w))
        mesh.from_pydata(verts,[],[tuple(range(7))])
        obj=bpy.data.objects.new('Foundation edge chip',mesh)
        scene.collection.objects.link(obj)
        finish(obj,obj.name,edge if i%3 else rust)


def factory_ports(role,size):
    # Every factory route has the native 0.61-tile diameter all the way into its tank.
    if role not in ['fuel','liquid-provider','liquid-request','liquid-buffer']:return []
    side_ports=role in ['fuel','liquid-buffer']
    signs=[-1,1] if role=='liquid-buffer' else ([-1] if role=='fuel' else [0])
    # Ground-level Buffer fittings clear a thin skid; tall front posts would
    # obstruct the outlets. Rear posts retain the open support-frame silhouette.
    if role=='liquid-buffer':
        for obj in list(root.children):
            if obj.type!='MESH':continue
            if obj.name.startswith(('Machinery frame upright','Orange frame knee brace')):
                verts=[obj.matrix_basis@Vector(v) for v in obj.bound_box]
                if sum(v.y for v in verts)/8>1.1:bpy.data.objects.remove(obj,do_unlink=True)
            elif obj.name.startswith(('Brass hex fastener','Fastener recessed hex socket','Protected status bezel','Status lens dark gasket','Convex coated violet status lens')):
                if obj.location.y>1.15 and abs(obj.location.x)>1.1 and obj.location.z>.1:bpy.data.objects.remove(obj,do_unlink=True)
    for obj in list(root.children):
        if obj.type!='MESH':continue
        if role=='liquid-buffer' and obj.name.startswith('Open skid longitudinal rail'):continue
        if side_ports and obj.name.startswith(('Open side scaffold rail','Rear service bay rail','Side structural sill','Open skid longitudinal rail')):
            verts=[obj.matrix_basis@Vector(v) for v in obj.bound_box];cx=sum(v.x for v in verts)/8
            if any(cx*sign>1 for sign in signs):
                dims=obj.dimensions.copy();z=obj.location.z;name=obj.name
                bpy.data.objects.remove(obj,do_unlink=True)
                front=-1.10 if role=='fuel' else -.80
                box(name+' behind service bay',(cx,(-1.38+front)/2,z),(dims.x,front+1.38,dims.z),steel,.012)
                if role=='fuel':box(name+' ahead of service bay',(cx,1.24,z),(dims.x,.28,dims.z),steel,.012)
        elif not side_ports and obj.name.startswith('Open skid transverse rail') and obj.location.y>1:
            z=obj.location.z;name=obj.name;bpy.data.objects.remove(obj,do_unlink=True)
            for x in [-.86,.86]:box(name+' outside front pipe',(x,1.30,z),(.80,.15,.18),steel,.012)
    if role=='fuel':
        pan=bpy.data.objects['Low steel foundation pan']
        cutter=box('Temporary full bore pan clearance',(-.94,0,.10),(1.25,1.20,.30),steel,0)
        mod=pan.modifiers.new('Full bore service notch','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
        bpy.context.view_layer.objects.active=pan;bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter,do_unlink=True)
        # Decals on the removed pan must be cut away with their supporting metal.
        for obj in list(root.children):
            if obj.type!='MESH' or not obj.name.startswith(('Foundation edge chip','WEAR |')):continue
            bm=bmesh.new();bm.from_mesh(obj.data)
            faces=[f for f in bm.faces if any(-1.565<p.x<-.315 and -.60<p.y<.60 and p.z<.25
                   for p in (obj.matrix_basis@v.co for v in f.verts))]
            bmesh.ops.delete(bm,geom=faces,context='FACES')
            bm.to_mesh(obj.data);bm.free()
            if not obj.data.polygons:bpy.data.objects.remove(obj,do_unlink=True)
    for obj in list(root.children):
        if obj.type!='MESH':continue
        if role=='liquid-buffer' and obj.location.y>1 and obj.name.startswith('Front open frame rail'):
            bpy.data.objects.remove(obj,do_unlink=True);continue
        if side_ports and obj.name.startswith('Open skid transverse rail') and obj.location.y>1:obj.location.y=1.40
        if not side_ports and obj.name.startswith('Rear scaffold rail'):
            bpy.data.objects.remove(obj,do_unlink=True)
            for x in [-.85,.85]:box('Rear rail outside tank',(x,-1.34,.65),(.69,.085,.09),steel,.012)
    ports=[]
    for sign in signs:
        if role=='fuel':
            points=[(-.72,0,.36),(-1.42,0,.36)]
            anchor=[-1,0];direction=12;seam=[-1.5,0]
        elif role=='liquid-buffer':
            points=[(float(sign),0,.36),(float(sign),1.42,.36)]
            anchor=[sign,-1];direction=0;seam=[sign,-1.5]
        else:
            points=[(0,.60,.36),(0,1.42,.36)]
            anchor=[0,-1];direction=0;seam=[0,-1.5]
        rigid_pipe('Factory full bore tank route '+str(sign),points,.305,native=True)
        marker=bpy.data.objects.new('SOCKET | '+str(direction),None)
        scene.collection.objects.link(marker);marker.parent=root
        marker.location=(seam[0],-seam[1],.36);marker.empty_display_type='ARROWS';marker.empty_display_size=.20
        marker['tile_anchor']=anchor;marker['direction']=direction
        ports.append({'direction':direction,'position':anchor,'seam':seam,'height':.36})
    return ports


def seated_pose_mesh(name,poses,faces,material,smooth=True):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(poses[0],[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);finish(obj,name,material)
    for face in mesh.polygons:face.use_smooth=smooth and len(face.vertices)==4
    obj.shape_key_add(name='Unprojected seated neck')
    for d in range(4):
        key=obj.shape_key_add(name=['North','East','South','West'][d]+' seated neck')
        for vertex,point in zip(key.data,poses[d+1]):vertex.co=point
        driver=key.driver_add('value').driver;driver.type='SCRIPTED'
        driver.expression=f'max(0,cos(h+{d}*pi/2))*(1-1/p)/(1-1/sqrt(2))'
        for var_name,target,path in [('h',root,'rotation_euler[2]'),('p',root.parent,'scale[1]')]:
            var=driver.variables.new();var.name=var_name;var.type='SINGLE_PROP';var.targets[0].id=target;var.targets[0].data_path=path
    return obj


def tank_weld_necks():
    """Seat tank adapters or weld necks at each registered cardinal view.

    The unprojected basis remains editable for ordinary concept inspection.
    The four poses follow the existing native-picture registration drivers.
    """
    routes=[o for o in root.children if o.name.startswith('Factory full bore tank route')]
    if not routes:return
    tank=next(o for o in root.children if o.name.startswith('Broad domed pressure vessel'))
    for route in routes:
        count=route['pipe_ring_size'];poses=[];exposed=[]
        adapter=root['role']=='liquid-buffer'
        root_radius=.335 if adapter else .36
        flange_poses=[];gasket_poses=[];bolt_poses=[]
        for heading,scale in [(0,1)]+[(d,math.sqrt(2)) for d in range(4)]:
            root.rotation_euler.z=-heading*math.pi/2;root.parent.scale.y=scale
            bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
            ev=route.evaluated_get(dg);mesh=ev.to_mesh()
            start=sum((route.matrix_world@v.co for v in mesh.vertices[:count]),Vector())/count
            end=sum((route.matrix_world@v.co for v in mesh.vertices[-count:]),Vector())/count
            axis=(end-start).normalized()
            radial=[(route.matrix_world@v.co-start).normalized() for v in mesh.vertices[:count]]
            ev.to_mesh_clear()
            ev=tank.evaluated_get(dg);mesh=ev.to_mesh()
            tree=BVHTree.FromPolygons([tank.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons],epsilon=1e-5);ev.to_mesh_clear()
            def surface(direction,radius,inset=0):
                origin=end+axis*3+direction*radius;origin.z=max(.045,origin.z)
                # An exact shell tessellation edge can miss the near face and
                # hit the far wall. Neighboring rays resolve that numerical tie.
                transverse=axis.cross(Vector((0,0,1))).normalized()
                hits=[tree.ray_cast(origin+transverse*offset,-axis,6) for offset in [0,-.0001,.0001]]
                hits=[hit for hit in hits if hit[0] is not None]
                assert hits,(route.name,heading,'weld misses shell')
                point,normal,index,distance=min(hits,key=lambda hit:hit[3])
                point=origin-axis*distance
                return point-axis*inset/max(.1,abs(normal.dot(axis)))
            contacts=[surface(v,root_radius) for v in radial]
            furthest=max(p.dot(axis) for p in contacts)
            source_start,source_end=[Vector(p) for p in json.loads(route['pipe_centerline'])]
            source_axis=source_end-source_start
            axial_scale=(route.matrix_world.to_3x3()@source_axis).length/source_axis.length
            # Stop before the separate connector sleeve, never flare into it.
            limit=end.dot(axis)-.08*axial_scale-.015
            length=min(.13,limit-furthest);exposed.append(length>=.04)
            if adapter:
                # A flat retaining face needs a shell-seated boss behind it.
                # Leave space for the plate and bolt heads before the native sleeve.
                plate_plane = min(max(surface(v, .35).dot(axis) for v in radial) + .012, limit - .06)
            points=[]
            for ring,radius in enumerate([root_radius,root_radius,.305] if adapter else [root_radius,root_radius,.305+(root_radius-.305)*.55,.305]):
                for direction in radial:
                    point=surface(direction,radius)
                    if length<.04:
                        # Rearward fittings within the vessel need no visible flare.
                        point=surface(direction,radius,.012+.004*ring)
                    elif ring==0:point=surface(direction,radius,.012)
                    elif adapter:
                        target = plate_plane - .008 if ring == 1 else plate_plane + .028
                        point += axis * (target - point.dot(axis))
                    elif ring==1:point+=axis*.012
                    else:
                        target=furthest+length*(.55 if ring==2 else 1)
                        point+=axis*(target-point.dot(axis))
                    points.append(tuple(root.matrix_world.inverted()@point))
            poses.append(points)
            if adapter:
                inverse=root.matrix_world.inverted()
                def annulus(front, back):
                    result = []
                    for offset, radius in [(back, .305), (back, .35), (front, .35), (front, .305)]:
                        for direction in radial:
                            point = surface(direction, radius)
                            if length >= .04:
                                point += axis * (plate_plane + offset - point.dot(axis))
                            else:
                                point += axis * offset
                            result.append(tuple(inverse @ point))
                    return result
                flange_poses.append(annulus(.028, 0))
                gasket_poses.append(annulus(0, -.008))
                heads=[]
                for i in range(6):
                    angle=i*math.tau/6
                    v=radial[0]*math.cos(angle)+radial[count//4]*math.sin(angle)
                    radius=(.35+.305)/2
                    contact = surface(v, radius)
                    normal = axis
                    if length >= .04:
                        contact += axis * (plate_plane - contact.dot(axis))
                    u=normal.cross(Vector((0,0,1))).normalized();w=normal.cross(u).normalized()
                    center=contact+axis*.028
                    for z in [0,.018]:
                        for k in range(6):
                            a=k*math.tau/6
                            heads.append(tuple(inverse@(center+normal*z+(u*math.cos(a)+w*math.sin(a))*.014)))
                bolt_poses.append(heads)
        root.rotation_euler.z=0;root.parent.scale.y=math.sqrt(2);bpy.context.view_layer.update()
        rings=len(poses[0])//count
        faces=[(k*count+i,k*count+(i+1)%count,(k+1)*count+(i+1)%count,(k+1)*count+i) for k in range(rings-1) for i in range(count)]
        faces += [tuple(reversed(range(count))),tuple(range((rings-1)*count,rings*count))]
        name=('Bolted tank adapter | ' if adapter else 'Welded tank neck | ')+route.name
        obj=seated_pose_mesh(name,poses,faces,housing if adapter else steel)
        obj['source_route']=route.name;obj['pipe_ring_size']=count;obj['exposed_in_cardinal_views']=exposed[1:]
        if not adapter:
            obj.data.materials.append(copper)
            for face in obj.data.polygons:
                if face.index<count:face.material_index=1
        else:
            ring_faces=[(j*count+i,j*count+(i+1)%count,((j+1)%4)*count+(i+1)%count,((j+1)%4)*count+i) for j in range(4) for i in range(count)]
            for label,data,material in [('machined flange',flange_poses,brass),('gasket',gasket_poses,black)]:
                part=seated_pose_mesh('Buffer adapter '+label+' | '+route.name,data,ring_faces,material,False)
                part['source_route']=route.name
            head_faces=[]
            for i in range(6):
                n=i*12
                head_faces.extend([tuple(n+k for k in reversed(range(6))),tuple(n+6+k for k in range(6))])
                head_faces.extend((n+k,n+(k+1)%6,n+6+(k+1)%6,n+6+k) for k in range(6))
            part=seated_pose_mesh('Buffer adapter hex bolts | '+route.name,bolt_poses,head_faces,brass,False)
            part['source_route']=route.name


def midsection_tank_straps(role):
    """Two additional retainers on the straight middle of each obround shell."""
    if role not in ['fuel','liquid-buffer']:return
    fuel=role=='fuel';r=.50 if fuel else .88;top=2.03 if fuel else 2.05
    dome=.25 if fuel else .42;shoulder=top-dome*r
    center=Vector((-.56,0,0)) if fuel else Vector((0,0,0))
    for sign in [-1,1]:
        before=set(root.children)
        radial=Vector((sign,0,0)) if fuel else Vector((0,sign*1.3,0))
        tangent=Vector((0,sign,0)) if fuel else Vector((-sign,0,0))
        width=.14 if fuel else .20
        profile=[(r+.04,.78),(r+.04,shoulder)]
        for k in range(1,12):
            t=math.pi/2*k/16
            profile.append((r*math.cos(t)+.04,shoulder+dome*r*math.sin(t)+.015))
        points=[tuple(center+radial*radius+tangent*side*width/2+Vector((0,0,z)))
                for radius,z in profile for side in [-1,1]]
        mesh=bpy.data.meshes.new('Formed midsection strap')
        mesh.from_pydata(points,[],[(2*k,2*k+1,2*k+3,2*k+2) for k in range(len(profile)-1)]);mesh.update()
        obj=bpy.data.objects.new('Continuous retaining strap',mesh);scene.collection.objects.link(obj);finish(obj,obj.name,steel)
        solid=obj.modifiers.new('Strap plate thickness','SOLIDIFY');solid.thickness=.045;solid.offset=1
        bevel=obj.modifiers.new('Strap worn edge','BEVEL');bevel.width=.008;bevel.segments=2
        obj.data.materials.append(edge);bevel.material=1
        for radius,z in [profile[0],profile[-1]]:bolt(tuple(center+radial*radius+Vector((0,0,z+.05))),radius=.04)
        box('Orange strap buckle',tuple(center+radial*(r+.045)+Vector((0,0,shoulder-.05))),(.14,.14,.19),trim)
        for z in [.82,shoulder-.19]:
            rod('Strap transverse rivet',tuple(center+radial*(r+.055)+Vector((0,0,z))),tuple(center+radial*(r+.085)+Vector((0,0,z))),.033,brass)
        for part in set(root.children)-before:part.name='Midsection binding | '+str(sign)+' | '+part.name


def compress_cargo_height(parts):
    # Shorten the case above its foundation without changing the tile footprint.
    # Transform local geometry, not local scale: tilted rods must remain attached.
    warp=Matrix.Translation((0,0,.4))@Matrix.Diagonal((1,1,.80,1))@Matrix.Translation((0,0,-.4))
    for obj in parts:
        local=obj.matrix_basis.inverted()@warp@obj.matrix_basis
        if obj.type=='MESH':obj.data.transform(local)
        elif obj.type=='CURVE':
            for spline in obj.data.splines:
                for point in spline.bezier_points:
                    co,left,right=point.co.copy(),point.handle_left.copy(),point.handle_right.copy()
                    point.co=local@co;point.handle_left=local@left;point.handle_right=local@right


def build(role,size):
    global scene,root,steel,edge,black,copper,brass,trim,housing,rolepaint,rubber,violet,rust,dial
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(1977)
    scene=bpy.context.scene
    scene.name='Scene'
    with bpy.data.libraries.load(str(REPO/'assets/quinityn-freighter/source/quinityn-freighter.blend'),link=False) as (available,loaded):
        loaded.materials=[name for name in available.materials if name.startswith(('BASE |','PAINT |'))]
    steel=bpy.data.materials['BASE | dark cast steel']
    edge=bpy.data.materials['BASE | worn steel edges']
    black=bpy.data.materials['BASE | deep recess']
    copper=bpy.data.materials['BASE | aged copper']
    brass=bpy.data.materials['BASE | brass']
    rubber=bpy.data.materials['BASE | tire rubber']
    violet=bpy.data.materials['BASE | violet power lenses']
    rust=bpy.data.materials['BASE | old oxide and seam deposits']
    rolepaint=bpy.data.materials['PAINT | cab'];trim=bpy.data.materials['PAINT | trim'];housing=bpy.data.materials['PAINT | cargo']
    key=role.removeprefix('liquid-')
    palette=MONITOR_PALETTE if role==MONITOR else TUNNEL_PALETTE if role==TUNNEL else {'cab':ROLE_COLORS[key], 'trim':[.80,.38,.12], 'cargo':[.43,.43,.40]}
    for mat,channel in [(rolepaint,'cab'),(trim,'trim'),(housing,'cargo')]:
        color=[((v+.055)/1.055)**2.4 if v>.04045 else v/12.92 for v in palette[channel]]
        ramp=mat.node_tree.nodes['Surface pigment'].color_ramp
        ramp.elements[0].color=(*(v*.3 for v in color),1)
        ramp.elements[1].color=(*color,1)
        mat.diffuse_color=(*color,1)
    configure_depot_materials()
    if role in ['fuel','liquid-provider','liquid-request','liquid-buffer',MONITOR,TUNNEL]:warm_fluid_metal()
    dial=edge.copy();dial.name='BASE | enamel gauge face'
    dial.node_tree.nodes['Surface pigment'].color_ramp.elements[1].color=(.65,.58,.43,1)
    root=bpy.data.objects.new('Depot | rotate this assembly',None)
    scene.collection.objects.link(root)
    root['forward_axis']='+Y (Factorio north)'
    root['role']=role;root['tile_size']=size
    if role==MONITOR:
        monitor_body()
    elif role==TUNNEL:
        tunnel_body()
    else:
        foundation(role)
    if role in (MONITOR,TUNNEL):
        pass
    elif role in ['provider','request','buffer']:
        before=set(root.children)
        cargo_body(role)
        cargo_mechanics(role)
        reference_cargo_hardware(role)
        roof_wear(role)
        detail_weather(role)
        compress_cargo_height(set(root.children)-before)
        cargo_loading(role)
    else:
        before=set(root.children)
        fluids(role)
        fluid_mechanics(role)
        reference_fluid_hardware(role)
        detail_weather(role)
        # The reference front view places the fuel hopper at image left and
        # the automated transfer assembly at image right. +Y faces the opposite world axis.
        mirror=Matrix.Diagonal((-1,1,1,1))
        for obj in set(root.children)-before:obj.matrix_basis=mirror@obj.matrix_basis
    if role not in (MONITOR,TUNNEL):surface_wear(role)
    if size==1:
        for obj in root.children:
            obj.location *= 1/3
            obj.scale *= 1/3
        for material in bpy.data.materials:
            if not material.use_nodes:continue
            for node in material.node_tree.nodes:
                if node.type=='AMBIENT_OCCLUSION':node.inputs['Distance'].default_value *= 1/3
                if node.type=='BUMP':node.inputs['Distance'].default_value *= 1/3
    ports=factory_ports(role,size)
    projection=bpy.data.objects.new('PROJECTION | tile grid compensation',None)
    scene.collection.objects.link(projection)
    projection.scale.y=math.sqrt(2)
    root.parent=projection
    for obj in root.children:
        if obj.type!='MESH' or not obj.data.shape_keys:continue
        for name,expression in [('Native circle north south','cos(h)**2'),('Native circle east west','sin(h)**2'),('Native seam X','-(.36/sqrt(2)-.025)*sin(h)'),('Native seam Y','-(.36/sqrt(2)-.025)*cos(h)')]:
            key=obj.data.shape_keys.key_blocks.get(name)
            if not key:continue
            driver=key.driver_add('value').driver;driver.type='SCRIPTED'
            driver.expression=expression+'*(1-1/p)/(1-1/sqrt(2))'
            for var_name,target,path in [('h',root,'rotation_euler[2]'),('p',projection,'scale[1]')]:
                variable=driver.variables.new();variable.name=var_name;variable.type='SINGLE_PROP'
                variable.targets[0].id=target;variable.targets[0].data_path=path
    projection['purpose']='Maps one logical ground tile to equal screen X/Y lengths at 45 degrees elevation'
    tank_weld_necks()
    midsection_tank_straps(role)
    bpy.ops.object.camera_add(location=(0,-16,16))
    camera=bpy.context.object
    camera.name='CAMERA | fixed 45 degree tile projection'
    camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'
    camera.data.ortho_scale=7.5 if size==3 else 2.5
    scene.camera=camera
    bpy.ops.object.light_add(type='SUN',location=(-6,-8,12))
    sun=bpy.context.object
    sun.name='LIGHT | fixed upper-left sunlight'
    sun.rotation_euler=(Vector((0,0,0))-sun.location).to_track_quat('-Z','Y').to_euler()
    sun.data.energy=2.2;sun.data.angle=math.radians(4)
    bpy.ops.object.light_add(type='AREA',location=(-5,-7,11))
    fill=bpy.context.object
    fill.name='LIGHT | broad metal highlights'
    fill.rotation_euler=(Vector((0,0,1))-fill.location).to_track_quat('-Z','Y').to_euler()
    fill.data.energy=1200;fill.data.shape='DISK';fill.data.size=7
    scene.world=bpy.data.worlds.new('Depot world')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.72,.78,.85,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.30
    scene.render.engine='CYCLES'
    scene.cycles.samples=64;scene.cycles.use_denoising=False
    scene.cycles.max_bounces=4;scene.cycles.diffuse_bounces=2;scene.cycles.glossy_bounces=2
    scene.render.film_transparent=True
    scene.render.resolution_x=scene.render.resolution_y=2048
    scene.render.resolution_percentage=100
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
    scene.view_layers[0].name='Vehicle'
    for name in ['cab','trim','cargo']:
        aov=scene.view_layers[0].aovs.add();aov.name='mask_'+name;aov.type='VALUE'
    scene['layer_mapping']='cab=role, trim=clamps, cargo=housing'
    scene['direction_count']=4
    scene['fidelity_pass']=18
    scene['concept']='liquid-provider palette (no concept art)' if role in (MONITOR,TUNNEL) else f'concepts/depots/images/{role}.png'
    shadow=bpy.data.scenes.new('Ground shadow')
    shadow.render.engine='CYCLES';shadow.cycles.samples=1;shadow.cycles.use_denoising=False
    shadow.render.film_transparent=True;shadow.camera=camera;shadow.collection.objects.link(camera)
    shadow.world=bpy.data.worlds.new('Shadow world');shadow.world.color=(0,0,0)
    shadow.view_settings.view_transform='Standard'
    out=ROOT/role/str(size)
    for folder in ['masters/exr','masters/shadow-silhouettes','masters/layers','frames','sheets','previews']:
        (out/folder).mkdir(parents=True,exist_ok=True)
    metadata={'role':role,'size':size,'fidelity_pass':18,'directions':['north','east','south','west'],'palette':palette,'ortho_scale':camera.data.ortho_scale,'projection_y_scale':math.sqrt(2),'ports':ports,'game_frame_size':512,'game_scale':32*camera.data.ortho_scale/512,'source':f'source/{role}-{size}.blend'}
    if role==MONITOR:metadata['points']=monitor_points(size)
    (out/'asset.json').write_text(json.dumps(metadata,indent=2)+'\n')
    root.rotation_euler.z=0
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/f'{role}-{size}.blend'))
    print('BUILT',role,size,flush=True)

for role in ROLES if args.role=='all' else [args.role]: build(role,args.size)
