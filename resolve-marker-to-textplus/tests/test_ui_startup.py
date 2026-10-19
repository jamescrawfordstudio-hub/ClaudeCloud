"""Start-up and Generate path through a fake UIManager (run: python3 tests/test_ui_startup.py)."""
import os, sys
from lupa import luajit21
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
lua = luajit21.LuaRuntime()
lua.execute('package.path = "tests/?.lua;" .. package.path')
lua.execute(r'''
local R = require("mock_resolve")
local function widget(spec)
  local w = spec or {}
  w.items = {}; w.CurrentIndex = w.CurrentIndex or 0; w.PlainText = ""
  function w:AddItem(x) table.insert(self.items, x) end
  function w:AddItems(t) for _, x in ipairs(t) do table.insert(self.items, x) end end
  function w:Clear() self.items = {} end
  return w
end
local all = {}
local ui = setmetatable({}, {__index = function(_, k) return function(self, spec)
    local w = widget(type(spec) == "table" and spec or {}); if w.ID then all[w.ID] = w end; return w end end})
local win = { On = setmetatable({}, {__index = function(t, k) local v = {} rawset(t, k, v) return v end}) }
function win:GetItems() return all end
function win:Show() end function win:Hide() end function win:SetAttribute() end
local disp = { AddWindow = function() return win end, RunLoop = function() SHOWN = true end, ExitLoop = function() end }
bmd = { UIDispatcher = function() return disp end }
local template = { GetName = function() return "Text+" end, GetClipProperty = function() return "Fusion Title" end }
local clip = R.newItem({ name = "A001", start = 1000, dur = 100, left = 0, markers = {
    [10] = { name = "Hi", note = "", color = "Blue" }, [20] = { name = "There", note = "", color = "Blue" } } })
TL = R.newTimeline("Edit 1", { { clip } })
local mp = R.newMediaPool(function() return TL end, template)
local project = { GetName = function() return "P" end, GetCurrentTimeline = function() return TL end,
                  GetMediaPool = function() return mp end }
local resolveObj = { Fusion = function() return { UIManager = ui } end, GetVersionString = function() return "20.3.2" end,
                     GetProjectManager = function() return { GetCurrentProject = function() return project end } end }
Resolve = function() return resolveObj end
WIN = win
''')
lua.execute(open("MarkerTitler.lua").read())
assert lua.eval("SHOWN"), "window did not open"
lua.execute("local i = WIN:GetItems(); i.DryRun.Checked = false; i.Duplicate.Checked = false; i.Color.CurrentIndex = 0")
lua.execute("WIN.On.Generate.Clicked({})")
lua.execute("WIN.On.Generate.Clicked({})")
report = lua.eval("WIN:GetItems().Report.PlainText")
print(report)
assert "DONE: 2 created, 0 failed" in report, "generate did not create 2 titles"
print("\nUI STARTUP TEST PASSED")
