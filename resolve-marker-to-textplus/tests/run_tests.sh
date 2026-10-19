#!/bin/sh
# Runs the offline tests under LuaJIT (the Lua Resolve uses). Needs: pip install lupa
cd "$(dirname "$0")/.." && python3 -c '
from lupa import luajit21
lua = luajit21.LuaRuntime()
lua.execute("arg = {\"Marker Titles.lua\", \"tests\"}")
lua.execute(open("tests/test_marker_titles.lua").read().replace("os.exit(", "return ("))
'
