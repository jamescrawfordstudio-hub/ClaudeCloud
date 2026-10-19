#!/usr/bin/env python3
"""
Resolve Clip Marker to Text+ -- Phase 1 diagnostic (READ-ONLY)

Targets DaVinci Resolve Studio 20.3 and 21.x on macOS.

This script NEVER modifies the project or timeline. It only reads:
  * Resolve version, project, current timeline, frame rate, start frame
  * every video track (name, enabled, locked) and every clip on it
  * each clip's start / end / duration / offsets / source frames
  * clip-level markers on the TimelineItem (what we need)
  * markers on the clip's MediaPoolItem (source-clip markers - a DIFFERENT thing)
  * timeline markers (also a DIFFERENT thing, listed so you can tell them apart)
  * a "does this method exist?" probe of the API calls later phases depend on

Output goes to Workspace > Console AND to a text file on your Desktop.

Install: copy this file to
  ~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
Run:     Workspace > Scripts > Marker Diagnostic (Phase 1)
"""

import datetime
import os
import sys
import traceback

LINES = []


def out(text=""):
    LINES.append(str(text))
    print(text)


def safe(fn, *args, default="<error>"):
    """Call a Resolve API method without letting one failure kill the report."""
    if fn is None:
        return "<method missing>"
    try:
        return fn(*args)
    except Exception as exc:  # the Resolve bridge raises odd types
        return "%s: %s" % (default, exc)


def method(obj, name):
    """Return a bound method or None. On the Resolve bridge, unknown names
    usually come back as None, so this is a hint, not proof."""
    try:
        return getattr(obj, name, None)
    except Exception:
        return None


# --------------------------------------------------------------------------
# Connect
# --------------------------------------------------------------------------
def get_resolve():
    # 1) Launched from Workspace > Scripts: Resolve injects `resolve` (and bmd/fusion)
    g = globals()
    if g.get("resolve"):
        return g["resolve"], "injected global 'resolve'"
    bmd_mod = g.get("bmd")
    if bmd_mod is not None:
        try:
            r = bmd_mod.scriptapp("Resolve")
            if r:
                return r, "bmd.scriptapp('Resolve')"
        except Exception:
            pass
    # 2) Launched externally (Terminal) - needs Preferences > General >
    #    External scripting using: Local
    try:
        import DaVinciResolveScript as dvr  # noqa
    except ImportError:
        mod_dir = ("/Library/Application Support/Blackmagic Design/"
                   "DaVinci Resolve/Developer/Scripting/Modules/")
        if os.path.isdir(mod_dir) and mod_dir not in sys.path:
            sys.path.append(mod_dir)
        try:
            import DaVinciResolveScript as dvr  # noqa
        except ImportError:
            return None, "DaVinciResolveScript module not found"
    try:
        r = dvr.scriptapp("Resolve")
        return r, "DaVinciResolveScript.scriptapp('Resolve')"
    except Exception as exc:
        return None, "scriptapp failed: %s" % exc


# --------------------------------------------------------------------------
# Report sections
# --------------------------------------------------------------------------
PROBE = {
    "Resolve": ["GetVersion", "GetVersionString", "GetProductName",
                "GetProjectManager", "GetCurrentPage", "OpenPage"],
    "Project": ["GetCurrentTimeline", "GetMediaPool", "GetSetting",
                "GetTimelineCount", "GetTimelineByIndex", "SetCurrentTimeline"],
    "MediaPool": ["AppendToTimeline", "CreateEmptyTimeline", "CreateTimelineFromClips",
                  "ImportMedia", "GetRootFolder", "GetCurrentFolder", "AddSubFolder"],
    "Timeline": ["GetName", "GetStartFrame", "GetEndFrame", "GetStartTimecode",
                 "GetTrackCount", "GetItemListInTrack", "GetTrackName",
                 "GetIsTrackEnabled", "GetIsTrackLocked", "AddTrack", "DeleteTrack",
                 "SetTrackName", "GetMarkers", "GetCurrentTimecode", "SetCurrentTimecode",
                 "GetCurrentVideoItem", "InsertFusionTitleIntoTimeline",
                 "InsertTitleIntoTimeline", "InsertGeneratorIntoTimeline",
                 "InsertFusionGeneratorIntoTimeline", "InsertFusionCompositionIntoTimeline",
                 "InsertOFXGeneratorIntoTimeline", "CreateFusionClip",
                 "DuplicateTimeline", "DeleteClips", "GetSelectedClips",
                 "GetSetting", "Export"],
    "TimelineItem": ["GetName", "GetStart", "GetEnd", "GetDuration",
                     "GetLeftOffset", "GetRightOffset", "GetSourceStartFrame",
                     "GetSourceEndFrame", "GetMarkers", "GetMarkerByCustomData",
                     "AddMarker", "GetMediaPoolItem", "GetUniqueId", "GetTrackTypeAndIndex",
                     "GetProperty", "SetProperty", "GetClipEnabled",
                     "GetFusionCompCount", "GetFusionCompByIndex", "GetFusionCompNameList",
                     "AddFusionComp", "SetClipColor", "GetClipColor",
                     "SetStart", "SetEnd", "SetName"],
}


