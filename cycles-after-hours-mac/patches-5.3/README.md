# Viewport Motion Blur patches ported to Blender 5.3

These are the five upstream Cycles After Hours v0.2.1 patches (in `../patches`),
rebased onto Blender `main` at `3a8dfe8e58d9` (5.3 alpha; no 5.3 release branch
exists yet). Patches 0002 and 0003 applied unchanged. Three needed small fixes for
upstream changes in 5.3:

- **0001 and 0004, `intern/cycles/blender/object.cpp`:** Blender 5.3 removed
  `python_thread_state` from Cycles' Blender sync. Cycles now releases the Python
  GIL around each call with `Py_BEGIN_ALLOW_THREADS`, and code that runs Python
  during a frame change (drivers) takes the GIL itself with `PyGILState_Ensure`
  (`source/blender/python/intern/bpy_driver.cc`). Upstream 5.3 therefore calls
  `RE_engine_frame_set()` without restoring the thread state, and the port does
  the same around the patch's `frame_set()` helper and its cleanup block.
- **0005, `source/blender/draw/engines/external/external_engine.cc`:** 5.3 added
  `RE_WRITE_VIEWPORT_DEPTH` support and a header redraw when the viewport render
  engine is created. The port keeps both, and moves the header redraw into
  `init()` together with the engine creation that the patch moved there.

Generated with `git format-patch` from a branch where they apply in order with
`git am`. Build with `TARGET=5.3 ../scripts/build-macos.sh`.
