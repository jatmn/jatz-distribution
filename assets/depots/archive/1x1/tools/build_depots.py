"""Build editable depot masters. Blender 4.3+, no external texture files."""
import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--role', default='all')
parser.add_argument('--size', type=int, choices=[1,3], default=3)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
ROLES = ['provider','request','buffer','fuel','liquid-provider','liquid-request','liquid-buffer']
ROLE_COLORS = {'provider':[.64,.23,.18], 'request':[.23,.42,.69], 'buffer':[.42,.52,.24], 'fuel':[.83,.58,.15]}


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
    return finish(obj,name,mat,bevel)


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


def rigid_pipe(name,points,radius=.20,bend=.26):
    # Explicit tangent sections prevent automatic Bezier handles bowing away from unions.
    points=[Vector(p) for p in points];path=[points[0]]
    for i in range(1,len(points)-1):
        incoming=points[i]-points[i-1];outgoing=points[i+1]-points[i]
        distance=min(bend,incoming.length*(.9 if i==1 else .45),outgoing.length*(.9 if i==len(points)-2 else .45))
        before=points[i]-incoming.normalized()*distance
        after=points[i]+outgoing.normalized()*distance
        path.append(before)
        u=incoming.normalized();v=outgoing.normalized()
        assert abs(u.dot(v))<1e-6, 'Bulk elbow requires orthogonal tangent sections'
        assert distance>radius, 'Elbow centerline radius must exceed tube radius'
        center=before+v*distance
        for step in range(1,17):
            angle=math.pi/2*step/16
            path.append(center-v*distance*math.cos(angle)+u*distance*math.sin(angle))
    path.append(points[-1])
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D'
    curve.bevel_depth=radius;curve.bevel_resolution=4;curve.use_fill_caps=True
    spline=curve.splines.new('POLY');spline.points.add(len(path)-1)
    for point,co in zip(spline.points,path):point.co=(*co,1)
    obj=bpy.data.objects.new(name,curve);scene.collection.objects.link(obj)
    return finish(obj,name,steel)


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
            box('Open skid longitudinal rail',(x,0,.16),(.15,2.76,.18),steel,.018)
        for y in [-1.30,1.30]:
            box('Open skid transverse rail',(0,y,.16),(2.52,.15,.18),steel,.018)
        for x in [-.72,.72]:
            box('Tank load bearing crossmember',(x,0,.30),(.16,2.70,.20),steel,.016)
        for x in [-1.25,1.25]:
            for y in [-1.25,1.25]:
                taper('Bolted skid foot',(x,y,.14),(.34,.34),(.27,.27),.26,steel,.06)
                bolt((x,y,.29),radius=.045)
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
    for index,(x,width) in enumerate(mouths):
        box('Continuous conveyor carcass',(x,.24,.105),(width,2.46,.10),rubber,.035)
        box('Continuous conveyor carrying belt',(x,.24,.158),(width-.045,2.46,.034),rubber,.012)
        for i in range(20):
            y=-.90+i*.12
            box('Conveyor flat tread',(x,y,.178),(width-.075,.092,.012),steel,.004)
            # Direction marks belong to the belt, with Buffer's two lanes opposed.
            if i%4==1:
                sign=-1 if role=='request' or (role=='buffer' and index==1) else 1
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
    if role=='provider':
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
    else:
        for x in [-.54,.54]:
            taper('Split hatch dark gasket',(x,0,2.37),(.99,2.12),(.99,2.12),.035,black,.13)
            taper('Chamfered colored access panel',(x,0,2.43),(.94,2.06),(.86,1.98),.12,rolepaint,.12)
            for y in [-.84,.84]:
                for dx in [-.30,.30]:bolt((x+dx,y,2.505))
            if role=='buffer':
                cylinder('Buffer hatch seat',(x,0,2.51),.43,.08,steel)
                cylinder('Buffer circular lid',(x,0,2.563),.35,.035,rolepaint)
                ring_arc('Buffer locking annulus',x,0,2.59,.35,.415,0,math.tau,edge,.04)
                rod('Lid handle',(x,-.23,2.65),(x,.23,2.65),.018,edge)
                for y in [-.23,.23]: box('Handle stand',(x,y,2.62),(.08,.10,.08),copper)
                for i in range(6):
                    a=i*math.tau/6
                    box('Buffer lock dog',(x+.395*math.cos(a),.395*math.sin(a),2.63),(.10,.10,.055),copper,.008)
                    bolt((x+.395*math.cos(a),.395*math.sin(a),2.67),radius=.022)
            else:
                cylinder('Recessed access lock',(x,0,2.52),.16,.05,edge)
                bolt_ring(x,0,2.556,.125,8)
                cylinder('Access lock center',(x,0,2.56),.075,.05,steel)
        box('Central roof spine',(0,0,2.51),(.16,2.22,.19),steel,.025)
        for y in [-.99,.99]: hinge(0,y,2.58,width=.30)
        if role=='buffer':
            box('Central armored control spine',(0,0,2.62),(.26,1.40,.17),steel,.035)
            cylinder('Roof violet bezel',(0,0,2.74),.105,.045,brass)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=(0,0,2.78))
            obj=bpy.context.object;obj.scale=(.069,.069,.025)
            for face in obj.data.polygons:face.use_smooth=True
            finish(obj,'Convex roof violet indicator',violet)
    if role=='request': lens(-1.19,1.435,1.91)
    for x in [-.80,.80]:
        box('Rear armored service hatch',(x,-1.222,1.23),(.58,.05,1.10),steel,.025)
        for z in [.87,1.0,1.13,1.26]: box('Rear louver',(x,-1.26,z),(.41,.035,.045),edge,.006)
    # Side accumulator tank makes the silhouette mechanically specific.
    for sign in [-1,1]:
        cylinder('Side hydraulic accumulator',(sign*1.28,-.57,.94),.12,.63,steel)
        for z in [.65,.80,1.18,1.27]:cylinder('Accumulator collar',(sign*1.28,-.57,z),.135,.045,copper)
        pipe('Accumulator return tube',[(sign*1.28,-.73,.66),(sign*1.32,-.81,1.18),(sign*1.18,-.86,1.87)],.025,copper)