def probe(label, obj):
    if obj is None:
        out("  %-13s (no object available to probe)" % label)
        return
    present, missing = [], []
    for name in PROBE[label]:
        (present if method(obj, name) is not None else missing).append(name)
    out("  %-13s present: %s" % (label, ", ".join(present) or "-"))
    if missing:
        out("  %-13s MISSING: %s" % ("", ", ".join(missing)))


def fmt_markers(markers, indent):
    if not isinstance(markers, dict):
        out("%s(GetMarkers returned %r)" % (indent, markers))
        return 0
    if not markers:
        out("%s(none)" % indent)
        return 0
    for frame_id in sorted(markers):
        m = markers[frame_id] or {}
        out("%sframeId=%-7s color=%-9s dur=%-4s name=%r note=%r customData=%r" % (
            indent, frame_id, m.get("color"), m.get("duration"),
            m.get("name"), m.get("note"), m.get("customData")))
    return len(markers)


def main():
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    out("=" * 78)
    out("Resolve Clip Marker Diagnostic (Phase 1, read-only)   %s" % stamp)
    out("Python %s" % sys.version.replace("\n", " "))
    out("=" * 78)

    resolve, how = get_resolve()
    if not resolve:
        out("ERROR: could not connect to Resolve (%s)." % how)
        out("Run this from Workspace > Scripts inside DaVinci Resolve Studio.")
        return
    out("Connected via: %s" % how)
    out("Product: %s   Version: %s" % (safe(method(resolve, "GetProductName")),
                                       safe(method(resolve, "GetVersionString"))))
    out("Current page: %s" % safe(method(resolve, "GetCurrentPage")))

    pm = safe(method(resolve, "GetProjectManager"), default=None)
    project = safe(method(pm, "GetCurrentProject"), default=None) if pm else None
    if not project or isinstance(project, str):
        out("ERROR: no project is open.")
        return
    out("Project: %s" % safe(method(project, "GetName")))

    timeline = safe(method(project, "GetCurrentTimeline"), default=None)
    if not timeline or isinstance(timeline, str):
        out("ERROR: no current timeline. Open a timeline in the Edit page and re-run.")
        return

    out("Timeline: %s" % safe(method(timeline, "GetName")))
    out("  frame rate (timelineFrameRate): %s" % safe(method(timeline, "GetSetting"), "timelineFrameRate"))
    out("  start frame: %s   end frame: %s   start TC: %s" % (
        safe(method(timeline, "GetStartFrame")), safe(method(timeline, "GetEndFrame")),
        safe(method(timeline, "GetStartTimecode"))))
    out("  playhead TC: %s" % safe(method(timeline, "GetCurrentTimecode")))
    vcount = safe(method(timeline, "GetTrackCount"), "video")
    acount = safe(method(timeline, "GetTrackCount"), "audio")
    scount = safe(method(timeline, "GetTrackCount"), "subtitle")
    out("  tracks: video=%s audio=%s subtitle=%s" % (vcount, acount, scount))

    # Selected clips (GetSelectedClips added in Resolve 21.0.4; read-only)
    sel = method(timeline, "GetSelectedClips")
    if sel is not None:
        res = safe(sel)
        try:
            names = [safe(method(i, "GetName")) for i in (res.values() if isinstance(res, dict) else res)]
            out("  selected clips (21.0.4+ API): %s" % names)
        except Exception:
            out("  selected clips (21.0.4+ API) raw: %r" % (res,))

    # ---------------- Timeline markers (NOT clip markers)
    out("")
    out("-" * 78)
    out("TIMELINE markers (ruler markers - NOT used by this tool, shown for contrast)")
    fmt_markers(safe(method(timeline, "GetMarkers")), "  ")

    # ---------------- Tracks and clips
    total_items = total_clip_markers = total_mpi_markers = 0
    first_item = None
    if not isinstance(vcount, int):
        out("ERROR: could not read video track count.")
        vcount = 0
    for t in range(1, vcount + 1):
        out("")
        out("-" * 78)
        out("VIDEO TRACK V%d  name=%r  enabled=%s  locked=%s" % (
            t, safe(method(timeline, "GetTrackName"), "video", t),
            safe(method(timeline, "GetIsTrackEnabled"), "video", t),
            safe(method(timeline, "GetIsTrackLocked"), "video", t)))
        items = safe(method(timeline, "GetItemListInTrack"), "video", t)
        if not isinstance(items, (list, tuple)) or not items:
            out("  (no clips)")
            continue
        for idx, item in enumerate(items, 1):
            total_items += 1
            first_item = first_item or item
            start = safe(method(item, "GetStart"))
            end = safe(method(item, "GetEnd"))
            left = safe(method(item, "GetLeftOffset"))
            mpi = safe(method(item, "GetMediaPoolItem"), default=None)
            mpi = None if isinstance(mpi, str) else mpi
            out("  [%d] %r" % (idx, safe(method(item, "GetName"))))
            out("      uniqueId=%s  trackTypeAndIndex=%s" % (
                safe(method(item, "GetUniqueId")), safe(method(item, "GetTrackTypeAndIndex"))))
            out("      start=%s end=%s duration=%s  (end is exclusive if end-start == duration)" % (
                start, end, safe(method(item, "GetDuration"))))
            out("      leftOffset=%s rightOffset=%s sourceStart=%s sourceEnd=%s" % (
                left, safe(method(item, "GetRightOffset")),
                safe(method(item, "GetSourceStartFrame")), safe(method(item, "GetSourceEndFrame"))))
            out("      mediaPoolItem=%s  fusionComps=%s  clipColor=%r" % (
                safe(method(mpi, "GetName")) if mpi else "None (generator/title/compound?)",
                safe(method(item, "GetFusionCompCount")), safe(method(item, "GetClipColor"))))
            if mpi:
                out("      media type=%r  file=%r" % (
                    safe(method(mpi, "GetClipProperty"), "Type"),
                    safe(method(mpi, "GetClipProperty"), "File Path")))

            out("      CLIP markers (TimelineItem.GetMarkers) - the ones this tool uses:")
            markers = safe(method(item, "GetMarkers"))
            n = fmt_markers(markers, "        ")
            total_clip_markers += n
            if n and isinstance(start, int):
                # frameId reference point is unverified: print both candidates so
                # you can compare against where the marker actually sits on screen.
                for fid in sorted(markers):
                    cand_a = start + fid
                    cand_b = start + fid - left if isinstance(left, int) else "?"
                    out("        frameId %s -> timeline frame if relative to clip start: %s; "
                        "if relative to source media start: %s" % (fid, cand_a, cand_b))

            if mpi:
                out("      SOURCE markers (MediaPoolItem.GetMarkers) - different thing:")
                total_mpi_markers += fmt_markers(safe(method(mpi, "GetMarkers")), "        ")

    # ---------------- API probe
    out("")
    out("-" * 78)
    out("API PROBE (does the method name resolve? hint only - not a behavior test)")
    probe("Resolve", resolve)
    probe("Project", project)
    probe("MediaPool", safe(method(project, "GetMediaPool"), default=None))
    probe("Timeline", timeline)
    probe("TimelineItem", first_item)

    out("")
    out("=" * 78)
    out("SUMMARY: %d video tracks, %d clips, %d clip markers, %d source-clip markers" % (
        vcount, total_items, total_clip_markers, total_mpi_markers))
    out("Nothing in the project or timeline was modified.")
    out("=" * 78)


def write_report():
    path = os.path.expanduser("~/Desktop/Resolve_Marker_Diagnostic_%s.txt" %
                              datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(LINES) + "\n")
        print("Report saved to: %s" % path)
    except Exception as exc:
        print("Could not save report file (%s); copy it from the Console instead." % exc)


try:
    main()
except Exception:
    out("UNEXPECTED ERROR:\n" + traceback.format_exc())
finally:
    write_report()
