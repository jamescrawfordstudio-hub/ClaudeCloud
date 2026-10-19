--[[
    MarkerTitler Placement Test  (one-off diagnostic)

    Tries every way of placing the Media Pool title template on the current
    timeline and prints exactly what Resolve returns or raises. Anything it
    creates is deleted again straight away. Use it on a test timeline.

    Install next to MarkerTitler.lua, run from Workspace > Scripts, then copy
    the output from Workspace > Console (Lua tab) or the Desktop text file.
]]

local lines = {}
local function out(s) s = tostring(s) lines[#lines + 1] = s print(s) end

local function describe(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth > 1 then return "{...}" end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. describe(x, depth + 1) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Calls obj:method(...) and reports errors instead of hiding them.
local function try(obj, method, ...)
    local n, args = select("#", ...), { ... }
    local ok, a = pcall(function() return obj[method](obj, unpack(args, 1, n)) end)
    if not ok then return nil, "ERROR: " .. tostring(a) end
    return a, nil
end

local function firstItem(result)
    if type(result) ~= "table" then return nil end
    for k, v in pairs(result) do
        if type(k) == "number" and type(v) ~= "number" and type(v) ~= "string" then return v end
    end
    return nil
end

local resolve = Resolve()
local project = resolve:GetProjectManager():GetCurrentProject()
local timeline = project and project:GetCurrentTimeline()
local mediaPool = project and project:GetMediaPool()
out("Resolve " .. tostring(resolve:GetVersionString()))
if not timeline then out("No timeline open.") return end
out("Timeline: " .. tostring(timeline:GetName()) .. "   start frame: " .. tostring(timeline:GetStartFrame())
    .. "   video tracks: " .. tostring(timeline:GetTrackCount("video")))
out("Current page: " .. tostring(resolve:GetCurrentPage()))

-- Find the template the same way MarkerTitler does (prefer Fusion Title clips)
local template
local function walk(folder)
    for _, clip in pairs(folder:GetClipList() or {}) do
        if type(clip) ~= "number" and not template then
            local kind = clip:GetClipProperty("Type")
            if type(kind) == "string" and kind:lower():find("title") then template = clip end
        end
    end
    for _, sub in pairs(folder:GetSubFolderList() or {}) do
        if type(sub) ~= "number" and not template then walk(sub) end
    end
end
walk(mediaPool:GetRootFolder())
if not template then out("No Fusion Title clip found in the Media Pool.") return end
out("Template: " .. tostring(template:GetName()))
local props = template:GetClipProperty()
if type(props) == "table" then
    for _, k in ipairs({ "Type", "Start", "End", "Frames", "Duration", "FPS", "In", "Out", "Start TC", "End TC" }) do
        if props[k] ~= nil and props[k] ~= "" then out("  " .. k .. " = " .. tostring(props[k])) end
    end
end

-- Pick the record frame: the playhead's clip start on V1, else timeline start
local tlStart = timeline:GetStartFrame()
local v1 = timeline:GetItemListInTrack("video", 1) or {}
local record = tlStart
for _, it in pairs(v1) do
    if type(it) ~= "number" then record = it:GetStart() break end
end
local trackCount = timeline:GetTrackCount("video")
local freeTrack = trackCount + 1
out("Adding a temporary empty track V" .. freeTrack .. ": " .. tostring(timeline:AddTrack("video")))
out("")

local variants = {
    { "plain list {mpi}", function() return { template } end },
    { "clipInfo: mediaPoolItem only", function() return { { mediaPoolItem = template } } end },
    { "clipInfo: + startFrame/endFrame", function() return { { mediaPoolItem = template, startFrame = 0, endFrame = 47 } } end },
    { "clipInfo: + trackIndex", function() return { { mediaPoolItem = template, startFrame = 0, endFrame = 47, trackIndex = freeTrack } } end },
    { "clipInfo: + recordFrame", function() return { { mediaPoolItem = template, startFrame = 0, endFrame = 47, trackIndex = freeTrack, recordFrame = record } } end },
    { "clipInfo: + mediaType=1", function() return { { mediaPoolItem = template, startFrame = 0, endFrame = 47, trackIndex = freeTrack, recordFrame = record, mediaType = 1 } } end },
    { "clipInfo: start 1 / end 48", function() return { { mediaPoolItem = template, startFrame = 1, endFrame = 48, trackIndex = freeTrack, recordFrame = record } } end },
}

for i, v in ipairs(variants) do
    local result, err = try(mediaPool, "AppendToTimeline", v[2]())
    local item = firstItem(result)
    local line = string.format("%d. %-34s -> %s", i, v[1], err or describe(result))
    if item then
        local _, tt = pcall(function() return item:GetTrackTypeAndIndex() end)
        line = line .. string.format("   PLACED start=%s dur=%s track=%s",
            tostring(item:GetStart()), tostring(item:GetDuration()), describe(tt))
        local comp = item:GetFusionCompByIndex(1)
        local tools = comp and comp:GetToolList(false, "TextPlus")
        line = line .. "   TextPlus=" .. tostring(tools and firstItem(tools) ~= nil)
        timeline:DeleteClips({ item }, false)
    end
    out(line)
end

out("")
local playheadBefore = timeline:GetCurrentTimecode()
local inserted, insErr = try(timeline, "InsertFusionTitleIntoTimeline", "Text+")
if inserted and type(inserted) ~= "boolean" then
    local _, tt = pcall(function() return inserted:GetTrackTypeAndIndex() end)
    out(string.format("InsertFusionTitleIntoTimeline -> start=%s dur=%s track=%s (playhead %s)",
        tostring(inserted:GetStart()), tostring(inserted:GetDuration()), describe(tt), tostring(playheadBefore)))
    for _, m in ipairs({ "SetStart", "SetEnd", "SetDuration" }) do
        local ok, fn = pcall(function() return inserted[m] end)
        out("  TimelineItem." .. m .. " present: " .. tostring(ok and fn ~= nil))
    end
    timeline:DeleteClips({ inserted }, false)
else
    out("InsertFusionTitleIntoTimeline -> " .. tostring(insErr or describe(inserted)))
end

out("Removing temporary track V" .. freeTrack .. ": " .. tostring(timeline:DeleteTrack("video", freeTrack)))

local home = os.getenv("HOME") or "."
local path = home .. "/Desktop/MarkerTitler_Placement_Test.txt"
local fh = io.open(path, "w")
if fh then fh:write(table.concat(lines, "\n"), "\n") fh:close() print("Saved to " .. path) end