def vessel(x,y,r,height,dome=.42):
    bottom=.41; shoulder=height-dome*r
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
    cylinder('Heavy lower shell flange',(x,y,.50),r+.065,.16,steel,vertices=64)
    bolt_ring(x,y,.60,r+.025,20 if r>.8 else 14)
    top=height
    cylinder('Manway machined collar',(x,y,top+.015),r*.40,.10,copper)
    cylinder('Bolted manway lid',(x,y,top+.09),r*.36,.09,steel)
    bolt_ring(x,y,top+.15,r*.30,12)
    for i in range(4):
        a=math.pi/4+i*math.pi/2;dx,dy=math.cos(a),math.sin(a)
        # Ribbon follows the actual elliptical dome rather than cutting through it.
        profile=[(r+.04,.49),(r+.04,shoulder)]
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
        vessel(.64,-.33,.64,2.03,dome=.25)
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
        # Motor, tank outlet and closed docking plenum share explicit centers.
        pump(.202,.75,z=.88,scale=.80)
        rod('Fuel straight tank outlet',(.634,.16,.80),(.634,.75,.80),.20,steel)
        flange('Fuel vessel outlet mounting collar',(.634,.40,.80),.29,'Y')
        cylinder('Fuel actuator mounting neck',(.634,.50,1.02),.09,.10,steel)
        actuator(.634,.50,1.15,.38)
        rod('Fuel pump to dock transfer neck',(.634,.89,.80),(.634,1.17,.80),.18,steel)
        flange('Fuel transfer neck union',(.634,1.045,.80),.25,'Y')
        box('Fuel closed docking plenum',(.634,1.24,.80),(.50,.28,.42),steel,.035)
        box('Fuel docking plenum access lid',(.634,1.24,1.04),(.50,.28,.05),housing,.012)
        panel_fasteners(.634,1.24,1.075,.34,.16,'Z')
    elif role=='liquid-buffer':
        for x in [-.64,.64]:vessel(x,-.25,.64,1.97)
        rod('Buffer straight collector',(-.72,.85,.90),(.72,.85,.90),.20,steel)
        for x in [-.64,.64]:
            rod('Buffer tank outlet nozzle',(x,.20,.90),(x,.85,.90),.20,steel)
            flange('Buffer vessel outlet mounting collar',(x,.49,.90),.28,'Y')
        for x in [-.575,.575]:
            box('Buffer cast branch junction',(x,.85,.90),(.55,.48,.48),steel,.07)
        box('Central fluid regulator cabinet',(0,.89,.91),(.38,.34,.76),steel,.035)
        actuator(0,.89,1.36,.38)
        for x in [-.51,.51]:
            box('Armored coupling pedestal',(x,1.10,.63),(.31,.38,.40),steel,.025)
            cylinder('Automatic dock locking collar',(x,1.13,.90),.30,.19,trim,'Y')
            cylinder('Twin fixed docking sleeve',(x,1.28,.90),.245,.24,edge,'Y')
            cylinder('Coupling dark bore',(x,1.406,.90),.19,.012,black,'Y')
            rod('Buffer fixed docking branch',(x,.85,.90),(x,1.28,.90),.20,steel)
        box('Front identity panel',(0,1.36,.60),(.47,.06,.48),steel)
        chevron(0,1.425,.67,.32,edge,relief=.04)
        lens(-1.24,1.335,.73)
    else:
        top=vessel(0,-.25,1.16,2.20)
        if role=='liquid-request':
            # One visible receiver train, with collars on separated straight seats.
            rigid_pipe('Large receiving elbow',[(-.60,.57,1.75),(-.60,1.20,1.75),(-.60,1.20,1.24)],.18,.24)
            cylinder('Front centrifugal pump casing',(-.60,1.15,.73),.30,.40,steel,'Y')
            cylinder('Receiving pump straight inlet neck',(-.60,1.20,1.15),.18,.26,steel)
            cylinder('Front pump mesh recess',(-.60,1.354,.73),.235,.018,black,'Y')
            torus('Front pump worn lip',(-.60,1.37,.73),.25,.020,edge,'Y')
            for v in [i*.027 for i in range(-7,8)]:
                length=2*math.sqrt(.218**2-v*v)
                box('Pump grille horizontal',(-.60,1.38,.73+v),(length,.012,.006),edge,.002)
                box('Pump grille vertical',(-.60+v,1.38,.73),(.006,.012,length),edge,.002)
        else:
            pump(.03,1.18,z=.88)
            rigid_pipe('Seated delivery manifold',[(-.70,.50,1.63),(-.70,1.18,1.63),(.57,1.18,1.63),(.57,1.18,1.28)],.20,.26)
            flange('Delivery vessel outlet mounting collar',(-.70,.84,1.63),.28,'Y')
            cylinder('Delivery pump straight inlet neck',(.57,1.18,1.205),.20,.17,steel)
            actuator(-.10,1.18,1.96,.38)
        if role=='liquid-request':
            box('Protected automation instrument enclosure',(.52,1.08,.82),(.34,.25,.48),steel,.025)
            box('Violet machine status strip',(.52,1.215,.94),(.22,.016,.055),violet,.006)
            box('Instrument enclosure mounting foot',(.52,1.08,.42),(.26,.22,.33),steel,.015)
        lens(1.24,1.335,.73)


