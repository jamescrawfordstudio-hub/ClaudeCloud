# Handoff: status as of 2026-10-03

Everything is on branch `claude/dazzling-ptolemy-0t253h` of
github.com/jamescrawfordstudio-hub/ClaudeCloud. GitHub Actions runs are free on this
public repo, so you can re-run any of them from the Actions tab.

## Ready to use

- **Mac build, Blender 5.2.2 + Viewport Motion Blur v0.2.1 (Apple Silicon):**
  latest green run of *Build Blender Viewport Motion Blur for macOS*, artifact
  `...Blender-5.2.2...macOS-arm64`. Known good: run 37129132092.
- **Do not use the first download (run 37100531801).** Its app signature was broken
  (Python cache files written after signing), which can make macOS say the app is
  "damaged". Fixed in `scripts/build-macos.sh`, which now refuses to package a broken
  signature.

## What was verified

- **Running alongside official Blender:** works. On a real macOS 15.7.9 Mac, both
  apps ran at the same time (run 37129131677).
- **Shared settings:** both use `~/Library/Application Support/Blender/5.2`.
  Preferences: whichever app quits last with changed settings wins. If both open the
  same .blend, the last save wins (the other version survives as `.blend1`). Your
  files are not corrupted.
- **Optional separation:** creating `<App>.app/Contents/Resources/portable` makes the
  Mac build keep its own settings (tested, official Blender unaffected). It writes
  inside the app bundle. A cleaner fix is a one-line source patch renaming the
  settings folder in `intern/ghost/intern/GHOST_SystemPathsCocoa.mm` (not done yet).
- **Patch code safety review (partial, agents stopped early):** no file, network,
  subprocess or OS calls added anywhere. Scene frame, original data and user counts
  are preserved. Low-severity findings only:
  1. Uncached Geometry Nodes simulations can reset in the viewport while viewport
     blur is on.
  2. Unbaked physics caches (cloth, particles, fluid replay) may lose a frame and
     need re-simulating.
  3. Unkeyed pose/shape-key/material edits snap back in the Rendered viewport until
     keyed (saved data is fine).

## Add-on version: not possible as a true add-on

Research (verified against the Blender source) found:

- **Pure Python:** official Cycles hard-disables motion blur in every viewport
  session, and no Python setting, flag or `_cycles` call can change that.
- **Compiled add-on:**
  - Binary patching is unsafe and breaks on every Blender release.
  - Windows `blender.exe` exports none of the needed functions.
  - Hydra passes no motion data.
- **Patches change Blender core:** 3 of the 5 patches modify Blender itself
  (depsgraph, animation, viewport drawing), not just Cycles.

The only add-on that can work is a *preview* add-on: it renders the camera view with
real Cycles in a background Blender process and overlays the image on the viewport.
That takes 0.6 to 7 seconds per update for moderate scenes and works only in camera
view. It is not the same as the patched build, and it was not built.

## Blender 5.3

- `patches-5.3/` holds the five patches ported to Blender 5.3 alpha
  (main @ 3a8dfe8e). See `patches-5.3/README.md` for the three small changes.
- Every Blender API the patches use still exists in 5.3. The first 5.3 build failed
  only on a renamed header, now fixed. The rebuild was **still running when work
  stopped** (run 37131538454). Check it in the Actions tab.
- When 5.3 is released, change `BLENDER_COMMIT` for `TARGET=5.3` in
  `scripts/build-macos.sh` to the release tag's commit and re-run the build workflow.
  If a patch fails to apply, rebase `patches-5.3` the same way.

## Still running or unchecked when work stopped

| Run | What | Look for |
| --- | --- | --- |
| 37131538454 | 5.2.2 + 5.3 builds | Did the 5.3 job go green? |
| 37130307702 / 37130309652 | Stress test (60 s and 600 s per session) | "Results" step and `stress-test-results` artifact: exit codes, "viewport motion blur: visible", RSS, "No writes outside the expected places" |
| 37131576945 | Side-by-side on macOS 26 | "Blender processes running: 2 of 2"? If 1 of 2, use `open -n` to start the second app. |

## Files

- `scripts/build-macos.sh`: build script (`TARGET=5.2.2` or `TARGET=5.3`), runs
  locally on an Apple Silicon Mac too.
- `tests/`: stress test (viewport, renders, file round trip, system audit).
- `../.github/workflows/`: `build-macos.yml`, `stress-test-macos.yml`,
  `test-side-by-side.yml`.
