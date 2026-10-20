-- Offline test: luajit (or lua5.1+) tests/test_marker_titles.lua <path to MarkerTitler.lua> <tests dir>
local scriptPath, testsDir = arg[1], arg[2]
package.path = testsDir .. "/?.lua;" .. package.path
local R = require("mock_resolve")
MARKER_TITLES_TEST = true
local MT = dofile(scriptPath)

local failures = 0
local function check(cond, msg)
    if cond then print("ok   " .. msg) else failures = failures + 1 print("FAIL " .. msg) end
end

local template = { GetName = function() return "Text+" end,
                   GetClipProperty = function(self, k) return "Fusion Title" end }
local clipA = R.newItem({ name = "A001", start = 1000, dur = 100, left = 10, markers = {
    [15] = { name = "One", note = "n1", color = "Blue" },
    [20] = { name = "Two", note = "", color = "Blue" },
    [30] = { name = "Three", note = "", color = "Blue" },
    [5] = { name = "Trimmed", note = "", color = "Blue" },
    [50] = { name = "  ", note = "", color = "Blue" },
} })
local clipB = R.newItem({ name = "B001", start = 1200, dur = 50, left = 0, markers = {
    [0] = { name = "", note = "Solo note", color = "Red" } } })
local blocker = R.newItem({ name = "Blocker", start = 1040, dur = 20, left = 0 })
local tl = R.newTimeline("Edit 1", { { clipA, clipB }, { blocker } })
local ctx = { timeline = tl, version = "test", project = {} }
ctx.mediaPool = R.newMediaPool(function() return ctx.timeline end, template)

local opts = { textSource = 2, color = "All colors", firstTrack = 0, existing = 0, includeSource = false,
               selectedOnly = false, margin = 6, vpos = 12, size = 6, font = "Open Sans", style = "Bold",
               colorHex = "#FFFFFF", keepStyle = false, templateClip = template }

