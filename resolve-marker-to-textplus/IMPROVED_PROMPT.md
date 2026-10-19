# Improved prompt (paste into your personal Claude session)

> **Status:** the full tool is now built: see `MarkerTitler.lua` and `README.md`. Use this prompt only for follow-up changes.

> **Attach with it:** (1) the Resolve `Developer/Scripting/README.txt` from your install (both 20.3 and 21 if you have them), (2) the Desktop report from `Marker Diagnostic (Phase 1).py` run on a test timeline, (3) the diagnostic script itself.

---

**Project: Resolve Clip Marker → Text+ for DaVinci Resolve Studio 20.3 and 21.x (macOS, Apple Silicon)**

Build a locally installed Python script for DaVinci Resolve Studio that turns **clip markers** (markers on timeline clips, read with `TimelineItem.GetMarkers()`) into **real Text+ title clips**. It must:
- run from `Workspace > Scripts`, installed in `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`
- work offline with no external dependencies beyond system Python 3
- support both **Resolve 20.3 and 21.x** from one file. Use feature detection, not version checks, wherever possible (e.g. use `Timeline.GetSelectedClips()` if it exists, which it does from 21.0.4). Python scripting requires Studio from 21.1.

I've attached Blackmagic's scripting README and a diagnostic report from my machine. **Treat the README and my report as the source of truth.** Don't use a method that isn't in the README unless the report's API probe shows it exists, and tell me when you're relying on something unverified.

**Marker types.** Use only `TimelineItem` clip markers. Ignore timeline (ruler) markers. Offer an *optional* checkbox to also include `MediaPoolItem` (source) markers that fall within the clip's used range. Interpret marker `frameId` using what my report showed: [FILL IN: relative to visible clip start / source media start].

**Behavior.**
- For every eligible marker on every clip on every video track (or only selected clips, if that option is on and the API supports it), create one Text+ title.
- The text is the marker name by default; options are name, note, or "name — note". Skip empty text and report it.
- The title spans **exactly** the clip's timeline range, `GetStart()` to `GetEnd()` [FILL IN: end exclusive yes/no from report], regardless of where the marker sits.
- Marker 1 is left-aligned on the left of frame, marker 2 is right-aligned on the right, then alternate. Markers are ordered by frameId.
- Each marker index gets its own track above the source clip's track, so the Nth title of any clip goes on track `base + N - 1`. Never place a title where it would overlap or overwrite any existing item. Add tracks with `AddTrack("video")` when needed. Refuse locked tracks.
- Never modify, move, or delete source clips, audio, or markers.

**Title creation: Phase 2 must test and pick a strategy, then explain the choice.** Candidates:
(a) `InsertFusionTitleIntoTimeline("Text+")` after moving the playhead. This is suspected to give no control over track or duration.
(b) A Fusion Composition / title media pool item placed with `MediaPool.AppendToTimeline([{mediaPoolItem, startFrame, endFrame, trackIndex, recordFrame, mediaType: 1}])`, then text set via `GetFusionCompByIndex(1)` → `TextPlus` tool → `SetInput("StyledText", ...)`. Verify that each instance's text is independent.
(c) A bundled `.setting` title template.
(d) An FCPXML/EDL import as a last resort.
For whichever strategy works, verify frame-accurate start, duration, track, and text, and confirm the title is editable in the Inspector. Read Text+ input names from `GetInputList()` rather than assuming them.

**Style.** A clean minimal lower-third. Configurable font, size, color, horizontal margin (default ~6% of width) and vertical position. Left titles use left justification and right titles use right justification.

**UI.** Use Resolve's built-in `fusion.UIManager` / `bmd.UIDispatcher` (no Tk or Qt). The window has:
- Scan / Preview button
- Text source (Name / Note / Both)
- Marker color filter (multi-select, from colors found)
- Include source markers
- Selected clips only
- First title track
- Font / size
- Dry run (default ON)
- Generate button

The report pane lists clips, markers, planned title→track/frame assignments, conflicts, and skips. Generation happens only after an explicit confirmation.

**Safety & repeatability.**
- Before generating, offer to **duplicate the timeline** and work on the copy. Default to yes.
- Tag every generated title (e.g. a name prefix plus a clip-level marker with `customData` holding a JSON id such as `{"tool":"m2t","src":<source uniqueId>,"marker":<frameId>}`, and/or a sidecar JSON next to the script keyed by project and timeline).
- On a re-run, detect existing generated titles and offer Skip or Regenerate. Regenerate deletes only tagged items, using `DeleteClips(..., False)`.
- Missing project or timeline → show a dialog, not a traceback.
- Print a final summary of created / skipped / failed titles with reasons.

**Process.** Phase 1 (diagnostic) is done and its report is attached. Start at **Phase 2**: a minimal standalone test script that creates ONE title from ONE marker on a duplicate timeline and prints verification of text, track, start, and duration. Stop there, tell me exactly what to run and what to look for, and wait for my results before Phase 3 (alternating multi-track), Phase 4 (UI, dry run, dedupe, errors), and Phase 5 (packaging + install/test README). Keep each phase in a separate file.
