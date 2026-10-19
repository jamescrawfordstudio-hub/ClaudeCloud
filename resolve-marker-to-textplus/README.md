# MarkerTitler — clip markers → Text+ titles for DaVinci Resolve

For **DaVinci Resolve Studio 20.3 and 21.x** on macOS (Apple Silicon). It also works on Windows and Linux.

Each clip marker becomes a real Text+ title that spans the whole clip. On a clip with several markers the titles alternate left, right, left, right. Each one sits on its own track above the clip, so none of them cover each other or your footage.

| File | Purpose |
|---|---|
| `MarkerTitler.lua` | **The tool.** Copy this into Resolve. |
| `Marker Diagnostic (Phase 1).py` | Optional read-only report of every track, clip and marker. Use it if something looks off. Needs Python 3. |
| `tests/` | Offline tests against a fake Resolve. Run `tests/run_tests.sh`; it needs `pip install lupa`. |
| `RESEARCH_NOTES.md` | API findings behind the design. |
| `IMPROVED_PROMPT.md` | The earlier hand-off prompt. Only needed if you want a follow-up build. |

The tool is written in **Lua**, like other Resolve script collections such as EditorScripts. Resolve runs Lua by itself, so **you don't need to install Python**.

## Install

1. In Finder press **⇧⌘G** and paste:
   `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`
   Create the `Utility` folder if it isn't there.
2. Copy `MarkerTitler.lua` into that folder.
3. In Resolve it appears under **Workspace > Scripts > MarkerTitler** on every page.

## One-time setup per project

Drag **Text+** from **Effects > Titles** into the **Media Pool**.

To set the default look, open that Text+ (or any copy of it) in the Inspector or the Fusion page, style it, then tick *Keep the template's font, size and color*. You can also rename it **Marker Title Template** and the tool will pick it automatically.

> Why: Resolve's scripting API can only place a clip at an exact track, frame and length with `MediaPool.AppendToTimeline`, and that needs a Media Pool item. The other route, `InsertFusionTitleIntoTimeline`, always drops the title at the playhead at the default length.

## Use

1. Open your timeline in the Edit page. Add clip markers by selecting a clip and pressing **M**. Type the title text as the marker's name or note.
2. Run **Workspace > Scripts > MarkerTitler**.
3. Choose your options:
   - **Title template:** the Text+ clip in your Media Pool.
   - **Text from:** the marker name, the note, the name falling back to the note, or "Name - Note".
   - **Marker color:** only use markers of one color.
   - **First title track:** *Auto* puts titles just above each clip. You can also choose a minimum track number.
   - **Earlier titles:** on a re-run, either *Skip* markers that already have a title or *Regenerate* those titles.
   - **Font / style, Size %, color (hex), Margin %, Height %:** how titles look and where they sit. Size is the Text+ size × 100.
   - **Also use source markers:** include markers added in the Source viewer (Media Pool markers), as long as they're inside the used part of the clip.
   - **Selected clips only:** needs Resolve **21.0.4+**. On 20.3 the tool scans everything and tells you so.
   - **Work on a duplicate of the timeline:** on by default and recommended. The original timeline stays exactly as it was.
4. Click **Scan / Preview**. The report lists every planned title with its track, frames, side and text, plus everything skipped and why.
5. Untick **Dry run**. Click **Generate Titles**, then click again to **Confirm**. If anything changes between the two clicks, it asks again.

### What it guarantees

- It never deletes or moves footage, audio, markers or titles you made. *Regenerate* only removes titles this tool made earlier.
- Titles only go into empty space. If a track is busy or locked, the title moves up a track. New video tracks are added on top when needed.
- Every title starts and ends exactly on its clip. The tool checks this after placing each one. If Resolve gets the length off by a frame on the first title, the tool corrects that title and every one after it. Anything that still doesn't fit is removed and reported.
- Markers in the trimmed-off part of a clip, markers with no text, and markers filtered out by color are reported and skipped.
- Generated titles get a **Cream** tag marker and a **Teal** clip color. The marker's hidden custom data links the title back to its clip and marker, which is how re-runs avoid duplicates. Don't delete the tag marker if you want re-runs to recognise the title.

## Testing checklist (5 minutes, on a test project)

1. Put a clip on V1 with **3 markers**, trimmed at the head, and a second clip with 1 marker. Put something on V2 overlapping part of the first clip.
2. Run it with Dry run on. Check that the preview shows V3/V4/V5 (left/right/left) for the first clip and V2 for the second.
3. Generate on a duplicate. On the new timeline, check that each title starts and ends on the clip, that the text matches, and that the left and right alignment is correct. Change one title's text in the Inspector to confirm each title can be edited on its own.
4. Run it again. It should report "already has a title" and create nothing. Try *Regenerate*.

If anything misbehaves, run **Marker Diagnostic (Phase 1)** and keep the Desktop report. It shows exactly what the API returned.

## Known limits

- Testing so far used a fake Resolve, not a real install. Run the checklist above before using it on real work.
- If Text+ setting names differ on your build, the text is still set but alignment or style may not apply. The report flags a title whose text didn't stick.
- Resolve's Undo may not group script changes. That's why *duplicate timeline* is on by default.