local plan = MT.buildPlan(ctx, opts)
print(table.concat(MT.describePlan(plan, opts, ctx), "\n"))
check(#plan.titles == 4, "4 titles planned")
check(#plan.skipped == 2, "trimmed + empty markers skipped")
local byText = {}
for _, t in ipairs(plan.titles) do byText[t.marker.text] = t end
check(byText.One.track == 3 and byText.One.side == "left", "One -> V3 left (V2 blocked)")
check(byText.Two.track == 4 and byText.Two.side == "right", "Two -> V4 right")
check(byText.Three.track == 5 and byText.Three.side == "left", "Three -> V5 left")
check(byText["Solo note"].track == 2, "Solo note (note fallback) -> V2")
check(plan.maxTrack == 5, "needs tracks up to V5")

local logs = {}
local res = MT.generate(ctx, plan, opts, function(s) logs[#logs + 1] = s end)
print(table.concat(logs, "\n"))
check(res.created == 4 and res.failed == 0, "4 created, 0 failed")
check(#tl.tracks == 5, "3 tracks added")
local t3 = tl.tracks[3][1]
check(t3 and t3.start == 1000 and t3.dur == 100, "V3 title spans clip exactly (after calibration)")
check(t3.comp.tool.inputs.StyledText == "One", "V3 text set")
check(t3.comp.tool.inputs.HorizontalJustificationNew == 0, "left justified")
check(tl.tracks[4][1].comp.tool.inputs.HorizontalJustificationNew == 2, "right justified")
check(tl.tracks[4][1].comp.tool.inputs.Center[1] == 0.94, "right title centered at 1 - margin")
check(#clipA.markers == nil or clipA.markers[15].customData == nil, "source markers untouched")
check(#tl.tracks[1] == 2 and #tl.tracks[2] == 2, "V1 untouched; V2 holds blocker + one title")

local plan2 = MT.buildPlan(ctx, opts)
check(#plan2.titles == 0 and plan2.existingCount == 4, "re-run: nothing new, 4 existing detected")
opts.existing = 1
local plan3 = MT.buildPlan(ctx, opts)
check(#plan3.titles == 4 and #plan3.deletions == 4, "regenerate: 4 replaced")
local tracksBefore = {}
for i, t in ipairs(plan3.titles) do tracksBefore[t.marker.text] = t.track end
check(tracksBefore.One == 3 and tracksBefore["Solo note"] == 2, "regenerate reuses freed slots")
MT.generate(ctx, plan3, opts, function() end)
local total = 0
for i = 2, #tl.tracks do total = total + #tl.tracks[i] end
check(total == 5, "after regenerate still 4 titles + blocker")

opts.existing, opts.color = 0, "Red"
for i = 2, #tl.tracks do tl.tracks[i] = (i == 2) and { blocker } or {} end
local plan4 = MT.buildPlan(ctx, opts)
check(#plan4.titles == 1 and plan4.titles[1].marker.text == "Solo note", "color filter Red -> only Solo")

-- Resolve refuses a template shorter than the clip: diagnose, create nothing
local short = { frames = 120, GetName = function() return "Text+" end,
    GetClipProperty = function(self, k) if k == "Frames" then return tostring(self.frames) end return "Fusion Title" end }
local tlS = R.newTimeline("Short", { { R.newItem({ name = "Long", start = 0, dur = 1870, left = 0,
    markers = { [5] = { name = "Long one", note = "", color = "Blue" } } }) } })
local ctxS = { timeline = tlS, version = "test", project = {} }
ctxS.mediaPool = R.newMediaPool(function() return tlS end, short)
opts.color, opts.existing, opts.templateClip = "All colors", 0, short
local planS = MT.buildPlan(ctxS, opts)
local logS = {}
local resS = MT.generate(ctxS, planS, opts, function(s) logS[#logS + 1] = s end)
local textS = table.concat(logS, "\n")
check(resS.created == 0 and textS:find("refused", 1, true) ~= nil, "too-short template: nothing created, reported")
local stray = 0
for i = 2, #tlS.tracks do stray = stray + #tlS.tracks[i] end
check(stray == 0, "no stray clips left after refusal")

-- Builds that reject mediaType: falls back to placing without it
R.rejectMediaType = true
local tlM = R.newTimeline("MT", { { R.newItem({ name = "C", start = 0, dur = 48, left = 0,
    markers = { [1] = { name = "x", note = "", color = "Blue" } } }) } })
local ctxM = { timeline = tlM, version = "test", project = {} }
ctxM.mediaPool = R.newMediaPool(function() return tlM end, template)
opts.templateClip = template
local resM = MT.generate(ctxM, MT.buildPlan(ctxM, opts), opts, function() end)
check(resM.created == 1 and tlM.tracks[2][1].dur == 48, "mediaType fallback works")
R.rejectMediaType = false

-- A track Resolve refuses (e.g. locked without the API saying so): titles move
-- to new empty tracks, still above one another, source clips untouched
R.refuseTracks = { [2] = true }
local src = R.newItem({ name = "S", start = 500, dur = 60, left = 0, markers = {
    [1] = { name = "a", note = "", color = "Blue" }, [2] = { name = "b", note = "", color = "Blue" } } })
local tlR = R.newTimeline("R", { { src }, {} })
local ctxR = { timeline = tlR, version = "test", project = {} }
ctxR.mediaPool = R.newMediaPool(function() return tlR end, template)
local logR = {}
local planR = MT.buildPlan(ctxR, opts)
check(planR.titles[1].track == 2 and planR.titles[2].track == 3, "planned V2, V3")
local resR = MT.generate(ctxR, planR, opts, function(s) logR[#logR + 1] = s end)
print(table.concat(logR, "\n"))
check(resR.created == 2, "both titles created despite refused V2")
check(#tlR.tracks[2] == 0, "nothing on refused V2")
local onA = tlR.tracks[3][1] and tlR.tracks[3][1].comp.tool.inputs.StyledText
local higher
for i = 4, #tlR.tracks do if tlR.tracks[i][1] then higher = tlR.tracks[i][1].comp.tool.inputs.StyledText end end
check(onA == nil or higher ~= nil, "titles stay on separate tracks")
check(src.start == 500 and #tlR.tracks[1] == 1, "source clip untouched")
R.refuseTracks = nil

local mk = { name = "Title", note = "Sub" }
check(MT.markerText(mk, 4) == "Title\nSub", "name (new line) note")
check(MT.markerText({ name = "Only", note = "" }, 4) == "Only", "new line option with empty note")
print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURE(S)"))
os.exit(failures == 0 and 0 or 1)
