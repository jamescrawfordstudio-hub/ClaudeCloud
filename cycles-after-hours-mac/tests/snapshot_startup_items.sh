#!/usr/bin/env bash
# Lists everything macOS can start automatically (launch agents/daemons,
# helper tools, cron jobs, login items), so a before/after diff shows whether
# a test left anything behind. Missing folders are reported, not errors.

for dir in ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons \
  /Library/PrivilegedHelperTools /Library/StartupItems; do
  echo "== $dir"
  ls -la "$dir" 2>&1 || true
done
echo "== crontab"
crontab -l 2>&1 || true
echo "== login and background items mentioning Blender"
sudo -n sfltool dumpbtm 2>/dev/null | grep -i blender || echo "(none)"
