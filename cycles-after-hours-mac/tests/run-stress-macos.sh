#!/usr/bin/env bash
#
# Stress test the Mac build next to official Blender. Used by
# .github/workflows/stress-test-macos.yml; runs Blender with --factory-startup
# so your own preferences are neither read nor saved.
#
# Usage: run-stress-macos.sh PATCHED_APP OFFICIAL_APP OUT_DIR [VIEWPORT_SECONDS]

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHED="$1"
OFFICIAL="$2"
OUT="$3"
SECONDS_PER_RUN="${4:-600}"
RESULTS="$OUT/results.txt"
mkdir -p "$OUT"

note() { echo "$*" | tee -a "$RESULTS"; }

# Runs one GUI viewport stress session and records how Blender exited.
# Exit code 0 means it quit normally; 134/139 mean a crash; HUNG means it had
# to be killed. Allows extra time for the first Metal kernel compile.
run_viewport() {
  local app="$1" label="$2" device="$3" secs="$4"
  local limit=$((secs + 1500)) waited=0 pid code
  "$app/Contents/MacOS/Blender" --factory-startup --python "$HERE/stress_viewport.py" \
    -- "$OUT" "$label" "$device" "$secs" >"$OUT/$label-stdout.txt" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    waited=$((waited + 5))
    if ((waited > limit)); then
      kill -9 "$pid" 2>/dev/null
      note "$label: HUNG, killed after ${limit}s"
      break
    fi
  done
  wait "$pid"
  code=$?
  note "$label: exit code $code"
  if [[ -f "$OUT/$label-summary.json" ]]; then
    python3 - "$OUT/$label-summary.json" <<'EOF' | tee -a "$RESULTS"
import json, sys
s = json.load(open(sys.argv[1]))
checks = s.get("checks", {})
print(f"  {s['label']}: blender {s['blender']} patched={s['patched']} device={s.get('device_used')} "
      f"finished={s['finished']} actions={s['actions']} errors={len(s['action_errors'])} "
      f"max_ui_gap={s['max_timer_gap_s']}s rss start/peak/end={s.get('rss_start_mb')}/{s.get('rss_peak_mb')}/{s.get('rss_end_mb')} MB")
print(f"  viewport motion blur: {checks.get('viewport_blur', 'n/a')}  off={checks.get('blur_off')}  on={checks.get('blur_on')}")
print(f"  final check: {checks.get('final')}")
for e in s["action_errors"][:10]:
    print(f"  error: {e}")
EOF
  else
    note "  $label: no summary written"
    tail -n 30 "$OUT/$label-stdout.txt" | sed 's/^/  | /' | tee -a "$RESULTS"
  fi
}

# Runs one background Blender command and keeps its result lines.
run_background() {
  local label="$1"
  shift
  "$@" >"$OUT/$label-stdout.txt" 2>&1
  local code=$?
  note "$label: exit code $code"
  grep -E '^(RENDER|INSPECT|COMPARE) ' "$OUT/$label-stdout.txt" | sed 's/^/  /' | tee -a "$RESULTS"
}

note "== Viewport stress: Mac build, CPU"
run_viewport "$PATCHED" patched-cpu CPU "$SECONDS_PER_RUN"
note "== Viewport stress: Mac build, Metal GPU"
run_viewport "$PATCHED" patched-metal METAL "$SECONDS_PER_RUN"
note "== Viewport baseline: official Blender, CPU"
run_viewport "$OFFICIAL" official-cpu CPU $((SECONDS_PER_RUN / 2))
note "== Both apps at once, both on Metal"
run_viewport "$OFFICIAL" together-official METAL $((SECONDS_PER_RUN / 2)) &
sleep 20
run_viewport "$PATCHED" together-patched METAL $((SECONDS_PER_RUN / 2)) &
wait

P="$PATCHED/Contents/MacOS/Blender"
O="$OFFICIAL/Contents/MacOS/Blender"
R="$HERE/stress_render.py"
note "== Final renders (F12) with heavy motion blur"
run_background render-patched-cpu "$P" -b --factory-startup --python "$R" -- render "$OUT" patched-cpu CPU
run_background render-official-cpu "$O" -b --factory-startup --python "$R" -- render "$OUT" official-cpu CPU
run_background render-patched-metal "$P" -b --factory-startup --python "$R" -- render "$OUT" patched-metal METAL
run_background render-official-metal "$O" -b --factory-startup --python "$R" -- render "$OUT" official-metal METAL

note "== Are final renders unchanged by the patches? (Mac build vs official, same scene)"
for device in cpu metal; do
  for frame in 02 09 20; do
    run_background "compare-$device-f$frame" "$O" -b --factory-startup --python "$R" -- compare \
      "$OUT/patched-$device-f$frame.png" "$OUT/official-$device-f$frame.png"
  done
done

note "== .blend round trip: Mac build -> official -> Mac build"
run_background roundtrip-official "$O" -b "$OUT/patched-cpu.blend" --python "$R" -- inspect "$OUT" roundtrip-official
run_background roundtrip-patched "$P" -b "$OUT/roundtrip-official.blend" --python "$R" -- inspect "$OUT" roundtrip-patched
