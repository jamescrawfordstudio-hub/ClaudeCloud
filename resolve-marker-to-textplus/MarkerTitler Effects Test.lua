--[[
    MarkerTitler Effects Test  (one-off, safe)

    Question: can a Text+ from the Effects library be dropped over a clip's exact
    in/out by script, without cutting or moving anything?

    It DUPLICATES the current timeline and works only on the copy
    ("<name> (Effects Test)"). Your original timeline is never touched.
    On the copy it locks every existing track, adds an empty track, sets In/Out
    to the first clip on V1, puts the playhead on the clip start and inserts
    Text+ from the Effects library. It then checks the title's start/length and
    whether any existing clip moved. Results go to the Console (Lua tab) and to
    ~/Desktop/MarkerTitler_Effects_Test.txt.
]]

local lines = {}
local function out(s) s = tostring(s) lines[#lines + 1] = s print(s) end
local function try(fn) local ok, r = pcall(fn) if ok then return r end return "ERROR " .. tostring(r) end
local function list(t)
    local o = {}
    if type(t) ~= "table" then return o end
    local keys = {}
    for k in pairs(t) do if type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do o[#o + 1] = t[k] end
    return o
end

local function finish()
    local path = (os.getenv("HOME") or ".") .. "/Desktop/MarkerTitler_Effects_Test.txt"
    local fh = io.open(path, "w")
    if fh then fh:write(table.concat(lines, "\n"), "\n") fh:close() print("Saved to " .. path) end
end

local resolve = Resolve()
local project = resolve:GetProjectManager():GetCurrentProject()
local source = project and project:GetCurrentTimeline()
out("Resolve " .. tostring(resolve:GetVersionString()) .. "   page: " .. tostring(resolve:GetCurrentPage()))
if not source then out("No timeline open.") finish() return end

-- Work on a copy only
local base = source:GetName() .. " (Effects Test)"
local name, n = base, 2
local existing = {}
for i = 1, project:GetTimelineCount() do existing[project:GetTimelineByIndex(i):GetName()] = true end
while existing[name] do name = base .. " " .. n n = n + 1 end
local tl = source:DuplicateTimeline(name)
if not tl or not project:SetCurrentTimeline(tl) then out("Could not duplicate the timeline; nothing done.") finish() return end
out("Working on duplicate: " .. name)

local fps = tonumber(tl:GetSetting("timelineFrameRate")) or 24
local tlStart = tl:GetStartFrame()
local function tc(frame)
    local r = math.floor(fps + 0.5)
    local f = frame
    local h = math.floor(f / (3600 * r)) f = f - h * 3600 * r
    local m = math.floor(f / (60 * r)) f = f - m * 60 * r
    local s = math.floor(f / r) f = f - s * r
    return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end
out(string.format("fps=%s  start frame=%d  drop frame=%s", tostring(fps), tlStart, tostring(tl:GetSetting("timelineDropFrameTimecode"))))

-- Snapshot every clip position, to detect cutting/rippling
local function snapshot()
    local snap = {}
    for _, kind in ipairs({ "video", "audio" }) do
        for t = 1, tl:GetTrackCount(kind) do
            for _, it in ipairs(list(tl:GetItemListInTrack(kind, t))) do
                snap[#snap + 1] = string.format("%s%d %s %s-%s", kind:sub(1, 1), t, tostring(it:GetName()), tostring(it:GetStart()), tostring(it:GetEnd()))
            end
        end
    end
    return snap
end

local clip = list(tl:GetItemListInTrack("video", 1))[1]
if not clip then out("No clip on V1 of the copy.") finish() return end
local s, e, d = clip:GetStart(), clip:GetEnd(), clip:GetDuration()
out(string.format("Target clip: %s  start=%s end=%s dur=%s", tostring(clip:GetName()), tostring(s), tostring(e), tostring(d)))

-- Lock every existing track
local locked = {}
for _, kind in ipairs({ "video", "audio", "subtitle" }) do
    for t = 1, tl:GetTrackCount(kind) do
        locked[#locked + 1] = { kind, t, tl:GetIsTrackLocked(kind, t) }
        try(function() return tl:SetTrackLock(kind, t, true) end)
    end
end
out("Locked existing tracks: " .. tostring(#locked) .. "  (V1 locked now: " .. tostring(tl:GetIsTrackLocked("video", 1)) .. ")")
out("Added empty track: " .. tostring(tl:AddTrack("video")) .. "  -> video tracks: " .. tostring(tl:GetTrackCount("video")))

local function attempt(label, useInOut)
    out("")
    out("== " .. label)
    local before = snapshot()
    if useInOut then
        local r1 = try(function() return tl:SetMarkInOut(s, e - 1, "all") end)
        out("SetMarkInOut(absolute) -> " .. tostring(r1))
        if r1 ~= true then
            local r2 = try(function() return tl:SetMarkInOut(s - tlStart, e - 1 - tlStart, "all") end)
            out("SetMarkInOut(relative) -> " .. tostring(r2))
        end
        local mio = try(function() return tl:GetMarkInOut() end)
        if type(mio) == "table" then
            local v = mio.video or mio.all or mio
            out("GetMarkInOut -> in=" .. tostring(v["in"]) .. " out=" .. tostring(v.out))
        else
            out("GetMarkInOut -> " .. tostring(mio))
        end
    else
        out("ClearMarkInOut -> " .. tostring(try(function() return tl:ClearMarkInOut("all") end)))
    end
    out("SetCurrentTimecode(" .. tc(s) .. ") -> " .. tostring(try(function() return tl:SetCurrentTimecode(tc(s)) end))
        .. "   now at " .. tostring(tl:GetCurrentTimecode()))
    local item = try(function() return tl:InsertFusionTitleIntoTimeline("Text+") end)
    if type(item) ~= "string" and item then
        local tt = try(function() return item:GetTrackTypeAndIndex() end)
        local track = type(tt) == "table" and tt[2] or tt
        local is, idur = item:GetStart(), item:GetDuration()
        out(string.format("Inserted Text+: start=%s dur=%s track=V%s   wanted start=%s dur=%s  -> %s",
            tostring(is), tostring(idur), tostring(track), tostring(s), tostring(d),
            (is == s and idur == d) and "EXACT MATCH" or "no match"))
        out("  GetMediaPoolItem -> " .. tostring(try(function() return item:GetMediaPoolItem() end)))
        local comp = try(function() return item:GetFusionCompByIndex(1) end)
        out("  has Fusion comp -> " .. tostring(type(comp) ~= "string" and comp ~= nil))
    else
        out("InsertFusionTitleIntoTimeline -> " .. tostring(item))
    end
    local after = snapshot()
    local moved = 0
    local lookup = {}
    for _, x in ipairs(after) do lookup[x] = true end
    for _, x in ipairs(before) do if not lookup[x] then moved = moved + 1 out("  CHANGED: " .. x) end end
    out("Existing clips changed/moved: " .. moved .. (moved == 0 and "  (nothing cut or rippled)" or "  <-- CUT/RIPPLE"))
    if type(item) ~= "string" and item then try(function() return tl:DeleteClips({ item }, false) end) end
end

attempt("A: In/Out set to the clip, playhead at clip start", true)
attempt("B: no In/Out, playhead at clip start", false)

-- Restore lock states on the copy
for _, l in ipairs(locked) do try(function() return tl:SetTrackLock(l[1], l[2], l[3] == true) end) end
try(function() return tl:ClearMarkInOut("all") end)
out("")
out("Done. Inspect the copy '" .. name .. "', then delete it. Your original timeline was not touched.")
finish()
