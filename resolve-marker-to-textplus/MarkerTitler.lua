--[[
    MarkerTitler  v1.0.0
    Turns clip markers into Text+ title clips.
    DaVinci Resolve Studio 20.3 and 21.x (macOS; also runs on Windows/Linux)

    Install: copy this file to
      ~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
    Run:     Workspace > Scripts > MarkerTitler

    One-time setup per project: drag "Text+" from Effects > Titles into the
    Media Pool. The script places that clip with MediaPool:AppendToTimeline,
    which is the only API path that takes an exact track, record frame and
    length (InsertFusionTitleIntoTimeline only drops at the playhead).

    How it works
      * Reads TimelineItem clip markers (optionally MediaPoolItem source markers)
        that fall inside each clip's visible range. Marker frame ids count from
        the start of the source media, so the visible range is
        [leftOffset, leftOffset + duration).
      * Marker 1 -> left-aligned title on the left, marker 2 -> right, 3 -> left...
      * Every title spans the whole clip. The Nth title of a clip sits on a
        higher track than the (N-1)th and only ever goes into empty space;
        new video tracks are added on top when needed.
      * Each generated title carries a tag marker (customData) so re-runs can
        skip or regenerate it. Nothing else on the timeline is touched.
]]

local SCRIPT_NAME = "MarkerTitler"
local SCRIPT_VERSION = "1.0.0"
local TAG_PREFIX = "markertitles"
local TAG_MARKER_COLOR = "Cream"
local TAG_CLIP_COLOR = "Teal"
local TEMPLATE_NAME = "Marker Title Template"
local MAX_TRACKS = 50

local MARKER_COLORS = {
    "Blue", "Cyan", "Green", "Yellow", "Red", "Pink", "Purple", "Fuchsia",
    "Rose", "Lavender", "Sky", "Mint", "Lemon", "Sand", "Cocoa", "Cream",
}
local TEXT_SOURCES = { "Marker name", "Marker note", "Name, or note if name is empty", "Name - Note" }
local EXISTING_MODES = { "Skip them", "Regenerate them" }

local unpack = unpack or table.unpack
local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local IS_MACOS = not IS_WINDOWS and (os.getenv("HOME") or ""):find("^/Users/") ~= nil

-- ============================================================================
-- Helpers
-- ============================================================================

-- Calls obj:method(...) and returns nil instead of raising when the method is
-- missing on this Resolve build or the call fails.
local function call(obj, method, ...)
    if obj == nil then return nil end
    local n, args = select("#", ...), { ... }
    local ok, result = pcall(function()
        local fn = obj[method]
        if fn == nil then return nil end
        return fn(obj, unpack(args, 1, n))
    end)
    if ok then return result end
    return nil
end

local function toFrame(value)
    if type(value) ~= "number" then return nil end
    return math.floor(value + 0.5)
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split(s, sep)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return out
end

-- Tables coming back from Resolve can mix numeric keys with string keys
-- (e.g. "__flags"), so never compare keys of different types.
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function numericKeys(t)
    local keys = {}
    for k in pairs(t or {}) do
        if type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- Values of an API list, in order, ignoring non-numeric bookkeeping keys.
