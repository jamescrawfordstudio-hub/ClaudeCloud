# Cycles After Hours: Viewport Motion Blur for Mac

A macOS (Apple Silicon) build of [Cycles After Hours](https://github.com/BramGunst/cycles-after-hours)
Viewport Motion Blur v0.2.1 by Bram Gunst, which upstream only ships for Windows.

Cycles After Hours is not an add-on. It is a modified Blender 5.2.2 LTS that
renders true Cycles motion blur in the Rendered Viewport. A Mac version
therefore means compiling Blender itself on macOS with the same patches. The
patches only touch cross-platform Cycles and Blender code (nothing is
Windows-specific), so they build unchanged on macOS.

## Get the Mac build

The GitHub Actions workflow [`build-macos.yml`](../.github/workflows/build-macos.yml)
compiles Blender on a GitHub-hosted Apple Silicon Mac and publishes a `.dmg`.

1. Open the repository's **Actions** tab and pick the latest green
   **Build Blender Viewport Motion Blur for macOS** run.
2. Download the artifact at the bottom of the run page (you must be signed
   in to GitHub). Unzip it to get the `.dmg`.
3. Open the `.dmg`, drag **Blender Viewport Motion Blur** to Applications,
   and follow `READ ME FIRST.txt`. The app is not notarized by Apple, so the
   first launch needs **System Settings > Privacy & Security > Open Anyway**
   (or `xattr -dr com.apple.quarantine "/Applications/Blender Viewport Motion Blur.app"`).

Then pick Cycles, enable **Render Properties > Motion Blur > Viewport Motion
Blur**, and switch the viewport to Rendered. Use Metal under **Preferences >
System** for GPU rendering.

Requirements: an Apple Silicon Mac (M1 or newer) on macOS 11.2 or later.
Blender 5 no longer supports Intel Macs.

## Build it yourself

On an Apple Silicon Mac with about 35 GB free:

```sh
xcode-select --install                  # Apple's compilers
brew install cmake git-lfs ninja ccache # build tools (https://brew.sh)
git clone https://github.com/jamescrawfordstudio-hub/ClaudeCloud.git
cd ClaudeCloud/cycles-after-hours-mac
./scripts/build-macos.sh
```

The script:

1. downloads Blender `v5.2.2` (`d13f752e3b9c`, the base upstream uses),
2. applies the five patches in [`patches/`](patches) with `git am`,
3. downloads Blender's precompiled macOS arm64 libraries (`make update`),
4. builds with Blender's release configuration (Metal enabled),
5. ad-hoc signs the app, runs a smoke test, and writes
   `dist/Cycles-After-Hours_Blender-5.2.2_Viewport-Motion-Blur-v0.2.1-macOS-arm64.dmg`.

Expect 30 to 60 minutes on an M-series Mac. Re-running the script reuses the
download and the existing build.

## Patches

The patches are copied unmodified from
[BramGunst/cycles-after-hours](https://github.com/BramGunst/cycles-after-hours)
at commit `e3df704eea78`. See its [SOURCE.md](https://github.com/BramGunst/cycles-after-hours/blob/main/SOURCE.md)
for what each one does.

| Version | Patch | SHA-256 |
| --- | --- | --- |
| v0.1.0 | `0001-Add-true-Cycles-motion-blur-to-rendered-viewport.patch` | `0a8846da…e9d8` |
| v0.1.1 | `0002-Fix-viewport-motion-corruption-when-changing-Motion-.patch` | `32dd44fe…4c0f` |
| v0.2.0 | `0003-Fix-point-motion-BVH-rebuild-on-viewport-blur-toggle.patch` | `6bed32a5…5f49` |
| v0.2.0 | `0004-Add-live-unkeyed-transform-preview-for-viewport-motion-blur.patch` | `effd23ce…fee7` |
| v0.2.1 | `0005-Fix-initial-viewport-motion-blur-overlay-crash.patch` | `9fae2b5f…6b34` |

## Caveats

- Unofficial, and not affiliated with the Blender Foundation or the patch author.
- Upstream tested the patches on Windows with CPU, CUDA and OptiX. The Mac
  build runs the same Cycles code on CPU and Metal, but Metal has not been
  tested by the patch author. Report Mac-specific problems here rather than upstream.
- The app shares preferences and add-ons with any other Blender 5.2 install.

## License

Blender is distributed under GPL-3.0-or-later. The patches keep their
per-file `GPL-2.0-or-later` (Blender core) and `Apache-2.0` (Cycles) headers.
The corresponding source for the Mac build is upstream Blender `v5.2.2` plus
the patches and build script in this folder.
