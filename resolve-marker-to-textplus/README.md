# Resolve Clip Marker → Text+ (research + Phase 1)

Targets **DaVinci Resolve Studio 20.3 and 21.x**, macOS (Apple Silicon).

| File | What it is |
|---|---|
| `Marker Diagnostic (Phase 1).py` | Read-only diagnostic. Changes nothing in the project. |
| `RESEARCH_NOTES.md` | API facts, the open questions, and what you need to test in Resolve |
| `IMPROVED_PROMPT.md` | The revised prompt to give your personal Claude for the full build |

## Install (macOS)

1. **Python 3 must be installed.** Resolve doesn't ship its own Python. Install Python 3 from python.org (the universal2 installer, e.g. 3.12) if `python3 --version` in Terminal doesn't show one. Note: since **Resolve 21.1, Python scripting requires Studio**. You have Studio, so this is fine.
2. Copy the script into the user-level Utility scripts folder (create the folders if they don't exist):

   ```
   ~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
   ```

   In Finder: **Go > Go to Folder…** (⇧⌘G) and paste the path. Scripts in `Utility` appear on every page. Scripts in `Edit` appear only on the Edit page.
3. Restart Resolve, or just reopen the Workspace menu. The list is usually rescanned.

## Run

1. Open a project and a timeline with some clip markers on it. Select a clip in the Edit page, press **M**, and type a name and note. Also add one **timeline** marker (deselect all clips and press M) and one **source** marker (in the Source viewer) for contrast.
2. **Workspace > Console**, then pick **Py3** at the top so you see the output.
3. **Workspace > Scripts > Marker Diagnostic (Phase 1)**.
4. Read the Console output. The same report is saved to `~/Desktop/Resolve_Marker_Diagnostic_<date>.txt`.

If nothing happens, look in the Console for "Python not found" or a similar message. That means Python 3 isn't installed or Resolve can't see it.

## What to check in the report (and paste into the next prompt)

- **Version string** (20.3.x vs 21.x).
- For a clip you trimmed at its head: is a marker's `frameId` counted from the **clip's visible start** or from the **source media start**? The report prints both candidate timeline frames. Compare them with where the marker actually sits.
- Is `end - start == duration`? If so, the end frame is exclusive.
- The **API PROBE** section shows which methods exist on your build. Paste the whole report into your personal Claude session.
