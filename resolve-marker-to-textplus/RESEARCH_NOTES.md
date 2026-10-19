# Research notes: Resolve 20.3 / 21 scripting for marker → Text+

Status labels: **Known** (stable, long-documented API), **Likely** (from memory or community sources, verify), **Unknown** (must test in Resolve).

## Authoritative source on your Mac
`/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/README.txt`
(also reachable via **Help > Documentation > Developer**). This file is version-specific. **Attach the 20.3 and 21 copies to your personal Claude session.** It's the single most valuable input you can give it.

## Version facts
- **21.0.3** added scripting APIs for project attributes in bins, user preference presets, and UI layout / data burn presets.
- **21.0.4** added `Timeline.GetSelectedClips()` (useful for a "selected clips only" mode). Get the timeline from a media pool timeline entry. SetRenderSettings options.
- **21.1** made Python and advanced scripting **Studio-only**. 21.1.1 added async APIs (Quick Export, transcription, scene cut).
- No source found says `AddTrack` or `InsertFusionTitleIntoTimeline` changed in 21. Design for 20.3 and feature-detect the 21 extras.

## Marker types: three different things
| Type | API | Notes |
|---|---|---|
| Timeline marker (ruler) | `Timeline.GetMarkers()` | **Not** what we want |
| Clip marker on a timeline clip | `TimelineItem.GetMarkers()` | **What we want** |
| Source marker on the media | `MediaPoolItem.GetMarkers()` | Shows on every use of the clip. Decide whether to include it as an option |

`GetMarkers()` returns `{frameId: {color, duration, note, name, customData}}` (**Known**). The frameId's reference point (visible clip start vs. media start) is **Unknown**. The diagnostic prints both candidates.

## Key API questions for the build
| Need | Candidate API | Status / risk |
|---|---|---|
| Clip bounds | `GetStart()`, `GetEnd()`, `GetDuration()` | Known. Whether end is exclusive is **Unknown** (diagnostic checks it) |
| Add video track | `Timeline.AddTrack("video")` | Known: appends on top. An `index` option for inserting mid-stack is **Likely** in newer builds; verify in the README |
| Track enabled/locked | `GetIsTrackLocked`, `SetTrackLock`… | Likely (18+). Locked target tracks must be refused |
| Insert Text+ | `Timeline.InsertFusionTitleIntoTimeline("Text+")` | Known to exist. It inserts **at the playhead** on a track Resolve picks (track targeting is undocumented), and duration is the default title length. **Biggest risk** |
| Exact track + frame placement | `MediaPool.AppendToTimeline([{mediaPoolItem, startFrame, endFrame, trackIndex, recordFrame, mediaType}])` | Known (18+). Needs a **MediaPoolItem**. Text+ generators have none, which is why the template approach matters |
| Edit Text+ text | `item.GetFusionCompByIndex(1).FindToolByID("TextPlus")` or `FindTool("Template")`, then `tool.SetInput("StyledText", text)`. Also `HorizontalJustificationNew`, `Center`, `Font`, `Size` | Known for Fusion. Input names should be confirmed by reading `tool.GetInputList()` |
| Move/resize an item after insert | `TimelineItem.SetStart/SetEnd` | **Unknown / probably absent**. The probe reports it |
| Tag generated titles | `TimelineItem.AddMarker(..., customData)` + `GetMarkerByCustomData`, or `SetClipColor` + a name prefix, or a JSON sidecar keyed by `GetUniqueId()` | customData markers are Known. A sidecar file is the most robust |
| Delete for regenerate | `Timeline.DeleteClips([items], ripple=False)` | Known |

## Candidate strategies for creating titles (Phase 2 must pick one by testing)
1. **Playhead + InsertFusionTitleIntoTimeline.** `SetCurrentTimecode(clip start)`, insert, find the new item, then set its text. Problems: you can't choose the track and you can't set the length unless SetEnd or trimming exists. Probably fails "exact duration".
2. **Fusion Composition media pool clip + AppendToTimeline (recommended to test first).** In the Media Pool: right-click > *New Fusion Composition* (or create one via the API if available). Build a Text+ comp inside it once and save it as a template. Then `AppendToTimeline` with `trackIndex`, `recordFrame`, `startFrame`, and `endFrame` gives exact placement and length on any track. Afterwards, set the text per item through `GetFusionCompByIndex(1)`. Caveat: each instance may share one comp. You need to check whether editing one instance changes the others. If it does, the fix is to use `AddFusionComp()` or a per-item comp.
3. **Pre-made title template** (`.setting` macro in `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Templates/Edit/Titles/`). This works with option 1 by name, so it still has the placement problem.
4. **Fallback: generate a timeline/EDL/FCPXML** containing titles and import it. This is heavier but placement is exact. Text+ attributes in FCPXML import are unreliable.

## What to test manually in Resolve (5-minute checklist)
1. Run the diagnostic and save the report.
2. In the Console (Py3), on a **duplicate** timeline, run:
   `tl = resolve.GetProjectManager().GetCurrentProject().GetCurrentTimeline(); print(tl.InsertFusionTitleIntoTimeline("Text+"))`
   Note which track it lands on, where it starts, and how long it is.
3. Create a Fusion Composition in the Media Pool, then try `AppendToTimeline` with `trackIndex: 3, recordFrame: <clip start>`. Does it land exactly?
4. Edit the text on two instances. Are they independent?

Sources: [Newsshooter 21.0.4](https://www.newsshooter.com/2026/08/05/davinci-resolve-21-0-4-update/), [Digital Production 21.0.4](https://digitalproduction.com/2026/08/25/blackmagic-adds-script-hooks-and-pre-record/), [Digital Production 21.1.1](https://digitalproduction.com/2026/10/06/davinci-resolve-21-1-1/), [AlternativeTo 21.1](https://alternativeto.net/news/2026/9/davinci-resolve-21-1-changes-scripting-and-editing-tools/), [BMD forum: TimelineItem.AddMarker bug](https://forum.blackmagicdesign.com/viewtopic.php?p=924536)
