-- Minimal fake of the Resolve API surface MarkerTitler uses.
-- AppendToTimeline treats endFrame as EXCLUSIVE so the calibration path runs.
local M = {}
local uidSeq = 0
local function newItem(t)
    uidSeq = uidSeq + 1
    t.uid = "uid-" .. uidSeq
    t.markers = t.markers or {}
    function t:GetName() return self.name end
    function t:GetStart() return self.start end
    function t:GetEnd() return self.start + self.dur end
    function t:GetDuration() return self.dur end
    function t:GetLeftOffset() return self.left end
    function t:GetUniqueId() return self.uid end
    function t:GetMarkers()
        local out = { __flags = 1024 }
        for k, v in pairs(self.markers) do out[k] = v end
        return out
    end
    function t:GetMediaPoolItem() return self.mpi end
    function t:AddMarker(f, color, name, note, dur, cd)
        if self.markers[f] then return false end
        self.markers[f] = { color = color, name = name, note = note, duration = dur, customData = cd }
        return true
    end
    function t:SetClipColor(c) self.clipColor = c return true end
    function t:GetFusionCompByIndex(i) return self.comp end
    return t
end
M.newItem = newItem

function M.newTimeline(name, tracks)
    local tl = { name = name, tracks = tracks }
    function tl:GetName() return self.name end
    function tl:GetTrackCount(kind) return kind == "video" and #self.tracks or 0 end
    function tl:GetIsTrackLocked(kind, i) return self.tracks[i].locked == true end
    function tl:GetItemListInTrack(kind, i)
        local out = { __flags = 1024 }  -- real Resolve lists carry string keys too
        for k, v in ipairs(self.tracks[i]) do out[k] = v end
        return out
    end
    function tl:AddTrack(kind) table.insert(self.tracks, {}) return true end
    function tl:DeleteClips(items)
        for _, it in ipairs(items) do
            for _, tr in ipairs(self.tracks) do
                for k = #tr, 1, -1 do if tr[k] == it then table.remove(tr, k) end end
            end
        end
        return true
    end
    return tl
end

function M.newTextPlus()
    local tool = { inputs = {} }
    function tool:SetInput(k, v) self.inputs[k] = v end
    function tool:GetInput(k) return self.inputs[k] end
    local comp = { tool = tool }
    function comp:GetToolList(sel, id) if id == "TextPlus" then return { [1] = tool, __flags = 1024 } end return {} end
    return comp
end

function M.newMediaPool(getTimeline, template)
    local mp = {}
    function mp:AppendToTimeline(list)
        local info = list[1]
        local tpl = info.mediaPoolItem
        if tpl.frames and (info.endFrame - info.startFrame) > tpl.frames then return { __flags = 1024 } end
        if M.rejectMediaType and info.mediaType ~= nil then return { __flags = 1024 } end
        if M.refuseTracks and M.refuseTracks[info.trackIndex] then return { __flags = 1024 } end
        local tl = getTimeline()
        local tr = tl.tracks[info.trackIndex]
        if not tr then return {} end
        local it = newItem({ name = "Text+", start = info.recordFrame, dur = info.endFrame - info.startFrame,
                              left = info.startFrame, mpi = info.mediaPoolItem, comp = M.newTextPlus() })
        table.insert(tr, it)
        return { it, __flags = 1024 }
    end
    function mp:GetRootFolder()
        return { GetClipList = function() return { template, __flags = 1024 } end, GetSubFolderList = function() return {} end }
    end
    return mp
end
return M
