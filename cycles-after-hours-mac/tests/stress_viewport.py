# Stress test for the real Rendered viewport. Run Blender with a window:
#
#   Blender --factory-startup --python stress_viewport.py -- OUT_DIR LABEL DEVICE SECONDS
#
# DEVICE is CPU or METAL. The script builds the stress scene, switches a 3D
# viewport to Rendered camera view, checks that viewport motion blur is
# visible, then hammers every setting the patches touch on a timer for
# SECONDS while logging memory and UI responsiveness. It writes
# OUT_DIR/LABEL-summary.json and quits Blender when done.

import json
import os
import sys
import time
import traceback

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stress_scene  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT, LABEL, DEVICE, SECONDS = ARGS[0], ARGS[1], ARGS[2], float(ARGS[3])
os.makedirs(OUT, exist_ok=True)

T0 = time.time()
LOG = open(os.path.join(OUT, f"{LABEL}-log.txt"), "w", buffering=1)
SUMMARY = {
    "label": LABEL,
    "device_requested": DEVICE,
    "blender": bpy.app.version_string,
    "patched": False,
    "actions": 0,
    "action_errors": [],
    "max_timer_gap_s": 0.0,
    "rss_mb": [],
    "checks": {},
    "finished": False,
}

# The splash would cover the viewport in screenshots. This runs before
# Blender decides whether to show it.
bpy.context.preferences.view.show_splash = False


def log(message):
    line = f"[{time.time() - T0:7.1f}s] {message}"
    print(f"STRESS {LABEL} {line}", flush=True)
    LOG.write(line + "\n")


def rss_mb():
    try:
        return int(os.popen(f"ps -o rss= -p {os.getpid()}").read().strip()) // 1024
    except ValueError:
        return -1


def view3d():
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type == "VIEW_3D":
                region = next(r for r in area.regions if r.type == "WINDOW")
                return window, area, region, area.spaces.active
    return None


