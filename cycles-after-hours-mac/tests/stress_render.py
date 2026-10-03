# Final-render (F12) stress test and file round trip, run in the background:
#
#   Blender -b --factory-startup --python stress_render.py -- render OUT_DIR LABEL DEVICE
#       Renders frames with heavy motion blur settings and saves LABEL.blend.
#   Blender -b FILE.blend --python stress_render.py -- inspect OUT_DIR LABEL
#       Opens a file saved by another build, reports the viewport motion blur
#       setting, renders one frame and saves it again as LABEL.blend.
#   Blender -b --factory-startup --python stress_render.py -- compare A.png B.png
#       Prints how different two renders are.

import json
import os
import sys
import time

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stress_scene  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:]
MODE = ARGS[0]


def rss_mb():
    try:
        return int(os.popen(f"ps -o rss= -p {os.getpid()}").read().strip()) // 1024
    except ValueError:
        return -1


def load_pixels(path):
    image = bpy.data.images.load(path, check_existing=False)
    pixels = np.empty(image.size[0] * image.size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels


def report(tag, data):
    print(f"{tag} {json.dumps(data)}", flush=True)


if MODE == "render":
    out, label, device = ARGS[1], ARGS[2], ARGS[3]
    os.makedirs(out, exist_ok=True)
    scene = bpy.context.scene
    objects = stress_scene.build_scene(with_extras=True)
    used = device if stress_scene.use_device(device) else "CPU"
    if used == "CPU":
        stress_scene.use_device("CPU")
    patched = hasattr(scene.cycles, "use_viewport_motion_blur")
    if patched:
        scene.cycles.use_viewport_motion_blur = True
    scene.render.resolution_x = 320
    scene.render.resolution_y = 240
    for obj in (objects["cube"], objects["wave"], objects["points"]):
        obj.cycles.motion_steps = 7
    results = []
    for frame in (2, 5, 9, 14, 20, 27):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out, f"{label}-f{frame:02d}.png")
        start = time.time()
        bpy.ops.render.render(write_still=True)
        pixels = load_pixels(scene.render.filepath)
        results.append({
            "frame": frame,
            "seconds": round(time.time() - start, 2),
            "mean": round(float(pixels.reshape(-1, 4)[:, :3].mean()), 4),
            "rss_mb": rss_mb(),
        })
    # The motion blur check: frame 2 of the cube with and without blur.
    objects["wave"].hide_render = objects["hair"].hide_render = objects["points"].hide_render = True
    scene.frame_set(2)
    blur = {}
    for enabled in (False, True):
        scene.render.use_motion_blur = enabled
        scene.render.filepath = os.path.join(out, f"{label}-blur{int(enabled)}.png")
        bpy.ops.render.render(write_still=True)
        lum = load_pixels(scene.render.filepath).reshape(-1, 4)[:, :3].mean(axis=1)
        blur["on" if enabled else "off"] = round(float(((lum > 0.15) & (lum < 0.85)).mean()), 4)
    scene.render.use_motion_blur = True
    objects["wave"].hide_render = objects["hair"].hide_render = objects["points"].hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, f"{label}.blend"))
    report("RENDER", {"label": label, "device": used, "patched": patched,
                      "frames": results, "blur_fraction": blur, "peak_rss_mb": max(r["rss_mb"] for r in results)})

elif MODE == "inspect":
    out, label = ARGS[1], ARGS[2]
    opened = bpy.data.filepath
    scene = bpy.context.scene
    patched = hasattr(scene.cycles, "use_viewport_motion_blur")
    stored = scene.get("cycles", {}).get("use_viewport_motion_blur") if scene.get("cycles") else None
    value = scene.cycles.use_viewport_motion_blur if patched else None
    scene.render.resolution_x = 160
    scene.render.resolution_y = 120
    stress_scene.use_device("CPU")
    scene.render.filepath = os.path.join(out, f"{label}-inspect.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, f"{label}.blend"))
    report("INSPECT", {"label": label, "opened": os.path.basename(opened), "patched_build": patched,
                       "setting_via_ui": value, "setting_stored_in_file": stored,
                       "objects": len(bpy.data.objects), "rendered": os.path.getsize(scene.render.filepath) > 0})

elif MODE == "compare":
    a, b = load_pixels(ARGS[1]), load_pixels(ARGS[2])
    if a.shape != b.shape:
        report("COMPARE", {"a": ARGS[1], "b": ARGS[2], "error": "different sizes"})
    else:
        diff = np.abs(a - b)
        report("COMPARE", {"a": os.path.basename(ARGS[1]), "b": os.path.basename(ARGS[2]),
                           "mean_abs_diff": round(float(diff.mean()), 5),
                           "max_abs_diff": round(float(diff.max()), 4),
                           "pixels_differing_over_2pct": round(float((diff.reshape(-1, 4)[:, :3].max(axis=1) > 0.02).mean()), 5)})

else:
    raise SystemExit(f"unknown mode {MODE}")