local function listOf(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for _, k in ipairs(numericKeys(t)) do out[#out + 1] = t[k] end
    return out
end

local function hexToRgb(hex)
    local r, g, b = trim(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function shorten(s, n)
    s = (s or ""):gsub("[\r\n]+", " ")
    if #s > n then return s:sub(1, n - 3) .. "..." end
    return s
end

-- ============================================================================
-- Settings (remembered between runs)
-- ============================================================================

local DEFAULTS = {
    textSource = 0, color = "All colors", firstTrack = 0, existing = 0,
    font = "Open Sans", style = "Bold", size = 6, margin = 6, vpos = 12,
    colorHex = "#FFFFFF", keepStyle = false, includeSource = false,
    selectedOnly = false, duplicate = true, dryRun = true, template = "",
}

local function settingsPath()
    local dir
    if IS_WINDOWS then
        dir = (os.getenv("APPDATA") or ".") .. "\\MarkerTitler"
    elseif IS_MACOS then
        dir = os.getenv("HOME") .. "/Library/Application Support/MarkerTitler"
    else
        dir = (os.getenv("HOME") or ".") .. "/.config/marker-titles"
    end
    return dir, dir .. (IS_WINDOWS and "\\" or "/") .. "settings.txt"
end

local function loadSettings()
    local s = {}
    for k, v in pairs(DEFAULTS) do s[k] = v end
    local _, path = settingsPath()
    local fh = io.open(path, "r")
    if not fh then return s end
    for line in fh:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k and DEFAULTS[k] ~= nil then
            local kind = type(DEFAULTS[k])
            if kind == "number" then s[k] = tonumber(v) or DEFAULTS[k]
            elseif kind == "boolean" then s[k] = (v == "true")
            else s[k] = v end
        end
    end
    fh:close()
    return s
end

local function saveSettings(s)
    pcall(function()
        local dir, path = settingsPath()
        if IS_WINDOWS then
            os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
        else
            os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
        end
        local fh = io.open(path, "w")
        if not fh then return end
        for _, k in ipairs(sortedKeys(DEFAULTS)) do fh:write(k, "=", tostring(s[k]), "\n") end
        fh:close()
    end)
end

-- ============================================================================
-- Resolve access
-- ============================================================================

local function getContext()
    local resolve = Resolve and Resolve() or nil
    if type(resolve) == "function" then resolve = resolve() end
    if not resolve then return nil, "Could not connect to DaVinci Resolve." end
    local pm = call(resolve, "GetProjectManager")
    local project = call(pm, "GetCurrentProject")
    if not project then return nil, "No project is open." end
    local timeline = call(project, "GetCurrentTimeline")
    if not timeline then return nil, "No timeline is open. Open one in the Edit page." end
    local mediaPool = call(project, "GetMediaPool")
    if not mediaPool then return nil, "Could not access the Media Pool." end
    return {
        resolve = resolve, project = project, timeline = timeline, mediaPool = mediaPool,
        version = call(resolve, "GetVersionString") or "?",
    }
end

local function collectClips(folder, out, path)
    for _, clip in ipairs(listOf(call(folder, "GetClipList"))) do
        out[#out + 1] = { clip = clip, path = path }
    end
    for _, sub in ipairs(listOf(call(folder, "GetSubFolderList"))) do
        collectClips(sub, out, path .. "/" .. (call(sub, "GetName") or "?"))
    end
end

-- Media pool clips that could be a Text+ title. Validated on first use.
local function findTemplates(mediaPool)
    local all, found = {}, {}
    collectClips(call(mediaPool, "GetRootFolder"), all, "")
    for _, entry in ipairs(all) do
        local name = call(entry.clip, "GetName") or ""
        local kind = call(entry.clip, "GetClipProperty", "Type")
        kind = type(kind) == "string" and kind or ""
        local lk = kind:lower()
        if lk:find("title") or lk:find("generator") or lk:find("fusion")
            or name:find("Text+", 1, true) or name:find(TEMPLATE_NAME, 1, true) then
            local rank = name:find(TEMPLATE_NAME, 1, true) and 0 or (name == "Text+" and 1 or 2)
            found[#found + 1] = {
                clip = entry.clip, name = name, kind = kind, rank = rank,
                label = (entry.path ~= "" and (entry.path:sub(2) .. "/") or "") .. name,
            }
        end
    end
    table.sort(found, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.label < b.label
    end)
    return found
end

local function itemUid(item)
    local uid = call(item, "GetUniqueId")
    return uid and tostring(uid) or nil
end

local function markerText(m, source)
    local name, note = trim(m.name), trim(m.note)
    if source == 0 then return name
    elseif source == 1 then return note
    elseif source == 2 then return name ~= "" and name or note
    end
    if name ~= "" and note ~= "" then return name .. " - " .. note end
    return name ~= "" and name or note
end

-- customData layout: markertitles|1|<source uid>|<source track>|<source start>|<marker frame>
local function makeTag(uid, track, start, frame)
    return table.concat({ TAG_PREFIX, "1", uid or "", track, start, frame }, "|")
end

local function parseTag(customData)
    if type(customData) ~= "string" or customData:sub(1, #TAG_PREFIX + 1) ~= TAG_PREFIX .. "|" then return nil end
    local p = split(customData, "|")
    return { uid = p[3] ~= "" and p[3] or nil, track = p[4], start = p[5], frame = p[6] }
end

local function keysFor(uid, track, start, frame)
    local keys = { "p:" .. track .. "|" .. start .. "|" .. frame }
    if uid then keys[2] = "u:" .. uid .. "|" .. frame end
    return keys
end

-- ============================================================================
-- Scan + plan (read-only)
-- ============================================================================

local function buildPlan(ctx, opts)
    local timeline = ctx.timeline
    local plan = {
        timelineName = call(timeline, "GetName") or "?",
        clips = {}, titles = {}, skipped = {}, notes = {}, deletions = {},
        existingCount = 0, orphanCount = 0, markerCount = 0, maxTrack = 0,
    }
    local trackCount = call(timeline, "GetTrackCount", "video") or 0
    plan.trackCount = trackCount
    plan.maxTrack = trackCount

    local selected
    if opts.selectedOnly then
        local sel = call(timeline, "GetSelectedClips")
        if type(sel) ~= "table" then
            plan.notes[#plan.notes + 1] = "\"Selected clips only\" needs Resolve 21.0.4 or later; scanning all clips."
        else
            selected = {}
            for _, item in ipairs(listOf(sel)) do
                local uid = itemUid(item)
                if uid then selected[uid] = true end
            end
        end
    end

    local occupancy, locked, existing, sources = {}, {}, {}, {}

    for t = 1, trackCount do
        occupancy[t] = {}
        locked[t] = call(timeline, "GetIsTrackLocked", "video", t) == true
        for _, item in ipairs(listOf(call(timeline, "GetItemListInTrack", "video", t))) do
            local s, d = toFrame(call(item, "GetStart")), toFrame(call(item, "GetDuration"))
            local interval = s and d and { s = s, e = s + d, item = item } or nil
            if interval then table.insert(occupancy[t], interval) end

            local tag
            for _, m in pairs(call(item, "GetMarkers") or {}) do
                if type(m) == "table" then tag = tag or parseTag(m.customData) end
            end
            if tag then
                plan.existingCount = plan.existingCount + 1
                local entry = { item = item, track = t, interval = interval, used = false }
                for _, key in ipairs(keysFor(tag.uid, tag.track, tag.start, tag.frame)) do existing[key] = entry end
            else
                sources[#sources + 1] = { item = item, track = t, start = s, dur = d }
            end
        end
    end

    -- Collect eligible markers per source clip
    for _, src in ipairs(sources) do
        local item = src.item
        local name = call(item, "GetName") or "Clip"
        local left = toFrame(call(item, "GetLeftOffset"))
        local uid = itemUid(item)
        local markers = {}
        for f, m in pairs(call(item, "GetMarkers") or {}) do
            if toFrame(f) and type(m) == "table" then markers[toFrame(f)] = m end
        end
        if opts.includeSource then
            local mpi = call(item, "GetMediaPoolItem")
            for f, m in pairs(call(mpi, "GetMarkers") or {}) do
                f = toFrame(f)
                if f and type(m) == "table" and markers[f] == nil then markers[f] = m end
            end
        end

        local frames = sortedKeys(markers)
        local inSelection = not selected or (uid and selected[uid])
        if #frames > 0 and inSelection then
            if not (src.start and src.dur and left) then
                plan.skipped[#plan.skipped + 1] = string.format("V%d %s: %d marker(s) - clip has no source range (generator/compound?)", src.track, name, #frames)
            else
                local clip = { name = name, track = src.track, start = src.start, dur = src.dur, uid = uid, markers = {} }
                for _, f in ipairs(frames) do
                    local m = markers[f]
                    plan.markerCount = plan.markerCount + 1
                    local where = string.format("V%d %s @%d", src.track, name, src.start + f - left)
                    if f < left or f >= left + src.dur then
                        plan.skipped[#plan.skipped + 1] = where .. ": marker is in the trimmed-off part of the clip"
                    elseif opts.color ~= "All colors" and m.color ~= opts.color then
                        plan.skipped[#plan.skipped + 1] = where .. ": color " .. tostring(m.color) .. " filtered out"
                    else
                        local text = markerText(m, opts.textSource)
                        if text == "" then
                            plan.skipped[#plan.skipped + 1] = where .. ": no marker text"
                        else
                            clip.markers[#clip.markers + 1] = { frame = f, text = text, color = m.color }
                        end
                    end
                end
                if #clip.markers > 0 then plan.clips[#plan.clips + 1] = clip end
            end
        end
    end

    -- Handle titles generated by an earlier run
    for _, clip in ipairs(plan.clips) do
        local kept = {}
        for i, mk in ipairs(clip.markers) do
            mk.index = i
            local prior
            for _, key in ipairs(keysFor(clip.uid, clip.track, clip.start, mk.frame)) do
                prior = prior or existing[key]
            end
            if prior and not prior.used then
                prior.used = true
                if opts.existing == 1 then
                    plan.deletions[#plan.deletions + 1] = prior.item
                    for idx, iv in ipairs(occupancy[prior.track]) do
                        if iv.item == prior.item then table.remove(occupancy[prior.track], idx) break end
                    end
                    kept[#kept + 1] = mk
                else
                    plan.skipped[#plan.skipped + 1] = string.format("V%d %s: \"%s\" already has a title", clip.track, clip.name, shorten(mk.text, 30))
                end
            elseif prior then
                plan.skipped[#plan.skipped + 1] = string.format("V%d %s: \"%s\" already has a title", clip.track, clip.name, shorten(mk.text, 30))
            else
                kept[#kept + 1] = mk
            end
        end
        clip.markers = kept
    end
    local seen = {}
    for _, entry in pairs(existing) do
        if not entry.used and not seen[entry] then plan.orphanCount = plan.orphanCount + 1 end
        seen[entry] = true
    end

    -- Assign tracks: only empty space, each title above the previous one for the clip
    local function isFree(t, s, e)
        if t <= trackCount and locked[t] then return false end
        for _, iv in ipairs(occupancy[t] or {}) do
            if s < iv.e and iv.s < e then return false end
        end
        return true
    end

    table.sort(plan.clips, function(a, b)
        if a.track ~= b.track then return a.track < b.track end
        return a.start < b.start
    end)
    for _, clip in ipairs(plan.clips) do
        local floor = math.max(clip.track + 1, opts.firstTrack > 0 and opts.firstTrack or 1)
        for i, mk in ipairs(clip.markers) do
            local t = floor
            while t <= MAX_TRACKS and not isFree(t, clip.start, clip.start + clip.dur) do t = t + 1 end
            if t > MAX_TRACKS then
                plan.skipped[#plan.skipped + 1] = string.format("V%d %s: no free track below V%d", clip.track, clip.name, MAX_TRACKS)
                break
            end
            occupancy[t] = occupancy[t] or {}
            table.insert(occupancy[t], { s = clip.start, e = clip.start + clip.dur })
            floor = t + 1
            plan.maxTrack = math.max(plan.maxTrack, t)
            plan.titles[#plan.titles + 1] = {
                clip = clip, marker = mk, track = t,
                side = (i % 2 == 1) and "left" or "right",
                tag = makeTag(clip.uid, clip.track, clip.start, mk.frame),
            }
        end
    end
    return plan
end

local function describePlan(plan, opts, ctx)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(string.format("%s %s  |  Resolve %s  |  Timeline: %s", SCRIPT_NAME, SCRIPT_VERSION, ctx.version, plan.timelineName))
    add(string.format("Markers found: %d   Clips with usable markers: %d   Titles to create: %d",
        plan.markerCount, #plan.clips, #plan.titles))
    if plan.existingCount > 0 then
        add(string.format("Titles from earlier runs: %d (%s)%s", plan.existingCount,
            opts.existing == 1 and string.format("%d will be replaced", #plan.deletions) or "kept, matching markers skipped",
            plan.orphanCount > 0 and string.format(", %d no longer match a marker and are left alone", plan.orphanCount) or ""))
    end
    if plan.maxTrack > plan.trackCount then
        add(string.format("New video tracks needed: %d (V%d-V%d)", plan.maxTrack - plan.trackCount, plan.trackCount + 1, plan.maxTrack))
    end
    for _, n in ipairs(plan.notes) do add("Note: " .. n) end
    add("")
    if #plan.titles > 0 then
        add("PLANNED TITLES")
        for _, t in ipairs(plan.titles) do
            add(string.format("  V%-2d  %6d-%-6d (%4df)  %-5s  %s  <- V%d %s",
                t.track, t.clip.start, t.clip.start + t.clip.dur - 1, t.clip.dur, t.side,
                "\"" .. shorten(t.marker.text, 40) .. "\"", t.clip.track, shorten(t.clip.name, 24)))
        end
        add("")
    end
    if #plan.skipped > 0 then
        add("SKIPPED (" .. #plan.skipped .. ")")
        for _, s in ipairs(plan.skipped) do add("  " .. s) end
        add("")
    end
    return lines
end

-- ============================================================================
-- Generation (modifies the timeline)
-- ============================================================================

local function findTextPlus(comp)
    for _, tool in ipairs(listOf(call(comp, "GetToolList", false, "TextPlus"))) do return tool end
    return nil
end

local function styleTitle(item, title, opts)
    local comp = call(item, "GetFusionCompByIndex", 1)
    local tool = findTextPlus(comp)
    if not tool then return false, "template has no Text+ tool" end
    local function set(name, value) return pcall(function() tool:SetInput(name, value) end) end

    set("StyledText", title.marker.text)
    local isLeft = title.side == "left"
    local margin = (opts.margin or 6) / 100
    set("HorizontalJustificationNew", isLeft and 0 or 2)
    set("HorizontalLeftCenterRight", isLeft and -1 or 1)
    set("Center", { isLeft and margin or (1 - margin), (opts.vpos or 12) / 100 })
    if not opts.keepStyle then
        if trim(opts.font) ~= "" then set("Font", trim(opts.font)) end
        if trim(opts.style) ~= "" then set("Style", trim(opts.style)) end
        set("Size", (opts.size or 6) / 100)
        local r, g, b = hexToRgb(opts.colorHex)
        if r then set("Red1", r) set("Green1", g) set("Blue1", b) end
    end
    local ok, readBack = pcall(function() return tool:GetInput("StyledText") end)
    if ok and readBack ~= nil and readBack ~= title.marker.text then
        return false, "text did not stick (read back \"" .. shorten(tostring(readBack), 30) .. "\")"
    end
    return true
end

local function uniqueTimelineName(project, base)
    local names = {}
    for i = 1, call(project, "GetTimelineCount") or 0 do
        names[call(call(project, "GetTimelineByIndex", i), "GetName") or ""] = true
    end
    local name, n = base, 2
    while names[name] do name = base .. " " .. n; n = n + 1 end
    return name
end

-- endFrame semantics of AppendToTimeline are calibrated on the first title:
-- if the clip comes out a frame long or short, the rest are corrected.
local function generate(ctx, plan, opts, log)
    local timeline, mediaPool = ctx.timeline, ctx.mediaPool
    local result = { created = 0, failed = 0, deleted = 0 }

    if #plan.deletions > 0 then
        if call(timeline, "DeleteClips", plan.deletions, false) then
            result.deleted = #plan.deletions
            log(string.format("Removed %d previously generated title(s).", result.deleted))
        else
            log("ERROR: could not remove previously generated titles; nothing was created.")
            result.failed = #plan.titles
            return result
        end
    end

    local count = call(timeline, "GetTrackCount", "video") or 0
    while count < plan.maxTrack do
        call(timeline, "AddTrack", "video")
        local now = call(timeline, "GetTrackCount", "video") or count
        if now <= count then
            log("ERROR: could not add video track V" .. (count + 1) .. "; nothing was created.")
            result.failed = #plan.titles
            return result
        end
        count = now
    end

    local endAdjust = 0
    local calibrated = false
    for _, title in ipairs(plan.titles) do
        local clip = title.clip
        local label = string.format("V%d %d \"%s\"", title.track, clip.start, shorten(title.marker.text, 30))
        local item, err

        for attempt = 1, 2 do
            local added = call(mediaPool, "AppendToTimeline", { {
                mediaPoolItem = opts.templateClip,
                startFrame = 0,
                endFrame = clip.dur - 1 + endAdjust,
                trackIndex = title.track,
                recordFrame = clip.start,
                mediaType = 1,
            } })
            item = type(added) == "table" and listOf(added)[1] or nil
            if not item then err = "AppendToTimeline returned nothing" break end

            local gotStart = toFrame(call(item, "GetStart"))
            local gotDur = toFrame(call(item, "GetDuration"))
            if gotStart ~= clip.start then
                call(timeline, "DeleteClips", { item }, false)
                item, err = nil, string.format("landed at frame %s instead of %d", tostring(gotStart), clip.start)
                break
            end
            if gotDur == clip.dur then calibrated = true break end
            call(timeline, "DeleteClips", { item }, false)
            item = nil
            if calibrated or attempt == 2 or not gotDur then
                err = string.format("came out %s frames long instead of %d (is the template long enough?)", tostring(gotDur), clip.dur)
                break
            end
            endAdjust = endAdjust + (clip.dur - gotDur)
        end

        if item then
            local styled, styleErr = styleTitle(item, title, opts)
            local frameId = toFrame(call(item, "GetLeftOffset")) or 0
            local tagged = call(item, "AddMarker", frameId, TAG_MARKER_COLOR, "Marker Title",
                "From \"" .. clip.name .. "\"", 1, title.tag)
            call(item, "SetClipColor", TAG_CLIP_COLOR)
            if styled then
                result.created = result.created + 1
                log("  OK    " .. label .. (tagged and "" or "  (warning: could not tag; a re-run may duplicate it)"))
            else
                result.failed = result.failed + 1
                log("  FAIL  " .. label .. ": " .. styleErr .. " (clip left on timeline)")
            end
        else
            result.failed = result.failed + 1
            log("  FAIL  " .. label .. ": " .. (err or "unknown error"))
            if title == plan.titles[1] and err and err:find("AppendToTimeline") then
                log("Stopping: the template clip cannot be placed. Check the template choice.")
                result.failed = #plan.titles
                return result
            end
        end
    end
    return result
end

-- ============================================================================
-- Window
-- ============================================================================

local function runUI(fusionApp)
    local ui = fusionApp.UIManager
    local disp = bmd.UIDispatcher(ui)
    local settings = loadSettings()
    local flags = IS_MACOS and { Tool = true } or { Window = true }

    local function row(label, ...)
        return ui:HGroup{ Weight = 0, ui:Label{ Text = label, Weight = 0.28 }, ... }
    end

    local win = disp:AddWindow({
        ID = "MarkerTitlesWin",
        WindowTitle = SCRIPT_NAME .. " " .. SCRIPT_VERSION,
        WindowFlags = flags,
        Geometry = { 200, 120, 720, 720 },
    }, ui:VGroup{
        row("Title template", ui:ComboBox{ ID = "Template" }, ui:Button{ ID = "RefreshTemplates", Text = "Refresh", Weight = 0 }),
        row("Text from", ui:ComboBox{ ID = "TextSource" }),
        row("Marker color", ui:ComboBox{ ID = "Color" }),
        row("First title track", ui:ComboBox{ ID = "FirstTrack" }),
        row("Earlier titles", ui:ComboBox{ ID = "Existing" }),
        row("Font / style", ui:LineEdit{ ID = "Font" }, ui:LineEdit{ ID = "Style" }),
        row("Size % / color",
            ui:SpinBox{ ID = "Size", Minimum = 1, Maximum = 50 },
            ui:LineEdit{ ID = "ColorHex", PlaceholderText = "#FFFFFF" }),
        row("Margin % / height %",
            ui:SpinBox{ ID = "Margin", Minimum = 0, Maximum = 45 },
            ui:SpinBox{ ID = "VPos", Minimum = 0, Maximum = 100 }),
        ui:HGroup{ Weight = 0,
            ui:CheckBox{ ID = "KeepStyle", Text = "Keep the template's font, size and color" },
            ui:CheckBox{ ID = "IncludeSource", Text = "Also use source (Media Pool) markers" },
        },
        ui:HGroup{ Weight = 0,
            ui:CheckBox{ ID = "SelectedOnly", Text = "Selected clips only (Resolve 21.0.4+)" },
            ui:CheckBox{ ID = "Duplicate", Text = "Work on a duplicate of the timeline" },
        },
        ui:TextEdit{ ID = "Report", ReadOnly = true, Weight = 1,
            Font = ui:Font{ Family = "Menlo", PixelSize = 11 } },
        ui:HGroup{ Weight = 0,
            ui:CheckBox{ ID = "DryRun", Text = "Dry run (no changes)" },
            ui:HGap(0, 1),
            ui:Button{ ID = "Scan", Text = "Scan / Preview" },
            ui:Button{ ID = "Generate", Text = "Generate Titles" },
            ui:Button{ ID = "Close", Text = "Close" },
        },
    })
    if IS_MACOS then pcall(function() win:SetAttribute("WA_MacAlwaysShowToolWindow", true) end) end
    local itm = win:GetItems()

    local templates = {}
    local armedSignature = nil

    local function setReport(lines) itm.Report.PlainText = table.concat(lines, "\n") end
    local function appendReport(s) itm.Report.PlainText = itm.Report.PlainText .. "\n" .. s end

    local function fillTemplates()
        itm.Template:Clear()
        local ctx = getContext()
        templates = ctx and findTemplates(ctx.mediaPool) or {}
        if #templates == 0 then
            itm.Template:AddItem("(none found: drag Text+ into the Media Pool, then Refresh)")
            return
        end
        local pick = 0
        for i, t in ipairs(templates) do
            itm.Template:AddItem(t.label .. (t.kind ~= "" and ("  [" .. t.kind .. "]") or ""))
            if t.label == settings.template then pick = i - 1 end
        end
        itm.Template.CurrentIndex = pick
    end

    itm.TextSource:AddItems(TEXT_SOURCES)
    itm.Color:AddItem("All colors")
    itm.Color:AddItems(MARKER_COLORS)
    itm.FirstTrack:AddItem("Auto (just above each clip)")
    for t = 2, 20 do itm.FirstTrack:AddItem("V" .. t .. " or higher") end
    itm.Existing:AddItems(EXISTING_MODES)

    itm.TextSource.CurrentIndex = settings.textSource
    itm.Color.CurrentIndex = 0
    for i, c in ipairs(MARKER_COLORS) do
        if c == settings.color then itm.Color.CurrentIndex = i end
    end
    itm.FirstTrack.CurrentIndex = settings.firstTrack
    itm.Existing.CurrentIndex = settings.existing
    itm.Font.Text, itm.Style.Text = settings.font, settings.style
    itm.Size.Value, itm.Margin.Value, itm.VPos.Value = settings.size, settings.margin, settings.vpos
    itm.ColorHex.Text = settings.colorHex
    itm.KeepStyle.Checked = settings.keepStyle
    itm.IncludeSource.Checked = settings.includeSource
    itm.SelectedOnly.Checked = settings.selectedOnly
    itm.Duplicate.Checked = settings.duplicate
    itm.DryRun.Checked = settings.dryRun
    fillTemplates()

    local function readOptions()
        local tpl = templates[(itm.Template.CurrentIndex or 0) + 1]
        local opts = {
            textSource = itm.TextSource.CurrentIndex,
            color = MARKER_COLORS[itm.Color.CurrentIndex or 0] or "All colors",
            firstTrack = itm.FirstTrack.CurrentIndex > 0 and (itm.FirstTrack.CurrentIndex + 1) or 0,
            existing = itm.Existing.CurrentIndex,
            font = itm.Font.Text, style = itm.Style.Text,
            size = itm.Size.Value, margin = itm.Margin.Value, vpos = itm.VPos.Value,
            colorHex = itm.ColorHex.Text, keepStyle = itm.KeepStyle.Checked,
            includeSource = itm.IncludeSource.Checked, selectedOnly = itm.SelectedOnly.Checked,
            duplicate = itm.Duplicate.Checked, dryRun = itm.DryRun.Checked,
            template = tpl and tpl.label or settings.template,
            templateClip = tpl and tpl.clip or nil,
        }
        for k in pairs(DEFAULTS) do settings[k] = opts[k] end
        settings.firstTrack = itm.FirstTrack.CurrentIndex
        saveSettings(settings)
        return opts
    end

    local function signature(plan, opts)
        local parts = { plan.timelineName, #plan.titles, #plan.deletions, opts.template, tostring(opts.duplicate) }
        for _, t in ipairs(plan.titles) do parts[#parts + 1] = t.tag .. "@" .. t.track end
        return table.concat(parts, ";")
    end

    local function guarded(fn)
        return function(ev)
            local ok, err = pcall(fn, ev)
            if not ok then
                armedSignature = nil
                itm.Generate.Text = "Generate Titles"
                appendReport("\nUNEXPECTED ERROR: " .. tostring(err))
            end
        end
    end

    local function scan()
        local ctx, err = getContext()
        if not ctx then setReport({ "ERROR: " .. err }) return nil end
        local opts = readOptions()
        local plan = buildPlan(ctx, opts)
        setReport(describePlan(plan, opts, ctx))
        return ctx, plan, opts
    end

    win.On.Scan.Clicked = guarded(function()
        armedSignature = nil
        itm.Generate.Text = "Generate Titles"
        scan()
    end)

    win.On.RefreshTemplates.Clicked = guarded(function() fillTemplates() end)

    win.On.Generate.Clicked = guarded(function()
        local ctx, plan, opts = scan()
        if not ctx then return end
        if opts.dryRun then
            armedSignature = nil
            appendReport("Dry run: nothing was changed. Untick \"Dry run\" to generate.")
            return
        end
        if #plan.titles == 0 then appendReport("Nothing to create.") return end
        if not opts.templateClip then
            appendReport("No title template selected. Drag Text+ from Effects > Titles into the Media Pool, click Refresh, then try again.")
            return
        end

        local sig = signature(plan, opts)
        if armedSignature ~= sig then
            armedSignature = sig
            itm.Generate.Text = string.format("Confirm: create %d", #plan.titles)
            appendReport(string.format("Ready to create %d title(s)%s on %s.\nClick \"Confirm\" to proceed, or change anything to cancel.",
                #plan.titles, #plan.deletions > 0 and string.format(" and replace %d", #plan.deletions) or "",
                opts.duplicate and "a DUPLICATE of this timeline" or "THIS timeline"))
            return
        end
        armedSignature = nil
        itm.Generate.Text = "Generate Titles"

        if opts.duplicate then
            local newName = uniqueTimelineName(ctx.project, plan.timelineName .. " (MarkerTitler)")
            local copy = call(ctx.timeline, "DuplicateTimeline", newName)
            if not copy or not call(ctx.project, "SetCurrentTimeline", copy) then
                appendReport("ERROR: could not duplicate the timeline. Nothing was changed.")
                return
            end
            ctx.timeline = copy
            plan = buildPlan(ctx, opts)
            appendReport("Working on duplicate timeline: " .. newName)
        end

        appendReport("\nGENERATING")
        local result = generate(ctx, plan, opts, appendReport)
        appendReport(string.format("\nDONE: %d created, %d failed, %d skipped%s.",
            result.created, result.failed, #plan.skipped,
            result.deleted > 0 and string.format(", %d replaced", result.deleted) or ""))
    end)

    win.On.Close.Clicked = function() disp:ExitLoop() end
    win.On.MarkerTitlesWin.Close = function() disp:ExitLoop() end

    setReport({
        SCRIPT_NAME .. " " .. SCRIPT_VERSION,
        "",
        "1. Drag Text+ from Effects > Titles into the Media Pool (once per project),",
        "   then click Refresh and pick it as the title template.",
        "2. Click Scan / Preview to see what will be created.",
        "3. Untick Dry run, click Generate Titles, then Confirm.",
    })
    win:Show()
    disp:RunLoop()
    win:Hide()
end

-- Allow the planning code to be loaded without a UI (used by the offline tests).
if MARKER_TITLES_TEST then
    return { buildPlan = buildPlan, describePlan = describePlan, generate = generate,
             markerText = markerText, parseTag = parseTag, makeTag = makeTag, findTemplates = findTemplates }
end

-- From Workspace > Scripts the `fu` global is not always set (notably on the
-- Edit page), so get the Fusion object from Resolve itself.
local function getFusion()
    local ok, resolve = pcall(function() return Resolve and Resolve() end)
    if ok and resolve then
        local okF, f = pcall(function() return resolve:Fusion() end)
        if okF and f then return f end
    end
    return rawget(_G, "fu") or rawget(_G, "fusion") or rawget(_G, "app")
end

local fusionApp = getFusion()
if not (fusionApp and bmd) then
    print(SCRIPT_NAME .. ": could not reach Resolve's Fusion UI. Run this from Workspace > Scripts inside DaVinci Resolve.")
    return
end
local ok, err = pcall(runUI, fusionApp)
if not ok then
    print(SCRIPT_NAME .. " error: " .. tostring(err))
end