def roof_wear(role):
    # The old flat-roof scratches no longer match the reconstructed lids.
    pass


def flange(name,loc,r,axis='Z',mat=None):
    x,y,z=loc
    inner=r*.55;verts=[]
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
    if role=='buffer':
        for y in [-.52,.52]:
            box('Spine roof vent recess',(0,y,2.715),(.16,.36,.025),black,.008)
            for d in [-.12,-.06,0,.06,.12]:box('Spine roof grille',(0,y+d,2.735),(.14,.015,.018),edge,.002)
            for x in [-.105,.105]:rod('Spine hydraulic copper rail',(x,y-.23,2.72),(x,y+.23,2.72),.022,copper)
            box('Orange spine actuator shoe',(0,y,2.74),(.22,.16,.055),trim,.01)
            panel_fasteners(0,y,2.78,.14,.08,'Z')
    elif role=='provider':
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
    if role=='provider':
        for a in [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]:
            for offset in [-.07,.07]:
                dx,dy=math.cos(a),math.sin(a)
                beam('Radial lock reinforcement',(dx*.99-dy*offset,dy*.99+dx*offset,2.48),(dx*1.31-dy*offset,dy*1.31+dx*offset,2.42),.075,.075,steel)
        for x in [-.57,.57]:
            box('Roof locking bridge end plate',(x,0,2.65),(.28,.25,.025),edge,.015)
            for y in [-.08,.08]:bolt((x,y,2.68),radius=.023)
    elif role=='request':
        for x in [-.54,.54]:
            for y in [-.74,.74]:
                box('Hatch latch tab',(x,y,2.52),(.10,.18,.045),steel,.012)
                bolt((x,y+.035,2.56),radius=.025)
        for y in [-1.0,1.0]:
            for x in [-.20,.20]:
                box('Heavy central hinge fork',(x,y,2.57),(.10,.25,.22),trim,.02)
                bolt((x,y,2.70),radius=.03)
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
        box('Open side scaffold rail',(sign*1.34,0,.77),(.085,2.39,.09),steel,.012)
        if sign==1:box('Rear scaffold rail',(0,-1.34,.65),(2.39,.085,.09),steel,.012)
        for y in [-.87,.87]:
            beam('Open scaffold diagonal',(sign*1.34,y,.25),(sign*1.34,y*.65,.73),.065,.065,steel)
    if role=='fuel':
        box('Fuel machinery mounting tray',(.57,.60,.35),(1.17,1.58,.12),steel,.02)
    else:
        box('Front machinery crossmember',(0,1.08,.26 if role=='liquid-request' else .35),(2.14,.38,.16 if role=='liquid-request' else .14),steel,.014)
        if role=='liquid-buffer':box('Central regulator mounting foot',(0,.89,.44),(.30,.30,.20),steel,.012)
        for x in [-.96,.96]:
            box('Front open frame rail',(x,1.33,.40),(.44,.085,.10),steel,.012)
    tanks=[(.64,-.33,.64,2.03)] if role=='fuel' else ([(-.64,-.25,.64,1.97),(.64,-.25,.64,1.97)] if role=='liquid-buffer' else [(0,-.25,1.16,2.20)])
    for x,y,r,height in tanks:
        top=height
        for a in [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]:
            dx,dy=math.cos(a),math.sin(a)
            beam('Pressure shell base foot',(x+dx*(r+.04),y+dy*(r+.04),.43),(x+dx*(r+.025),y+dy*(r+.025),.73),.16,.14,steel)
        # Flush inspection covers replace small rooftop service fittings.
        for a in range(4):
            t=a*math.pi/2
            box('Low manway retaining tab',(x+r*.36*math.cos(t),y+r*.36*math.sin(t),top+.13),(.075,.12,.055),copper,.008)
            bolt((x+r*.36*math.cos(t),y+r*.36*math.sin(t),top+.17),radius=.02)
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
        flange('Fuel automatic docking flange',(.634,1.405,.80),.30,'Y')
        cylinder('Fuel service bore',(.634,1.451,.80),.22,.018,black,'Y')
        lens(1.24,1.335,.73)
    elif role=='liquid-provider':
        for x in [-.32,.14]:flange('Delivery header union',(x,1.18,1.63),.28,'X')
        flange('Delivery pump seated inlet',(.57,1.18,1.29),.28)
    elif role=='liquid-request':
        flange('Oversized inlet union',(-.60,.91,1.75),.28,'Y')
        flange('Receiving pump inlet collar',(-.60,1.20,1.27),.28)
        for i in range(10):
            a=i*math.tau/10;bolt((-.60+.275*math.cos(a),1.35,.73+.275*math.sin(a)),'Y',.025)
        for x in [-.80,-.40]:
            box('Pump mounting foot',(x,1.12,.32),(.13,.32,.22),steel,.016)
        box('Front pump chevron plate',(-.60,1.39,.30),(.40,.055,.20),steel,.012)
        for dx in [-.15,.15]:rod('Pump guard mounting standoff',(-.60+dx,1.20,.30),(-.60+dx,1.39,.30),.022,steel)
        chevron(-.60,1.423,.32,.28,edge,double=False,relief=.012)
    else:
        for x in [-.51,.51]:
            flange('Buffer automatic dock collar',(x,1.25,.90),.30,'Y',trim)
            torus('Coupling machined mouth',(x,1.405,.90),.215,.025,edge,'Y')
            panel_fasteners(x,1.31,.61,.23,.27)
        box('Regulator bolted front cover',(0,1.08,1.12),(.35,.06,.28),steel,.025)
        panel_fasteners(0,1.12,1.12,.25,.18)
        for x in [-.235,.235]:
            box('Center pedestal orange wear rail',(x,1.43,.56),(.07,.07,.47),trim,.012)


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
    if role=='provider':
        for y in [-.99,.99]:
            box('Raised north south roof lock',(0,y,2.60),(.34,.20,.12),trim,.018)
            for x in [-.11,.11]:bolt((x,y,2.68),radius=.027)


