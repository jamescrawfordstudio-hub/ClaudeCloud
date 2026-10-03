# Run with: Blender --background --factory-startup --python-exit-code 1 --python smoke_test.py
#
# Checks that the build contains the Viewport Motion Blur patches and that
# Cycles can render a motion-blurred frame.

import os
import tempfile

import bpy

scene = bpy.context.scene

print("Blender", bpy.app.version_string, bpy.app.build_hash.decode(), bpy.app.build_platform.decode())

assert hasattr(scene.cycles, "use_viewport_motion_blur"), \
    "scene.cycles.use_viewport_motion_blur is missing: the patches were not built in"

# Informational only: CI machines may not expose a Metal GPU.
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.refresh_devices()
    print("Cycles devices:", [(d.name, d.type) for d in prefs.devices])
except Exception as ex:
    print("Could not list Cycles devices:", ex)

# Animate the default cube so there is something to blur.
cube = bpy.data.objects["Cube"]
cube.location = (-1.0, 0.0, 0.0)
cube.keyframe_insert("location", frame=1)
cube.location = (1.0, 0.0, 0.0)
cube.keyframe_insert("location", frame=2)
scene.frame_set(1)

scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 4
scene.cycles.use_denoising = False
scene.render.resolution_x = 64
scene.render.resolution_y = 64
scene.render.use_motion_blur = True
scene.cycles.use_viewport_motion_blur = True

output = os.path.join(tempfile.gettempdir(), "cycles_after_hours_smoke.png")
scene.render.filepath = output
bpy.ops.render.render(write_still=True)
assert os.path.getsize(output) > 0, "render produced no image"

print("Smoke test passed")
