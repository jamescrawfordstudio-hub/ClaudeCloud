# Shared test scene for the stress tests. Builds, without operators, a scene
# that exercises every code path the Viewport Motion Blur patches touch:
# an animated object, an animated camera, a deforming mesh, particle hair,
# and moving native Cycles points (Geometry Nodes points with a radius).

import bpy


def _emission_material(name, color, strength=1.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*color, 1.0)
    emission.inputs["Strength"].default_value = strength
    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return mat


def _grid_mesh(name, size, divisions):
    verts = []
    faces = []
    step = size / divisions
    for j in range(divisions + 1):
        for i in range(divisions + 1):
            verts.append((-size / 2 + i * step, -size / 2 + j * step, 0.0))
    row = divisions + 1
    for j in range(divisions):
        for i in range(divisions):
            a = j * row + i
            faces.append((a, a + 1, a + row + 1, a + row))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    return mesh


def _points_node_group():
    group = bpy.data.node_groups.new("StressPoints", "GeometryNodeTree")
    group.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    group.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    nodes = group.nodes
    links = group.links
    group_in = nodes.new("NodeGroupInput")
    group_out = nodes.new("NodeGroupOutput")
    distribute = nodes.new("GeometryNodeDistributePointsOnFaces")
    distribute.inputs["Density"].default_value = 40.0
    scene_time = nodes.new("GeometryNodeInputSceneTime")
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = 0.15
    combine = nodes.new("ShaderNodeCombineXYZ")
    set_position = nodes.new("GeometryNodeSetPosition")
    set_radius = nodes.new("GeometryNodeSetPointRadius")
    set_radius.inputs["Radius"].default_value = 0.04
    links.new(group_in.outputs[0], distribute.inputs["Mesh"])
    links.new(distribute.outputs["Points"], set_position.inputs["Geometry"])
    links.new(scene_time.outputs["Frame"], scale.inputs[0])
    links.new(scale.outputs[0], combine.inputs["X"])
    links.new(combine.outputs["Vector"], set_position.inputs["Offset"])
    links.new(set_position.outputs["Geometry"], set_radius.inputs["Points"])
    links.new(set_radius.outputs["Points"], group_out.inputs[0])
    return group


def build_scene(with_extras=True):
    """Return a dict of the created objects. The cube is white on black so
    motion blur can be measured from the image."""
    prefs = bpy.context.preferences
    prefs.edit.keyframe_new_interpolation_type = "LINEAR"

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.view_settings.view_transform = "Standard"
    scene.frame_start = 1
    scene.frame_end = 30
    scene.render.use_motion_blur = True
    scene.render.motion_blur_shutter = 1.0
    scene.cycles.samples = 16
    scene.cycles.preview_samples = 16
    scene.cycles.use_denoising = False
    scene.cycles.use_preview_denoising = False
    scene.cycles.seed = 1

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.color = (0.0, 0.0, 0.0)
    if world.node_tree is None:
        world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        background.inputs["Strength"].default_value = 0.0

    for obj in list(scene.objects):
        if obj.type == "LIGHT":
            bpy.data.objects.remove(obj)

    cube = scene.objects.get("Cube")
    if cube is None:
        mesh = bpy.data.meshes.new("Cube")
        mesh.from_pydata(
            [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], [],
            [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)])
        cube = bpy.data.objects.new("Cube", mesh)
        scene.collection.objects.link(cube)
    cube.data.materials.clear()
    cube.data.materials.append(_emission_material("StressWhite", (1.0, 1.0, 1.0)))
    cube.scale = (0.6, 0.6, 0.6)
    cube.location = (-1.5, 0.0, 0.0)
    cube.keyframe_insert("location", frame=1)
    cube.location = (1.5, 0.0, 0.0)
    cube.keyframe_insert("location", frame=3)
    cube.location = (-1.5, 0.0, 0.0)
    cube.keyframe_insert("location", frame=30)

    camera = scene.camera or scene.objects.get("Camera")
    if camera is None:
        camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        scene.collection.objects.link(camera)
        scene.camera = camera
    camera.location = (0.0, -9.0, 0.0)
    camera.rotation_euler = (1.5708, 0.0, 0.0)
    camera.keyframe_insert("location", frame=1)
    camera.keyframe_insert("rotation_euler", frame=1)
    camera.location = (0.0, -9.0, 0.6)
    camera.rotation_euler = (1.5708, 0.0, 0.08)
    camera.keyframe_insert("location", frame=30)
    camera.keyframe_insert("rotation_euler", frame=30)

    objects = {"cube": cube, "camera": camera}
    if not with_extras:
        scene.frame_set(2)
        return objects

    gray = _emission_material("StressGray", (0.4, 0.4, 0.4))

    wave = bpy.data.objects.new("StressWave", _grid_mesh("StressWaveMesh", 2.0, 30))
    scene.collection.objects.link(wave)
    wave.location = (0.0, 2.0, -2.2)
    wave.rotation_euler = (1.2, 0.0, 0.0)
    wave.data.materials.append(gray)
    modifier = wave.modifiers.new("Wave", "WAVE")
    modifier.height = 0.3
    modifier.speed = 0.2
    wave.cycles.motion_steps = 3
    objects["wave"] = wave

    hair = bpy.data.objects.new("StressHair", _grid_mesh("StressHairMesh", 1.5, 8))
    scene.collection.objects.link(hair)
    hair.location = (-3.0, 2.0, 1.6)
    hair.data.materials.append(gray)
    hair.modifiers.new("Hair", "PARTICLE_SYSTEM")
    settings = hair.particle_systems[-1].settings
    settings.type = "HAIR"
    settings.count = 400
    settings.hair_length = 0.4
    hair.location.x = -3.0
    hair.keyframe_insert("location", frame=1)
    hair.location.x = -2.0
    hair.keyframe_insert("location", frame=30)
    objects["hair"] = hair

    points = bpy.data.objects.new("StressPoints", _grid_mesh("StressPointsMesh", 1.5, 1))
    scene.collection.objects.link(points)
    points.location = (2.6, 2.0, 1.6)
    points.rotation_euler = (1.5708, 0.0, 0.0)
    points.data.materials.append(gray)
    nodes = points.modifiers.new("Points", "NODES")
    nodes.node_group = _points_node_group()
    objects["points"] = points

    scene.frame_set(2)
    return objects


def use_device(kind):
    """Switch Cycles to "CPU" or "METAL". Returns False if unavailable."""
    scene = bpy.context.scene
    if kind == "CPU":
        scene.cycles.device = "CPU"
        return True
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = kind
    except TypeError:
        return False
    prefs.refresh_devices()
    found = False
    for device in prefs.devices:
        device.use = device.type == kind
        found = found or device.type == kind
    if not found:
        return False
    scene.cycles.device = "GPU"
    return True
