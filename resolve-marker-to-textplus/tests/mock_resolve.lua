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
        if tpl and tpl.frames and (info.endFrame - info.startFrame) > tpl.frames then return { __flags = 1024 } end
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
    -- Media pool folders: root holds the template (if any); bins can be added,
    -- exported to a "file" (M.files) and imported back.
    local function folder(name, clips)
        local f = { name = name, clips = clips or {}, subs = {} }
        function f:GetName() return self.name end
        function f:GetClipList() local o = { __flags = 1024 } for i, c in ipairs(self.clips) do o[i] = c end return o end
        function f:GetSubFolderList() local o = { __flags = 1024 } for i, c in ipairs(self.subs) do o[i] = c end return o end
        return f
    end
    mp.root = folder("Master", template and { template } or {})
    function mp:GetRootFolder() return self.root end
    function mp:SetCurrentFolder(f) self.current = f return true end
    function mp:AddSubFolder(parent, name) local f = folder(name) table.insert(parent.subs, f) return f end
    function mp:MoveClips(clips, target)
        for _, c in ipairs(clips) do
            for k = #self.root.clips, 1, -1 do if self.root.clips[k] == c then table.remove(self.root.clips, k) end end
            table.insert(target.clips, c)
        end
        return true
    end
    function mp:ExportFolder(f, path)
        M.files = M.files or {}
        M.files[path] = f.clips[1]
        local fh = io.open(path, "w") fh:write("drb") fh:close()
        return true
    end
    function mp:ImportFolderFromFile(path)
        local clip = M.files and M.files[path]
        if not clip then return false end
        local f = self:AddSubFolder(self.current or self.root, "MarkerTitler")
        table.insert(f.clips, clip)
        return true
    end
    return mp
end
return M
