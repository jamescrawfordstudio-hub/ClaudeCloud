#!/bin/sh
# Runs the offline tests under LuaJIT (the Lua Resolve uses). Needs: pip install lupa
cd "$(dirname "$0")/.." && python3 -c '
from lupa import luajit21
lua = luajit21.LuaRuntime()
lua.execute("arg = {\"MarkerTitler.lua\", \"tests\"}")
lua.execute(open("tests/test_marker_titles.lua").read().replace("os.exit(", "return ("))
'
python3 tests/test_ui_startup.py | tail -1