def capture(name):
    """Screenshot the 3D viewport and measure the centre of the image."""
    window, area, region, _space = view3d()
    path = os.path.join(OUT, f"{LABEL}-{name}.png")
    with bpy.context.temp_override(window=window, area=area, region=region):
        bpy.ops.screen.screenshot_area(filepath=path)
    image = bpy.data.images.load(path, check_existing=False)
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    lum = pixels.reshape(height, width, 4)[:, :, :3].mean(axis=2)
    centre = lum[height // 4: 3 * height // 4, width // 4: 3 * width // 4]
    return {
        "mid": float(((centre > 0.15) & (centre < 0.85)).mean()),
        "bright": float((centre >= 0.85).mean()),
        "any": float((centre > 0.05).mean()),
    }


def setup_viewport():
    window, area, region, space = view3d()
    space.shading.type = "RENDERED"
    space.region_3d.view_perspective = "CAMERA"
    space.overlay.show_overlays = False
    space.show_gizmo = False
    space.show_region_header = False
    space.show_region_toolbar = False
    space.show_region_ui = False
    space.show_region_tool_header = False
    with bpy.context.temp_override(window=window, area=area, region=region):
        bpy.ops.view3d.view_center_camera()


def redraw():
    found = view3d()
    if found:
        found[1].tag_redraw()


# ---------------------------------------------------------------------------
# Setup

scene = bpy.context.scene
OBJECTS = stress_scene.build_scene(with_extras=True)
SUMMARY["patched"] = hasattr(scene.cycles, "use_viewport_motion_blur")
device_ok = stress_scene.use_device(DEVICE)
SUMMARY["device_used"] = DEVICE if device_ok else "CPU"
if not device_ok:
    stress_scene.use_device("CPU")
log(f"Blender {bpy.app.version_string}, patched={SUMMARY['patched']}, device={SUMMARY['device_used']}")
EXTRAS = [OBJECTS[k] for k in ("wave", "hair", "points")]


def set_extras_visible(visible):
    for obj in EXTRAS:
        obj.hide_viewport = not visible
        obj.hide_render = not visible


def set_viewport_blur(enabled):
    if SUMMARY["patched"]:
        scene.cycles.use_viewport_motion_blur = enabled


set_extras_visible(False)
set_viewport_blur(False)


# ---------------------------------------------------------------------------
# Phase 1: wait for the viewport to render, then compare blur off vs on.

class State:
    phase = "start"
    phase_started = time.time()
    last_tick = None
    previous = None
    stable = 0
    action_index = 0
    next_capture = 0.0
    reenter_rendered = False


def wait_until_converged(timeout):
    """Returns a metric dict once two consecutive captures agree, None while
    still waiting, or raises on timeout."""
    metrics = capture("probe")
    previous = State.previous
    State.previous = metrics
    if metrics["any"] < 0.002:
        State.stable = 0
    elif previous and abs(metrics["mid"] - previous["mid"]) < 0.01 and \
            abs(metrics["bright"] - previous["bright"]) < 0.01:
        State.stable += 1
    else:
        State.stable = 0
    if State.stable >= 2:
        State.previous = None
        State.stable = 0
        return metrics
    if time.time() - State.phase_started > timeout:
        raise TimeoutError(f"viewport did not settle within {timeout}s (last {metrics})")
    return None


def enter(phase):
    State.phase = phase
    State.phase_started = time.time()
    State.previous = None
    State.stable = 0
    log(f"phase: {phase}")


# ---------------------------------------------------------------------------
# Phase 2: actions. Each one touches a code path the patches changed.

FRAMES = [2, 5, 9, 14, 20, 27, 3, 11]
SHUTTERS = [0.25, 0.5, 1.0, 2.0]
POSITIONS = ["START", "CENTER", "END"]


def act_toggle_blur(i):
    set_viewport_blur(not scene.cycles.use_viewport_motion_blur if SUMMARY["patched"] else True)


def act_frame(i):
    scene.frame_set(FRAMES[i % len(FRAMES)])


def act_shutter(i):
    scene.render.motion_blur_shutter = SHUTTERS[i % len(SHUTTERS)]


def act_position(i):
    scene.render.motion_blur_position = POSITIONS[i % len(POSITIONS)]


def act_motion_steps(i):
    for obj in (OBJECTS["cube"], OBJECTS["wave"], OBJECTS["points"]):
        obj.cycles.motion_steps = 1 + (i % 7)


def act_object_blur_flags(i):
    obj = OBJECTS["wave"]
    obj.cycles.use_motion_blur = (i % 3) != 0
    obj.cycles.use_deform_motion = (i % 2) == 0


def act_rolling_shutter(i):
    scene.cycles.rolling_shutter_type = "TOP" if scene.cycles.rolling_shutter_type == "NONE" else "NONE"


def act_unkeyed_move(i):
    # Live transform preview path: change an animated object on a frame
    # without inserting a key.
    OBJECTS["cube"].location.x += 0.4 if i % 2 else -0.4
    OBJECTS["cube"].rotation_euler.z += 0.3


def act_camera_unkeyed(i):
    OBJECTS["camera"].location.z += 0.05 if i % 2 else -0.05


def act_keyframe_roundtrip(i):
    cube = OBJECTS["cube"]
    frame = scene.frame_current
    cube.keyframe_insert("location", frame=frame)
    cube.keyframe_delete("location", frame=frame)


def act_shading_cycle(i):
    # Leave Rendered now and re-enter it on the next tick, with motion blur on
    # (the v0.2.1 crash fix path). It needs a redraw in between to really exit.
    view3d()[3].shading.type = "SOLID"
    State.reenter_rendered = True


def act_view_cycle(i):
    rv3d = view3d()[3].region_3d
    rv3d.view_perspective = "PERSP" if rv3d.view_perspective == "CAMERA" else "CAMERA"


def act_denoise(i):
    scene.cycles.use_preview_denoising = not scene.cycles.use_preview_denoising


def act_extras(i):
    set_extras_visible(i % 4 != 3)


def act_samples(i):
    scene.cycles.preview_samples = [4, 16, 64][i % 3]


ACTIONS = [
    act_toggle_blur, act_frame, act_shutter, act_unkeyed_move, act_position,
    act_motion_steps, act_frame, act_camera_unkeyed, act_object_blur_flags,
    act_rolling_shutter, act_keyframe_roundtrip, act_shading_cycle, act_frame,
    act_view_cycle, act_denoise, act_extras, act_samples, act_toggle_blur,
]


def finish():
    SUMMARY["finished"] = True
    SUMMARY["elapsed_s"] = round(time.time() - T0, 1)
    SUMMARY["rss_start_mb"] = SUMMARY["rss_mb"][0][1] if SUMMARY["rss_mb"] else None
    SUMMARY["rss_peak_mb"] = max((m for _t, m in SUMMARY["rss_mb"]), default=None)
    SUMMARY["rss_end_mb"] = SUMMARY["rss_mb"][-1][1] if SUMMARY["rss_mb"] else None
    with open(os.path.join(OUT, f"{LABEL}-summary.json"), "w") as f:
        json.dump(SUMMARY, f, indent=2)
    log("summary: " + json.dumps({k: v for k, v in SUMMARY.items() if k != "rss_mb"}))
    window = view3d()[0]
    with bpy.context.temp_override(window=window):
        bpy.ops.wm.quit_blender()


def tick():
    now = time.time()
    if State.last_tick is not None:
        SUMMARY["max_timer_gap_s"] = max(SUMMARY["max_timer_gap_s"], round(now - State.last_tick, 2))
    State.last_tick = now
    try:
        return step()
    except Exception as ex:  # Record and keep going; a crash would end the process.
        SUMMARY["action_errors"].append(f"{State.phase}: {ex!r}")
        log("error: " + traceback.format_exc())
        if State.phase.startswith("check"):
            SUMMARY["checks"]["viewport_blur"] = f"failed: {ex}"
            enter("stress")
        return 1.0


def step():
    if State.phase == "start":
        setup_viewport()
        SUMMARY["rss_mb"].append((0.0, rss_mb()))
        enter("check-blur-off")
        return 2.0

    if State.phase == "check-blur-off":
        # First Metal render compiles kernels, which can take minutes.
        metrics = wait_until_converged(timeout=900)
        if metrics is None:
            return 2.0
        SUMMARY["checks"]["blur_off"] = metrics
        log(f"viewport, blur off: {metrics}")
        if SUMMARY["patched"]:
            set_viewport_blur(True)
            enter("check-blur-on")
        else:
            enter("stress")
        return 2.0

    if State.phase == "check-blur-on":
        metrics = wait_until_converged(timeout=300)
        if metrics is None:
            return 2.0
        SUMMARY["checks"]["blur_on"] = metrics
        off = SUMMARY["checks"]["blur_off"]
        visible = metrics["mid"] > max(3 * off["mid"], 0.01)
        SUMMARY["checks"]["viewport_blur"] = "visible" if visible else "NOT visible"
        log(f"viewport, blur on: {metrics} -> motion blur {SUMMARY['checks']['viewport_blur']}")
        set_extras_visible(True)
        enter("stress")
        State.next_capture = time.time() + 30
        return 1.0

    if State.phase == "stress":
        if State.reenter_rendered:
            State.reenter_rendered = False
            view3d()[3].shading.type = "RENDERED"
            redraw()
            return 1.2
        elapsed = time.time() - State.phase_started
        if elapsed > SECONDS:
            # Back to a known state once; the viewport must still render.
            set_extras_visible(False)
            set_viewport_blur(True)
            scene.render.motion_blur_shutter = 1.0
            scene.render.motion_blur_position = "CENTER"
            scene.cycles.rolling_shutter_type = "NONE"
            scene.cycles.preview_samples = 16
            scene.cycles.use_preview_denoising = False
            scene.frame_set(2)
            space = view3d()[3]
            space.shading.type = "RENDERED"
            space.region_3d.view_perspective = "CAMERA"
            enter("final-check")
            return 3.0
        action = ACTIONS[State.action_index % len(ACTIONS)]
        action(State.action_index)
        State.action_index += 1
        SUMMARY["actions"] += 1
        redraw()
        if SUMMARY["actions"] % 10 == 0:
            SUMMARY["rss_mb"].append((round(time.time() - T0, 1), rss_mb()))
            log(f"{SUMMARY['actions']} actions, RSS {SUMMARY['rss_mb'][-1][1]} MB, "
                f"max timer gap {SUMMARY['max_timer_gap_s']}s")
        if time.time() > State.next_capture:
            State.next_capture = time.time() + 30
            SUMMARY.setdefault("periodic_captures", []).append(capture("periodic"))
        return 1.2

    if State.phase == "final-check":
        metrics = wait_until_converged(timeout=300)
        if metrics is None:
            return 2.0
        SUMMARY["checks"]["final"] = metrics
        SUMMARY["rss_mb"].append((round(time.time() - T0, 1), rss_mb()))
        finish()
        return None

    return None


bpy.app.timers.register(tick, first_interval=3.0, persistent=True)
log("timer registered")
