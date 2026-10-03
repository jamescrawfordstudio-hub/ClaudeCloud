#!/usr/bin/env bash
#
# Build Blender 5.2.2 LTS with the Cycles After Hours "Viewport Motion Blur"
# patches (v0.2.1) for Apple Silicon Macs, and package it as a .dmg.
#
# Requirements: macOS on Apple Silicon, Xcode 16+ or its Command Line Tools,
# and `brew install cmake git-lfs ninja` (ccache is optional).
#
# Environment overrides:
#   WORK_DIR      sources and build files (default: ../work, needs ~35 GB)
#   DIST_DIR      where the finished .dmg goes (default: ../dist)
#   NPROCS        parallel compile jobs (default: all cores)
#   BLENDER_REPO  Blender Git URL (default: projects.blender.org)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$HERE")"

BLENDER_REPO="${BLENDER_REPO:-https://projects.blender.org/blender/blender.git}"
BLENDER_TAG="v5.2.2"
BLENDER_COMMIT="d13f752e3b9c4f8c261cda552b1021f8bcc0382c"
FEATURE_VERSION="0.2.1"
LAST_PATCH_SUBJECT="Fix initial viewport motion blur overlay crash"

WORK_DIR="${WORK_DIR:-$PROJECT/work}"
DIST_DIR="${DIST_DIR:-$PROJECT/dist}"
NPROCS="${NPROCS:-$(sysctl -n hw.ncpu)}"

SRC="$WORK_DIR/blender"
BUILD="$WORK_DIR/build"
STAGE="$WORK_DIR/package"
APP_NAME="Blender Viewport Motion Blur"
PACKAGE_NAME="Cycles-After-Hours_Blender-5.2.2_Viewport-Motion-Blur-v${FEATURE_VERSION}-macOS-arm64"

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

check_requirements() {
  step "Checking requirements"
  [[ "$(uname -s)" == "Darwin" ]] || die "this script must be run on macOS"
  [[ "$(uname -m)" == "arm64" ]] || die "Blender 5.x only supports Apple Silicon (arm64) Macs"
  xcode-select -p >/dev/null 2>&1 || die "install the Xcode Command Line Tools first: xcode-select --install"
  command -v cmake >/dev/null || die "cmake not found: brew install cmake"
  command -v python3 >/dev/null || die "python3 not found: xcode-select --install"
  git lfs version >/dev/null 2>&1 || die "git-lfs not found: brew install git-lfs"
  command -v ninja >/dev/null || echo "note: ninja not found, falling back to make (brew install ninja is faster)"
  echo "Using $NPROCS parallel jobs, work dir: $WORK_DIR"
}

fetch_source() {
  if [[ ! -d "$SRC/.git" ]]; then
    step "Downloading Blender $BLENDER_TAG source"
    mkdir -p "$WORK_DIR"
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "$BLENDER_TAG" "$BLENDER_REPO" "$SRC"
  fi
  # The ~800 MB of regression test files are not needed to build Blender.
  git -C "$SRC" config lfs.fetchexclude "tests/**"
}

