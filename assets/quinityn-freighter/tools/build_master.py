"""Build the editable Quinityn freighter master. Run with Blender 4.3+."""
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
random.seed(1977)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for material in list(bpy.data.materials):
    bpy.data.materials.remove(material)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = False
scene.cycles.max_bounces = 5
scene.cycles.diffuse_bounces = 2
scene.cycles.glossy_bounces = 2
scene.render.threads_mode = "FIXED"
scene.render.threads = 12
scene.render.film_transparent = True
scene.render.resolution_x = 1024
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.72, 0.78, 0.85, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.20

root = bpy.data.objects.new("Freighter | rotate this assembly", None)
scene.collection.objects.link(root)
root["forward_axis"] = "+Y"
root["paint_layers"] = "cab, trim, cargo"

def material(name, color, metallic=0.0, roughness=0.5, paint=None, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    coordinates = nodes.new("ShaderNodeTexCoord")
    def noise_at(label, scale, detail=3):
        node = nodes.new("ShaderNodeTexNoise")
        node.name = label
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = .72
        links.new(coordinates.outputs["Object"], node.inputs["Vector"])
        return node
    noise = noise_at("Uneven coating and oxidation", 3.8)
    micro = noise_at("Fine abrasion", 64, 2)
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.name = "Surface pigment"
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (*(c * .30 for c in color), 1)
    ramp.color_ramp.elements[1].position = 0.74
    ramp.color_ramp.elements[1].color = (*color, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    pigment = ramp.outputs["Color"]
    if not emission:
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.name = "Dirt trapped in seams"
        ao.inputs["Distance"].default_value = .18
        ao.samples = 8
        grime = nodes.new("ShaderNodeMixRGB")
        grime.blend_type = "MULTIPLY"
        grime.inputs[0].default_value = .68
        links.new(pigment, grime.inputs[1])
        links.new(ao.outputs["Color"], grime.inputs[2])
        pigment = grime.outputs[0]
        variation = nodes.new("ShaderNodeMapRange")
        variation.inputs["To Min"].default_value = max(.2, roughness-.10)
        variation.inputs["To Max"].default_value = min(.95, roughness+.18)
        links.new(micro.outputs["Fac"], variation.inputs["Value"])
        links.new(variation.outputs["Result"], shader.inputs["Roughness"])
    coverage = None
    if paint:
        chips = noise_at("Scattered flaked paint", 16, 3)
        cutoff = nodes.new("ShaderNodeMath")
        cutoff.operation = "GREATER_THAN"
        cutoff.inputs[1].default_value = .665
        links.new(chips.outputs["Fac"], cutoff.inputs[0])
        substrate = nodes.new("ShaderNodeValToRGB")
        substrate.name = "Exposed oxidized steel (never tinted)"
        substrate.color_ramp.elements[0].position = .30
        substrate.color_ramp.elements[0].color = (.043,.026,.016,1)
        substrate.color_ramp.elements[1].position = .72
        substrate.color_ramp.elements[1].color = (.22,.17,.105,1)
        links.new(noise.outputs["Fac"], substrate.inputs["Fac"])
        flaked = nodes.new("ShaderNodeMixRGB")
        links.new(cutoff.outputs[0], flaked.inputs[0])
        links.new(pigment, flaked.inputs[1])
        links.new(substrate.outputs["Color"], flaked.inputs[2])
        pigment = flaked.outputs[0]
        coverage = nodes.new("ShaderNodeMath")
        coverage.operation = "SUBTRACT"
        coverage.inputs[0].default_value = 1
        links.new(cutoff.outputs[0], coverage.inputs[1])
    links.new(pigment, shader.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .14 if not emission else 0
    bump.inputs["Distance"].default_value = .009
    links.new(micro.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    if emission:
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
    if paint:
        mat["paint_channel"] = paint
        mat["default_linear_rgb"] = color
        aov = nodes.new("ShaderNodeOutputAOV")
        aov.name = "mask_" + paint
        aov.aov_name = "mask_" + paint
        links.new(coverage.outputs[0], aov.inputs["Value"])
    return mat

steel = material("BASE | dark cast steel", (0.11, 0.115, 0.12), 0.76, 0.52)
edge = material("BASE | worn steel edges", (0.33, 0.32, 0.29), 0.8, 0.43)
black = material("BASE | deep recess", (0.012, 0.016, 0.019), 0.2, 0.7)
rubber = material("BASE | tire rubber", (0.035, 0.038, 0.04), 0, 0.84)
tread = material("BASE | worn tread", (0.055, 0.059, 0.06), 0, 0.76)
copper = material("BASE | aged copper", (0.37, 0.17, 0.075), 0.78, 0.34)
brass = material("BASE | brass", (0.46, 0.33, 0.13), 0.72, 0.38)
cab = material("PAINT | cab", (0.196, 0.055, 0.296), 0.45, 0.60, "cab")
trim = material("PAINT | trim", (0.570, 0.155, 0.017), 0.48, 0.57, "trim")
cargo = material("PAINT | cargo", (0.107, 0.179, 0.285), 0.48, 0.61, "cargo")
rust = material("BASE | old oxide and seam deposits", (.13,.061,.025), .25, .84)
scuff = material("BASE | dark rubbed substrate", (.08,.075,.062), .62, .62)

# Armored glass has a clean coated surface, a dark interior and grazing
# reflections. It must not inherit the grain/bump shader used for cast metal.
glass = bpy.data.materials.new("BASE | smoky armored teal glass")
glass.use_nodes = True
nodes, links = glass.node_tree.nodes, glass.node_tree.links
shader = nodes.get("Principled BSDF")
shader.inputs["Metallic"].default_value = .24
shader.inputs["Roughness"].default_value = .17
shader.inputs["Coat Weight"].default_value = .65
shader.inputs["Coat Roughness"].default_value = .12
shader.inputs["IOR"].default_value = 1.48
facing = nodes.new("ShaderNodeLayerWeight")
glaze = nodes.new("ShaderNodeValToRGB")
glaze.name = "Smoked teal reflection gradient"
glaze.color_ramp.elements[0].color = (.008,.020,.023,1)
glaze.color_ramp.elements[1].color = (.026,.080,.088,1)
links.new(facing.outputs["Facing"], glaze.inputs["Fac"])
coordinates = nodes.new("ShaderNodeTexCoord")
reflection_axis = nodes.new("ShaderNodeVectorMath")
reflection_axis.operation = "DOT_PRODUCT"
reflection_axis.inputs[1].default_value = (.13,.18,.82)
links.new(coordinates.outputs["Generated"], reflection_axis.inputs[0])
reflection = nodes.new("ShaderNodeValToRGB")
reflection.name = "Broad subdued sky reflection"
reflection.color_ramp.interpolation = "EASE"
# Configure existing stops before inserting new ones: Blender reallocates
# the underlying ramp array when a stop is inserted.
reflection.color_ramp.elements[0].position = .20
reflection.color_ramp.elements[0].color = (.010,.026,.029,1)
reflection.color_ramp.elements[1].position = .92
reflection.color_ramp.elements[1].color = (.018,.050,.055,1)
reflection.color_ramp.elements.new(.57).color = (.025,.078,.087,1)
reflection.color_ramp.elements.new(.70).color = (.045,.120,.133,1)
links.new(reflection_axis.outputs["Value"], reflection.inputs["Fac"])
reflected_glass = nodes.new("ShaderNodeMixRGB")
reflected_glass.inputs[0].default_value = .68
links.new(glaze.outputs["Color"], reflected_glass.inputs[1])
links.new(reflection.outputs["Color"], reflected_glass.inputs[2])
links.new(reflected_glass.outputs[0], shader.inputs["Base Color"])
violet = material("BASE | violet power lenses", (0.50, 0.06, 0.85), 0.25, 0.23, emission=1.1)
lamp = material("BASE | warm headlights", (1, 0.83, 0.52), 0.15, 0.2, emission=1.2)
amber = material("BASE | amber marker lights", (1, 0.26, 0.015), 0.15, 0.2, emission=1.6)
red = material("BASE | red rear lights", (0.7, 0.008, 0.006), 0.15, 0.24, emission=1.5)

def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    obj.parent = root
    if bevel:
        modifier = obj.modifiers.new("Manufactured edge radius", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier = obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
        modifier.keep_sharp = True
    return obj

def box(name, location, size, mat=steel, bevel=0.04, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rotation:
        obj.rotation_euler = rotation
    return finish(obj, name, mat, bevel)

def cylinder(name, location, radius, depth, mat=edge, axis="Z", vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    if axis == "X":
        obj.rotation_euler[1] = math.pi / 2
    if axis == "Y":
        obj.rotation_euler[0] = math.pi / 2
    finish(obj, name, mat, 0.012)
    for polygon in obj.data.polygons:
        polygon.use_smooth = len(polygon.vertices) == 4
    return obj

def torus(name, location, major, minor, mat=edge, axis="Z"):
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=10, location=location,
                                    major_radius=major, minor_radius=minor)
    obj = bpy.context.object
    if axis == "X":
        obj.rotation_euler[1] = math.pi / 2
    if axis == "Y":
        obj.rotation_euler[0] = math.pi / 2
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return finish(obj, name, mat)

def pipe(name, points, radius=0.045, mat=copper):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 10
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for p, coordinate in zip(spline.bezier_points, points):
        p.co = coordinate
        p.handle_left_type = "AUTO"
        p.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    return finish(obj, name, mat)

def panel(name, vertices, mat, thickness=0.025):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    finish(obj, name, mat)
    solid = obj.modifiers.new("Panel gauge", "SOLIDIFY")
    solid.thickness = thickness
    bevel = obj.modifiers.new("Panel edge", "BEVEL")
    bevel.width = 0.016
    bevel.segments = 2
    return obj

def bolt(location, axis="Z", radius=0.035, mat=brass):
    return cylinder("Fastener", location, radius, 0.025, mat, axis, 6)

def wear_patch(name, center, tangent, bitangent, length, width, mat):
    """An irregular flat chip/stain, attached to the model rather than a view."""
    center, tangent, bitangent = Vector(center), Vector(tangent), Vector(bitangent)
    vertices = []
    for i in range(9):
        angle = math.tau * i / 9
        radius = random.uniform(.62, 1)
        vertices.append(center + tangent * (math.cos(angle)*length*radius/2)
                        + bitangent * (math.sin(angle)*width*radius/2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return finish(obj, name, mat)

# The fixed chassis datum is at the ground plane beneath the vehicle center.
box("Ladder chassis", (0, 0, 1.15), (2.45, 10.4, 0.32), black)
for x in [-0.95, 0.95]:
    box("Chassis rail", (x, 0, 1.28), (0.2, 10.6, 0.33), steel)
for y in [-4.8, -3.3, -1.2, 0.8, 2.5, 4.4]:
    box("Crossmember", (0, y, 1.12), (2.6, 0.18, 0.22), edge)

# Eight individually modeled road wheels, hubs, bolts, sidewalls and tire blocks.
axles = [-4.18, -2.12, 1.28, 3.95]
for axle, y in enumerate(axles):
    cylinder("Axle", (0, y, 0.88), 0.13, 3.0, steel, "X")
    cylinder("Differential", (0, y, 0.88), 0.27, 0.5, steel, "X")
    for side in [-1, 1]:
        x = side * 1.39
        cylinder("Tire carcass", (x, y, 0.88), 0.79, 0.54, rubber, "X", 48)
        torus("Sidewall bead", (x + side * 0.265, y, 0.88), 0.57, 0.11, rubber, "X")
        cylinder("Wheel rim", (x + side * 0.29, y, 0.88), 0.46, 0.08, steel, "X", 40)
        torus("Rim lip", (x + side * 0.338, y, 0.88), 0.42, 0.035, edge, "X")
        cylinder("Hub cover", (x + side * 0.36, y, 0.88), 0.20, 0.12, brass, "X")
        cylinder("Hub cap", (x + side * 0.43, y, 0.88), 0.135, 0.022, edge, "X")
        for i in range(10):
            angle = i * math.tau / 10
            bolt((x + side * 0.35, y + 0.32 * math.sin(angle), 0.88 + 0.32 * math.cos(angle)), "X", 0.038)
        for i in range(28):
            angle = i * math.tau / 28
            for stripe in [-1, 1]:
                a = angle + stripe * 0.022
                box("Tread block", (x + stripe * 0.135, y + math.sin(a) * 0.795, 0.88 + math.cos(a) * 0.795),
                    (0.25, 0.14, 0.115), tread, 0.018, (-a, 0, stripe * 0.12))
        # A polygonal mudguard keeps the silhouette deliberately industrial.
        points = [(side*1.66, y-0.98, 1.35), (side*1.66, y-0.72, 1.83),
                  (side*1.66, y+0.72, 1.83), (side*1.66, y+0.98, 1.35)]
        for a, b in zip(points, points[1:]):
            middle = (Vector(a) + Vector(b)) / 2
            length = (Vector(b) - Vector(a)).length
            obj = box("Armored mudguard", middle, (0.55, length, 0.11), steel, 0.035)
            obj.rotation_euler[0] = math.atan2(b[2]-a[2], b[1]-a[1])
        pipe("Brake hose", [(side*0.95,y,1.4),(side*1.1,y+0.3,1.1),(side*1.28,y,0.9)], 0.032, black)

# Sloped cab, with hand-shaped windshield and side panels.
profile = [(2.55, 1.5), (5.17, 1.5), (5.17, 2.28), (4.45, 3.64), (4.18, 3.83), (2.55, 3.83)]
verts = [(x,y,z) for x in [-1.15,1.15] for y,z in profile]
faces = [tuple(range(5,-1,-1)), tuple(range(6,12))]
faces += [(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)]
mesh = bpy.data.meshes.new("Cab shell mesh")
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new("Cab shell", mesh)
scene.collection.objects.link(obj)
finish(obj, "Cab shell", cab, 0.055)

# A load-bearing armor frame surrounds the glazing; purple is inset plating.
panel("Windshield backing armor", [(-1.19,5.075,2.70),(1.19,5.075,2.70),
                                     (1.19,4.595,3.57),(-1.19,4.595,3.57)],steel,.055)
panel("Windshield center armored mullion", [(-.075,5.105,2.73),(.075,5.105,2.73),
                                             (.075,4.66,3.55),(-.075,4.66,3.55)],edge,.035)
panel("Lower windshield impact sill", [(-1.19,5.16,2.63),(1.19,5.16,2.63),
                                        (1.19,5.075,2.79),(-1.19,5.075,2.79)],steel,.07)
panel("Heavy sloped roof brow", [(-1.23,4.72,3.57),(1.23,4.72,3.57),
                                  (1.19,4.42,3.95),(-1.19,4.42,3.95)],steel,.07)
for x in [-1.08,-.70,-.30,.30,.70,1.08]:
    bolt((x,4.635,3.73),"Y",.034,edge)
    bolt((x,5.155,2.69),"Y",.031,edge)

# Windshield sections lie on the upper portion of the sloping front face.
for side in [-1,1]:
    x1, x2 = sorted([side*0.08, side*1.02])
    panel("Windshield gasket", [(x1,4.98,2.76),(x2,4.98,2.76),(x2,4.56,3.55),(x1,4.56,3.55)], black, 0.04)
    panel("Armored windshield", [(x1+0.055,5.06,2.82),(x2-0.055,5.06,2.82),
                                 (x2-0.055,4.69,3.49),(x1+0.055,4.69,3.49)], glass)
    # Separate armored glazing retainers keep the glass from reading as a
    # luminous cyan panel. Tiny deposits follow the gasket, outside the glass.
    for x in [x1+.025, x2-.025]:
        pipe("Windshield steel retainer", [(x,5.075,2.79),(x,4.685,3.52)], .045,steel)
        for z in [2.88,3.40]:
            y=5.06-(z-2.82)*(.37/.67)
            bolt((x,y+.026,z),"Y",.022,edge)
    pipe("Windshield lower seal deposit",[(x1+.07,5.078,2.835),(x2-.07,5.078,2.835)],.012,scuff)
    pipe("Windshield wiper", [(side*0.16,5.11,2.81),(side*0.78,4.85,3.18)], 0.019, edge)
    x = side*1.205
    panel("Side window gasket", [(x,3.0,2.62),(x,4.64,2.62),(x,4.17,3.62),(x,3.0,3.62)], black, 0.035)
    panel("Side glazing", [(x+side*.026,3.08,2.74),(x+side*.026,4.43,2.74),
                           (x+side*.026,4.11,3.49),(x+side*.026,3.08,3.49)], glass)
    pipe("Side window bottom seal",[(x+side*.041,3.08,2.745),(x+side*.041,4.42,2.745)],.015,scuff)
    pipe("Side window armored top",[(x+side*.042,3.02,3.55),(x+side*.042,4.15,3.55)],.038,steel)
    box("Door armored surround", (side*1.24,3.46,2.12), (.12,1.48,.90),steel,.028)
    box("Door lower inset paint", (side*1.306,3.46,2.12), (.028,1.08,.57),cab,.025)
    for y in [2.80,4.12]:
        box("Door armor edge",(side*1.325,y,2.12),(.05,.13,.88),edge,.018)
        for z in [1.82,2.43]:
            bolt((side*1.365,y,z),"X",.034,steel)
    box("Door handle", (side*1.36,2.98,2.48), (.07,.26,.07), edge, .02)
    box("Cab rear armored pillar",(side*1.25,2.80,3.19),(.18,.25,1.24),steel,.035)
    for z in [2.69,3.10,3.64]:
        bolt((side*1.36,2.80,z),"X",.039,edge)
    panel("Sloped cab A pillar",[(side*1.28,4.43,2.61),(side*1.28,4.71,2.61),
                                  (side*1.28,4.28,3.70),(side*1.28,4.03,3.70)],steel,.07)
    for y,z in [(4.54,2.77),(4.24,3.48)]:
        bolt((side*1.34,y,z),"X",.038,edge)
    pipe("Door grab bar", [(side*1.30,2.78,1.76),(side*1.30,2.72,2.35),(side*1.30,2.72,2.74)], .034, edge)
    for z in [1.16,1.43]:
        box("Cab access step", (side*1.35,2.86,z), (.48,.58,.075), edge, .02)
        for y in [2.65,2.78,2.91,3.04]:
            box("Step grip", (side*1.37,y,z+.045), (.34,.026,.018), black, .004)
    pipe("Mirror bracket", [(side*1.19,4.22,3.3),(side*1.53,4.29,3.27),(side*1.54,4.3,2.97)], .035, edge)
    box("Mirror housing", (side*1.56,4.31,3.12), (.15,.25,.40), steel, .035)
    box("Mirror glass", (side*1.65,4.32,3.12), (.018,.18,.30), edge, .01)
    for y in [2.76,3.34,3.92]:
        bolt((side*1.24,y,1.87),"X")

box("Cab roof armor", (0,3.36,3.84), (2.32,1.72,.12), steel,.045)
box("Inset roof paint panel",(0,3.36,3.905),(1.86,1.38,.026),cab,.02)
box("Cab rear roof crossmember",(0,2.63,3.94),(2.34,.16,.14),steel,.025)
for x in [-.94,.94]:
    box("Cab roof steel rail", (x,3.37,3.94), (.23,1.85,.13), edge,.025)
    for y in [2.65,3.1,3.7,4.05]:
        bolt((x,y,4.02))
box("Roof vent recess", (0,3.38,3.93), (.83,.86,.08), black,.02)
for x in [-.47,.47]:
    box("Roof hatch rim",(x,3.38,3.99),(.10,1.03,.08),steel,.018)
    for y in [2.95,3.81]:
        bolt((x,y,4.04),radius=.03,mat=edge)
for y in [2.91,3.85]:
    box("Roof hatch rim",(0,y,3.99),(1.01,.09,.08),steel,.018)
for x in [-.32,-.24,-.16,-.08,0,.08,.16,.24,.32]:
    box("Roof vent grille", (x,3.38,3.99), (.028,.77,.025), edge,.004)
for y in [3.12,3.36,3.6]:
    box("Roof grille crossbar", (0,y,4.01), (.77,.018,.018), edge,.003)
cylinder("Antenna base", (.77,2.7,4.0), .08,.12,steel)
cylinder("Antenna", (.77,2.7,4.29), .018,.48,black,vertices=10)

# Blunt grille and bumper, with lamps retained in the base layer.
box("Front grille recess", (0,5.23,2.04), (1.34,.13,.85), black,.05)
for x in [-.57,-.38,-.19,0,.19,.38,.57]:
    box("Grille vertical", (x,5.31,2.04), (.032,.04,.72), edge,.006)
for z in [1.72,1.85,1.98,2.11,2.24,2.37]:
    box("Grille horizontal", (0,5.33,z), (1.24,.035,.025), steel,.005)
box("Front bumper", (0,5.41,1.37), (2.95,.34,.37), steel,.065)
box("Front center armor", (0,5.60,1.4), (1.21,.06,.29), edge,.035)
box("Upper grille armored crossmember",(0,5.285,2.55),(2.45,.16,.19),steel,.025)
box("Front inset identification plate",(0,5.377,2.55),(.68,.025,.105),cab,.01)
for side in [-1,1]:
    box("Bumper end armor",(side*1.16,5.55,1.40),(.58,.20,.48),steel,.035)
    for x in [side*.98,side*1.34]:
        bolt((x,5.675,1.53),"Y",.042,edge)
    box("Headlight block", (side*1.04,5.18,2.12), (.56,.28,.62), steel,.025)
    cylinder("Headlight bezel", (side*1.04,5.34,2.14), .175,.08,brass,"Y",32)
    cylinder("Headlight lens", (side*1.04,5.395,2.14), .135,.035,lamp,"Y",32)
    box("Marker housing", (side*.9,4.65,3.76), (.18,.18,.09),steel,.025)
    box("Amber roof marker", (side*.9,4.67,3.815), (.12,.13,.045),amber,.015)
    pipe("Front protective rail", [(side*1.42,5.5,1.55),(side*1.42,5.5,2.49),(side*.83,5.25,2.58)], .065,edge)
    torus("Tow eye", (side*.95,5.65,1.25), .12,.035,brass,"Y")
    for x in [side*.77,side*1.24]:
        bolt((x,5.60,1.49),"Y",.045)

# Power module with finned block, circular fan, pipes, cylinders and four lenses.
box("Engine bed", (0,1.63,1.63), (2.55,1.6,.28),steel)
box("Power block", (0,1.65,2.55), (2.03,1.43,1.58),steel,.12)
for side in [-1,1]:
    for y in [1.12,1.26,1.40,1.54,1.68,1.82,1.96,2.1]:
        box("Cooling fin", (side*1.06,y,2.74), (.12,.047,1.03),edge,.01)
    box("Violet cell housing", (side*1.22,1.63,2.25), (.24,.83,.65),black,.08)
    for y in [1.40,1.85]:
        for z in [2.08,2.44]:
            cylinder("Power port rim", (side*1.38,y,z), .135,.09,edge,"X")
            cylinder("Violet power lens", (side*1.44,y,z), .09,.025,violet,"X")
    pipe("Large copper coolant loop", [(side*1.18,1.04,1.76),(side*1.34,1.08,2.9),
                                      (side*1.16,1.13,3.38),(side*.6,1.25,3.49)],.075,copper)
    pipe("Lower service line", [(side*1.25,2.25,2.9),(side*1.45,2.15,1.91),
                               (side*1.36,1.3,1.82),(side*1.3,.95,2.2)],.045,edge)
    cylinder("Filter canister", (side*.95,2.18,2.99), .13,.72,edge)
    for z in [2.75,3.19]:
        cylinder("Filter ring", (side*.95,2.18,z), .15,.055,brass)
# Keep a genuinely circular fan inside the existing service bay. The previous
# outer radius .865 at y1.61 intersected cargo's front plane at y.94.
fan_y, fan_outer, fan_z = 1.74, .745, 3.88
assert fan_y-fan_outer > .94+.04 and fan_y+fan_outer < 2.55-.04
root["fan_cargo_clearance"] = fan_y-fan_outer-.94
root["fan_cab_clearance"] = 2.55-fan_y-fan_outer
root["fan_rim_height"] = fan_z
# A real supporting plenum lifts the full flange above neighboring bodywork.
cylinder("Raised fan plenum", (0,fan_y,3.56), .73,.44,steel,vertices=64)
cylinder("Fan recess", (0,fan_y,fan_z-.10), .74,.15,black,vertices=64)
torus("Brass fan surround", (0,fan_y,fan_z), .69,.055,brass)
cylinder("Fan hub", (0,fan_y,fan_z+.01), .17,.12,edge)
for i in range(14):
    angle=i*math.tau/14
    x=math.sin(angle)*.40;y=fan_y+math.cos(angle)*.40
    box("Fan blade", (x,y,fan_z-.05), (.13,.49,.045),edge,.012,(0,.16,-angle+.24))
for i in range(12):
    angle=i*math.tau/12
    bolt((math.sin(angle)*.69,fan_y+math.cos(angle)*.69,fan_z+.06),radius=.027)
for z in [2.0,2.6,3.0]:
    cylinder("Exhaust sleeve", (-.93,1.03,z), .13,.45,steel)
cylinder("Exhaust heat guard", (-.93,1.03,3.44), .17,.85,edge)
cylinder("Exhaust mouth", (-.93,1.03,3.88), .13,.035,black)
for z in [3.16,3.30,3.44,3.58,3.72]:
    for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
        # Shallow black studs suggest perforated heat shielding at sprite scale.
        cylinder("Heat shield perforation",(-.93+.165*math.cos(angle),1.03+.165*math.sin(angle),z),.034,.015,black,"X",10)

# Three full cargo bays. All large paint surfaces belong to the cargo channel.
box("Freight vault inner shell", (0,-2.18,2.68),(2.52,6.24,2.35),black,.14)
bay_centers=[-.18,-2.18,-4.18]
for index,y in enumerate(bay_centers):
    box("Cargo roof panel %d"%index,(0,y,3.93),(2.46,1.86,.18),cargo,.09)
    for side in [-1,1]:
        box("Cargo side panel %d"%index,(side*1.285,y,2.84),(.10,1.87,1.98),cargo,.055)
        # Diagonal stiffening ribs are steel, outside the recolorable paint.
        pipe("Panel diagonal rib",[(side*1.35,y-.80,1.96),(side*1.35,y+.78,3.65)],.023,steel)
        box("Cargo inspection vent",(side*1.36,y+.51,2.10),(.04,.37,.27),black,.018)
        for z in [2.01,2.07,2.13,2.19]:
            box("Vent slat",(side*1.39,y+.51,z),(.03,.30,.014),edge,.003)
        for dy in [-.78,-.34,.34,.78]:
            for z in [1.98,3.67]:
                bolt((side*1.36,y+dy,z),"X",.027)
    for dy in [-.74,.74]:
        box("Roof panel seam",(0,y+dy,4.04),(2.24,.035,.025),edge,.005)
    box("Roof recessed vent",(0,y+.53,4.035),(.74,.22,.02),black,.008)
    for x in [-.30,-.20,-.10,0,.10,.20,.30]:
        box("Roof vent slot",(x,y+.53,4.052),(.035,.18,.012),edge,.002)

for y in [.82,-1.18,-3.18,-5.18]:
    box("Vault roof structural band",(0,y,4.08),(2.70,.22,.18),steel,.045)
    for x in [-.91,-.45,0,.45,.91]:
        bolt((x,y,4.18),radius=.04)
    for side in [-1,1]:
        box("Vault upright",(side*1.39,y,2.80),(.19,.22,2.43),steel,.035)
        for z in [1.76,3.73]:
            box("Recolorable locking clamp",(side*1.43,y,z),(.23,.45,.43),trim,.035)
            for dy in [-.13,.13]:
                bolt((side*1.56,y+dy,z),"X",.037,edge)
        box("Recolorable roof clamp",(side*1.15,y,4.13),(.38,.43,.15),trim,.045)
        bolt((side*1.15,y,4.22),radius=.042,mat=edge)
        cylinder("External locking rod",(side*1.52,y,2.75),.045,1.38,edge)
        for z in [2.15,2.83,3.29]:
            cylinder("Rod collar",(side*1.52,y,z),.08,.13,brass)
        box("Latch housing",(side*1.54,y,3.09),(.13,.25,.25),steel,.025)

for side in [-1,1]:
    box("Freight lower edge rail",(side*1.36,-2.15,1.63),(.20,6.37,.18),edge,.035)
    box("Purple lower service trim",(side*1.43,-1.05,1.40),(.12,1.4,.15),cab,.025)
    box("Underbody tool locker",(side*1.19,-.57,1.1),(.53,1.25,.64),steel,.055)
    box("Tool locker grille",(side*1.48,-.57,1.12),(.04,.95,.45),black,.012)
    for y in [-.93,-.78,-.63,-.48,-.33,-.18]:
        box("Tool grille bar",(side*1.51,y,1.12),(.03,.024,.40),edge,.004)
    pipe("Long copper line",[(side*1.30,.6,1.45),(side*1.34,-1.0,1.44),
                             (side*1.33,-2.8,1.44),(side*1.30,-4.9,1.43)],.035,copper)

# Rear double loading doors, locking rods, hinges and chassis fixtures.
for side in [-1,1]:
    box("Rear loading door",(side*.63,-5.34,2.80),(1.17,.12,2.08),cargo,.055)
    box("Rear door edge",(side*.07,-5.43,2.80),(.09,.08,2.20),edge,.016)
    cylinder("Rear door locking rod",(side*.38,-5.46,2.80),.044,1.84,brass)
    for z in [1.92,2.54,3.52]:
        box("Rear door hinge",(side*1.13,-5.43,z),(.18,.14,.20),edge,.025)
        cylinder("Door lock collar",(side*.38,-5.46,z),.075,.12,steel)
    pipe("Rear pull handle",[(side*.38,-5.50,2.60),(side*.59,-5.55,2.60),
                             (side*.60,-5.55,2.36)],.03,edge)
    box("Rear lamp bracket",(side*.93,-5.45,1.52),(.47,.16,.18),black,.025)
    for x in [side*.80,side*1.06]:
        box("Rear red lens",(x,-5.55,1.53),(.15,.045,.10),red,.015)
    box("Upper rear marker",(side*1.10,-5.32,4.10),(.17,.15,.075),amber,.02)
box("Rear crash beam",(0,-5.46,1.20),(2.86,.27,.25),steel,.05)
box("Tow receiver",(0,-5.66,1.22),(.35,.23,.26),edge,.025)
box("Receiver opening",(0,-5.79,1.22),(.18,.015,.14),black,.005)

# Surface construction and wear are geometric, so they survive arbitrary views
# and remain editable independently of the procedural paint pigment.
for side in [-1,1]:
    x=side*1.255
    for y in [2.68,4.24]:
        box("Cab corner armor",(x,y,3.54),(.16,.32,.46),steel,.05)
        bolt((x+side*.09,y,3.53),"X",.042)
    box("Cab sill armor",(x,3.45,1.73),(.16,1.78,.15),edge,.025)
    box("Cab roof overhang",(side*.84,4.27,3.87),(.55,.27,.18),steel,.045)
    pipe("Door armor seam",[(x,2.83,1.84),(x,4.12,1.84),(x,4.18,2.48)],.025,edge)
    box("Side cab vent recess",(side*1.27,2.78,3.09),(.035,.20,.48),black,.012)
    for z in [2.92,3.00,3.08,3.16,3.24]:
        box("Side cab vent slat",(side*1.30,2.78,z),(.025,.17,.018),edge,.004)
    for y in bay_centers:
        for z in [1.92,3.74]:
            box("Cargo panel edge strip",(side*1.355,y,z),(.035,1.70,.055),edge,.009)
        for dy in [-.85,.85]:
            box("Cargo inset vertical seam",(side*1.35,y+dy,2.83),(.035,.04,1.75),steel,.007)
        for j in range(38):
            dy=random.uniform(-.78,.78)
            z=random.choice([random.uniform(1.94,2.10),random.uniform(3.48,3.68),random.uniform(2.1,3.5)])
            box("Exposed paint chip",(side*1.347,y+dy,z),(.008,random.uniform(.016,.075),random.uniform(.009,.028)),edge,.002)
        for j in range(9):
            dy=random.uniform(-.7,.7)
            z=random.uniform(2.15,3.43)
            pipe("Service scratch",[(side*1.349,y+dy,z),(side*1.35,y+dy+.07,z+.08)],.0055,edge)
    for y in [.82,-1.18,-3.18,-5.18]:
        for dy in [-.11,.11]:
            box("Upright bright edge",(side*1.51,y+dy,2.82),(.025,.025,1.42),edge,.006)
        for z in [1.76,3.73]:
            box("Clamp inset",(side*1.565,y,z),(.018,.16,.13),steel,.018)
            bolt((side*1.585,y,z),"X",.036,brass)
    # Hydraulic suspension details remain visible through the wheel gaps.
    for y in axles:
        pipe("Suspension strut",[(side*1.03,y-.25,1.55),(side*1.12,y+.24,.69)],.075,edge)
        for j in range(5):
            cylinder("Spring ring",(side*1.07,y-.10,1.05+j*.10),.12,.055,steel)

for y in bay_centers:
    for j in range(45):
        x=random.uniform(-1.12,1.12)
        dy=random.uniform(-.78,.78)
        box("Roof paint chip",(x,y+dy,4.026),(random.uniform(.015,.065),random.uniform(.008,.035),.006),edge,.002)
    for x in [-1.10,1.10]:
        box("Roof edge channel",(x,y,4.05),(.07,1.72,.055),steel,.012)
for y in [.82,-1.18,-3.18,-5.18]:
    for dy in [-.12,.12]:
        box("Roof band machined edge",(0,y+dy,4.16),(2.17,.032,.035),edge,.006)
for side in [-1,1]:
    for j in range(22):
        box("Cab paint chip",(side*1.325,random.uniform(3.0,3.92),random.uniform(1.91,2.36)),
            (.008,random.uniform(.015,.05),.012),edge,.002)
    for z in [2.52,3.64]:
        pipe("Windshield armored rim",[(side*.07,5.03 if z<3 else 4.52,z),
                                      (side*1.08,5.03 if z<3 else 4.52,z)],.055,steel)
    box("Cab front corner plate",(side*1.06,5.12,2.62),(.29,.16,.23),edge,.04)

# Larger, directional service wear is visible at gameplay size. These patches
# expose untinted substrate and oxide; repainting does not recolor the damage.
for side in [-1,1]:
    for y in bay_centers:
        for j in range(28):
            dy=random.uniform(-.79,.79)
            z=random.choice([random.uniform(1.92,2.24),random.uniform(3.43,3.72)])
            wear_patch("Chipped cargo perimeter",(side*1.341,y+dy,z),(0,1,0),(0,0,1),
                       random.uniform(.06,.24),random.uniform(.018,.07),random.choice([rust,scuff,edge]))
        for j in range(12):
            dy=random.uniform(-.76,.76)
            z=random.uniform(2.35,3.46)
            wear_patch("Cargo rain streak",(side*1.342,y+dy,z),(0,0,1),(0,1,0),
                       random.uniform(.16,.48),random.uniform(.012,.048),rust)
        for j in range(11):
            wear_patch("Cargo handling scrape",(side*1.343,y+random.uniform(-.70,.70),random.uniform(2.02,3.57)),
                       (0,1,.17),(0,0,1),random.uniform(.13,.39),random.uniform(.006,.018),edge)
    for j in range(32):
        wear_patch("Cab door worn coating",(side*1.325,random.uniform(3.0,3.92),random.uniform(1.91,2.36)),
                   (0,1,.12),(0,0,1),random.uniform(.04,.17),random.uniform(.012,.045),random.choice([rust,scuff,edge]))
    for y in axles:
        for j in range(9):
            wear_patch("Mudguard scuffed crown",(side*1.66,y+random.uniform(-.62,.62),1.889),
                       (0,1,0),(1,0,0),random.uniform(.05,.22),random.uniform(.01,.035),random.choice([edge,scuff]))
for y in bay_centers:
    for j in range(48):
        x=random.choice([random.uniform(-1.11,-.85),random.uniform(.85,1.11),random.uniform(-1,1)])
        dy=random.uniform(-.79,.79)
        wear_patch("Roof chipped coating",(x,y+dy,4.027),(1,0,0),(0,1,0),
                   random.uniform(.06,.25),random.uniform(.018,.075),random.choice([rust,scuff,edge]))
    for j in range(17):
        wear_patch("Roof dragging scratch",(random.uniform(-1,1),y+random.uniform(-.7,.7),4.029),
                   (1,.14,0),(0,1,0),random.uniform(.14,.46),random.uniform(.007,.019),edge)
for j in range(48):
    wear_patch("Cab roof service wear",(random.uniform(-.86,.86),random.uniform(2.72,4.00),3.922),
               (1,.10,0),(0,1,0),random.uniform(.05,.20),random.uniform(.012,.04),random.choice([rust,edge,scuff]))


# Camera and fixed lighting. North is +Y and maps toward the top of the frame.
bpy.ops.object.camera_add(location=(0,-16,16))
camera=bpy.context.object
camera.name="CAMERA | 45 degree orthographic game projection"
camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type="ORTHO"
camera.data.ortho_scale=15.8
scene.camera=camera
scene.render.image_settings.file_format="OPEN_EXR_MULTILAYER"
scene.render.image_settings.color_depth="16"
scene.render.image_settings.exr_codec="ZIP"
bpy.ops.object.light_add(type="SUN",location=(-6,-8,12))
sun=bpy.context.object
sun.name="LIGHT | fixed upper left sunlight"
sun.rotation_euler=(Vector((0,0,0))-sun.location).to_track_quat('-Z','Y').to_euler()
sun.data.energy=2.2
sun.data.angle=math.radians(4)
bpy.ops.object.light_add(type="AREA",location=(-5,-7,11))
softbox=bpy.context.object
softbox.name="LIGHT | broad metal highlights"
softbox.rotation_euler=(Vector((0,0,1.6))-softbox.location).to_track_quat('-Z','Y').to_euler()
softbox.data.energy=1000
softbox.data.shape="DISK"
softbox.data.size=7

for channel in ["cab","trim","cargo"]:
    aov=scene.view_layers[0].aovs.add()
    aov.name="mask_"+channel
    aov.type="VALUE"
scene.view_layers[0].name="Vehicle"
scene["direction_count"]=64
scene["heading_zero"]="North (+Y), clockwise positive as viewed from above"
scene["source_reference"]="approved-concept.png"
scene["model_notes"]="Revision 3: armored cab, clear circular fan, service-worn coating and smoky armored glass; unseen surfaces interpreted from modeling-turnaround.png"

# A second scene uses an exact directional-light projection of the geometry for
# the ground shadow. It shares the same camera and rotation datum.
shadow_scene=bpy.data.scenes.new("Ground shadow")
shadow_scene.render.engine="CYCLES"
shadow_scene.cycles.samples=1
shadow_scene.cycles.use_denoising=False
shadow_scene.render.film_transparent=True
shadow_scene.render.resolution_x=1024
shadow_scene.render.resolution_y=1024
shadow_scene.render.resolution_percentage=100
shadow_scene.camera=camera
shadow_scene.collection.objects.link(camera)
shadow_scene.world=bpy.data.worlds.new("Shadow world")
shadow_scene.world.color=(0,0,0)
shadow_scene.render.image_settings.file_format="PNG"
shadow_scene.render.image_settings.color_mode="RGBA"
shadow_scene.render.image_settings.color_depth="16"
shadow_scene.view_settings.view_transform="Standard"
shadow_mat=bpy.data.materials.new("SHADOW | black silhouette")
shadow_mat.use_fake_user=True
shadow_mat.use_nodes=True
nodes=shadow_mat.node_tree.nodes
nodes.clear()
output=nodes.new("ShaderNodeOutputMaterial")
emission=nodes.new("ShaderNodeEmission")
emission.inputs["Color"].default_value=(0,0,0,1)
shadow_mat.node_tree.links.new(emission.outputs[0],output.inputs["Surface"])

root.rotation_euler[2]=math.radians(-225)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/'quinityn-freighter.blend'))
scene.render.resolution_x=768
scene.render.resolution_y=768
scene.render.image_settings.file_format="PNG"
scene.render.image_settings.color_mode="RGBA"
scene.render.image_settings.color_depth="8"
scene.render.filepath=str(ROOT/'previews'/'model-first-pass.png')
bpy.ops.render.render(write_still=True)