def reference_fluid_hardware(role):
    tanks=[(.64,-.33,.64,2.03)] if role=='fuel' else ([(-.64,-.25,.64,1.97),(.64,-.25,.64,1.97)] if role=='liquid-buffer' else [(0,-.25,1.16,2.20)])
    for x,y,r,top in tanks:
        shoulder=top-(.25 if role=='fuel' else .42)*r
        # Gasket, clamp dogs and pinned lid restraints interrupt the plain disk.
        torus('Manway dark compression gasket',(x,y,top+.06),r*.365,.022,black)
        for i in range(6):
            a=i*math.tau/6;dx,dy=math.cos(a),math.sin(a)
            clamp=box('Manway forged clamp dog',(x+dx*r*.37,y+dy*r*.37,top+.15),(.09,.17,.10),steel,.015)
            clamp.rotation_euler.z=a-math.pi/2
            bolt((x+dx*r*.37,y+dy*r*.37,top+.215),radius=.025)
        for a in [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]:
            dx,dy=math.cos(a),math.sin(a)
            for z in [.82,shoulder-.19]:
                start=(x+dx*(r+.055),y+dy*(r+.055),z)
                end=(x+dx*(r+.085),y+dy*(r+.085),z)
                rod('Strap transverse rivet',start,end,.033,brass)
            shoe=box('Shoulder strap lock shoe',(x+dx*(r+.05),y+dy*(r+.05),shoulder-.035),(.22,.12,.17),trim,.018)
            shoe.rotation_euler.z=a+math.pi/2
            # A second cast brace at the base is anchored to the pressure flange.
            beam('Tank foot diagonal gusset',(x+dx*(r+.105),y+dy*(r+.105),.44),(x+dx*(r+.03),y+dy*(r+.03),.79),.12,.12,steel)
    if role=='fuel':
        for x in [-1.18,-.10]:
            for y in [-1.02,.58]:
                taper('Fuel hopper armored lower post',(x,y,.97),(.19,.22),(.15,.19),.94,steel,.035)
                for z in [.64,1.30]:bolt((x,y+.125,z),'Y',.028)
    elif role=='liquid-provider':
        for dx in [-.24,.24]:
            cylinder('Motor cooling end clamp',(dx,1.18,.88),.26,.035,steel,'X')
        for x in [-.35,.12]:
            box('Delivery motor angular mounting saddle',(x,1.18,.59),(.18,.47,.20),steel,.025)
            for dy in [-.19,.19]:bolt((x,1.18+dy,.70),radius=.028)
        # A protected indicator on the dome corresponds to the concept's violet pod.
        cylinder('Dome instrument socket',(.67,.05,2.13),.10,.08,brass)
        cylinder('Violet pressure beacon',(.67,.05,2.22),.070,.16,violet)
        cylinder('Beacon armored top cap',(.67,.05,2.315),.10,.035,steel)
        for dx in [-.07,.07]:
            for dy in [-.07,.07]:rod('Beacon brass cage',(.67+dx,.05+dy,2.16),(.67+dx,.05+dy,2.30),.012,brass)
    elif role=='liquid-request':
        for x in [-.80,-.40]:
            bolt((x,1.12,.44),radius=.026)
    else:
        for x in [-.51,.51]:
            taper('Buffer coupling armored tower',(x,1.08,.64),(.43,.40),(.35,.32),.51,steel,.055)
            for dx in [-.30,.30]:
                box('Buffer coupling keeper',(x+dx,1.32,.91),(.07,.11,.34),trim,.012)
                bolt((x+dx,1.385,.91),'Y',.022)
            for dy in [-.10,.10]:bolt((x,1.08+dy,.91),radius=.028)

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
        if role=='provider':
            for i in range(200):
                a=random.uniform(0,math.tau);r=random.uniform(.30,.75);x,y=r*math.cos(a),r*math.sin(a)
                if abs(y)<.15:continue
                length=random.uniform(.008,.065);w=random.uniform(.001,.004)
                polygon('Sealed lid handling scar',[(x-length,y,2.486),(x,y-w,2.486),(x+length*.5,y,2.486),(x,y+w,2.486)],edge if i%4 else rust)
            for sign in [-1,1]:pipe('Provider lid quadrant seam',[(0,sign*.31,2.489),(0,sign*.74,2.489)],.006,black)
        else:
            for x in [-.54,.54]:
                plane((x,0,2.491),(1,0,0),(0,1,0),.72,1.75,150)
                if role=='buffer':
                    for i in range(60):
                        a=random.uniform(0,math.tau);r=random.uniform(.06,.31);xx=x+r*math.cos(a);y=r*math.sin(a)
                        polygon('Buffer lid scrape',[(xx-.025,y,2.582),(xx,y-.003,2.582),(xx+.014,y,2.582),(xx,y+.002,2.582)],edge if i%4 else rust)
        for x in [-1.07,1.07]:
            for y in [-.68,.68]:plane((x,y,2.395),(1,0,0),(0,1,0),.14,.41,25)
    else:
        if role=='fuel':
            plane((-.64,-.22,2.451),(1,0,0),(0,1,0),.73,1.27,180)
            plane((-.64,.666,1.98),(1,0,0),(0,0,1),.89,.20,70)
        tanks=[(.64,-.33,.64,2.03)] if role=='fuel' else ([(-.64,-.25,.64,1.97),(.64,-.25,.64,1.97)] if role=='liquid-buffer' else [(0,-.25,1.16,2.20)])
        for x,y,r,height in tanks:
            dome=.25 if role=='fuel' else .42
            shoulder=height-dome*r
            def shell(a,z,offset=.015):
                radius=r if z<=shoulder else r*math.sqrt(max(0,1-((z-shoulder)/(dome*r))**2))
                return (x+(radius+offset)*math.cos(a),y+(radius+offset)*math.sin(a),z)
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
    sides=[]
    if role in ['liquid-provider','liquid-buffer']: sides.append((-1,0))
    if role in ['fuel','liquid-request','liquid-buffer']: sides.append((1,0))
    ports=[]
    for sign,game_y in sides:
        seam=sign*size/2
        y=-game_y
        z=.36
        inner=sign*(.65 if size==3 else .34)
        rod('Factory pipe manifold',(inner,y,z),(seam-sign*.10,y,z),.285,steel)
        torus('Factory socket welded reinforcing ring',(seam-sign*.15,y,z),.303,.024,steel,'X')
        marker=bpy.data.objects.new('SOCKET | '+('west' if sign<0 else 'east'),None)
        scene.collection.objects.link(marker)
        marker.parent=root
        marker.location=(seam,y,z)
        marker.empty_display_type='ARROWS'
        marker.empty_display_size=.20
        marker['tile_anchor']=[sign*(size-1)/2,game_y]
        marker['direction']=12 if sign<0 else 4
        ports.append({'direction':marker['direction'],'position':list(marker['tile_anchor']),'seam':[seam,game_y],'height':z})
    return ports


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
    palette={'cab':ROLE_COLORS[key], 'trim':[.80,.38,.12], 'cargo':[.43,.43,.40]}
    for mat,channel in [(rolepaint,'cab'),(trim,'trim'),(housing,'cargo')]:
        color=[((v+.055)/1.055)**2.4 if v>.04045 else v/12.92 for v in palette[channel]]
        ramp=mat.node_tree.nodes['Surface pigment'].color_ramp
        ramp.elements[0].color=(*(v*.3 for v in color),1)
        ramp.elements[1].color=(*color,1)
        mat.diffuse_color=(*color,1)
    configure_depot_materials()
    dial=edge.copy();dial.name='BASE | enamel gauge face'
    dial.node_tree.nodes['Surface pigment'].color_ramp.elements[1].color=(.65,.58,.43,1)
    root=bpy.data.objects.new('Depot | rotate this assembly',None)
    scene.collection.objects.link(root)
    root['forward_axis']='+Y (Factorio north)'
    root['role']=role;root['tile_size']=size
    foundation(role)
    if role in ['provider','request','buffer']:
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
    surface_wear(role)
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
    projection['purpose']='Maps one logical ground tile to equal screen X/Y lengths at 45 degrees elevation'
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
    scene['fidelity_pass']=7
    scene['concept']=f'concepts/depots/images/{role}.png'
    shadow=bpy.data.scenes.new('Ground shadow')
    shadow.render.engine='CYCLES';shadow.cycles.samples=1;shadow.cycles.use_denoising=False
    shadow.render.film_transparent=True;shadow.camera=camera;shadow.collection.objects.link(camera)
    shadow.world=bpy.data.worlds.new('Shadow world');shadow.world.color=(0,0,0)
    shadow.view_settings.view_transform='Standard'
    out=ROOT/role/str(size)
    for folder in ['masters/exr','masters/shadow-silhouettes','masters/layers','frames','sheets','previews']:
        (out/folder).mkdir(parents=True,exist_ok=True)
    metadata={'role':role,'size':size,'fidelity_pass':7,'directions':['north','east','south','west'],'palette':palette,'ortho_scale':camera.data.ortho_scale,'projection_y_scale':math.sqrt(2),'ports':ports,'game_frame_size':512,'game_scale':32*camera.data.ortho_scale/512,'source':f'source/{role}-{size}.blend'}
    (out/'asset.json').write_text(json.dumps(metadata,indent=2)+'\n')
    root.rotation_euler.z=0
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/f'{role}-{size}.blend'))
    print('BUILT',role,size,flush=True)

for role in ROLES if args.role=='all' else [args.role]: build(role,args.size)