apply_patches() {
  # No `grep -q`: exiting early would SIGPIPE `git log` and fail under pipefail.
  if git -C "$SRC" log --format=%s -n 10 | grep -xF "$LAST_PATCH_SUBJECT" >/dev/null; then
    echo "Viewport Motion Blur patches already applied"
    return
  fi
  [[ "$(git -C "$SRC" rev-parse HEAD)" == "$BLENDER_COMMIT" ]] ||
    die "$SRC is not at Blender $BLENDER_TAG ($BLENDER_COMMIT); delete it and run again"

  step "Applying Viewport Motion Blur v$FEATURE_VERSION patches"
  if ! git -C "$SRC" -c user.name="Cycles After Hours build" -c user.email="build@localhost" \
    am "$PROJECT"/patches/*.patch; then
    git -C "$SRC" am --abort || true
    die "a patch did not apply cleanly"
  fi
}

fetch_libraries() {
  step "Downloading precompiled macOS libraries (several GB, first run only)"
  (cd "$SRC" && python3 build_files/utils/make_update.py --no-blender)

  step "Downloading Blender's Git LFS files (icons, brushes, node assets)"
  git -C "$SRC" lfs pull
}

build_blender() {
  step "Configuring Blender"
  local args=(
    -S "$SRC" -B "$BUILD"
    -C "$SRC/build_files/cmake/config/blender_release.cmake"
    -DCMAKE_BUILD_TYPE=Release
  )
  if command -v ninja >/dev/null; then
    args+=(-G Ninja)
  fi
  if command -v ccache >/dev/null; then
    args+=(-DWITH_COMPILER_CCACHE=ON)
  fi
  cmake "${args[@]}"

  step "Compiling Blender with $NPROCS jobs (this takes a while)"
  cmake --build "$BUILD" --target install --parallel "$NPROCS"
}

# Apple Silicon refuses to run code with a missing or broken signature. Re-sign
# any Mach-O file the install step invalidated, then ad-hoc sign the bundle.
# Files that are already validly signed (e.g. the Quick Look thumbnailer and its
# entitlements) are left untouched.
sign_app() {
  local app="$1" file
  step "Ad-hoc code signing $app"
  while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q 'Mach-O' && ! codesign --verify "$file" >/dev/null 2>&1; then
      codesign --force --sign - "$file"
    fi
  done < <(find "$app/Contents" -type f \( -perm -0100 -o -name '*.dylib' -o -name '*.so' \) -print0)
  codesign --force --sign - --preserve-metadata=entitlements "$app"
  codesign --verify --deep --strict --verbose=2 "$app" || die "code signature of $app is invalid"
}

# Runs a copy, because Blender writes Python __pycache__ files into its own
# bundle, which would break the signature of the app that gets shipped.
smoke_test() {
  local app="$1" copy="$WORK_DIR/smoke-test/$APP_NAME.app"
  step "Smoke testing a copy of the packaged app"
  rm -rf "$WORK_DIR/smoke-test"
  mkdir -p "$WORK_DIR/smoke-test"
  ditto "$app" "$copy"
  "$copy/Contents/MacOS/Blender" --background --factory-startup --python-exit-code 1 \
    --python "$HERE/smoke_test.py"
  rm -rf "$WORK_DIR/smoke-test"
}

# Checks the app exactly as users will get it: inside the finished DMG.
verify_dmg() {
  local dmg="$1" mount
  step "Verifying the code signature inside the DMG"
  mount="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$dmg" >/dev/null
  if ! codesign --verify --deep --strict --verbose=2 "$mount/$APP_NAME.app"; then
    hdiutil detach "$mount" >/dev/null || true
    die "the app inside $dmg has an invalid code signature"
  fi
  hdiutil detach "$mount" >/dev/null
}

package() {
  local built="$BUILD/bin/Blender.app"
  local app="$STAGE/$APP_NAME.app"
  local dmg="$DIST_DIR/$PACKAGE_NAME.dmg"
  [[ -d "$built" ]] || die "build finished but $built is missing"

  step "Packaging"
  rm -rf "$STAGE"
  mkdir -p "$STAGE" "$DIST_DIR"
  ditto "$built" "$app"
  sign_app "$app"
  smoke_test "$app"
  ln -s /Applications "$STAGE/Applications"
  cp "$PROJECT/READ ME FIRST.txt" "$STAGE/"

  rm -f "$dmg"
  # hdiutil sometimes fails with "Resource busy" on CI machines, so retry.
  local attempt
  for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$dmg"; then
      break
    fi
    if [[ "$attempt" == 5 ]]; then
      die "hdiutil could not create $dmg"
    fi
    sleep $((attempt * 5))
  done
  verify_dmg "$dmg"
  (cd "$DIST_DIR" && shasum -a 256 "$PACKAGE_NAME.dmg" | tee "$PACKAGE_NAME.dmg.sha256")
  step "Done: $dmg"
}

check_requirements
fetch_source
apply_patches
fetch_libraries
build_blender
package
