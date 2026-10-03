"""Summarize where Blender wrote files, from `sudo fs_usage -w -f filesys Blender`.

Usage: python3 summarize_fs_usage.py FS_USAGE_LOG HOME TMPDIR OUT_DIR

Prints write activity grouped by folder, and flags any folder outside the
places Blender is expected to write to.
"""

import collections
import os
import re
import sys

log_path, home, tmpdir, out_dir = sys.argv[1:5]
tmpdir = os.path.realpath(tmpdir).rstrip("/")
cachedir = re.sub(r"/T$", "/C", tmpdir)

WRITE_CALLS = {
    "mkdir", "mkdirat", "rename", "renameat", "renameatx_np", "unlink", "unlinkat", "rmdir",
    "truncate", "ftruncate", "write", "pwrite", "writev", "WrData", "clonefileat", "fclonefileat",
    "exchangedata", "chmod", "fchmod", "fchmodat", "setxattr", "fsetxattr", "removexattr",
    "chown", "fchown", "link", "linkat", "symlink", "symlinkat", "utimes", "futimes", "setattrlist",
}
LINE = re.compile(r"^\S+\s+(\S+)\s+(.*?)\s+\d+\.\d+( W)?\s+\S+$")

EXPECTED = [
    (f"{home}/Library/Application Support/Blender", "Blender settings folder"),
    (f"{home}/Library/Caches", "per-user caches"),
    (f"{home}/Library/Saved Application State/org.blenderfoundation.blender", "macOS window state"),
    (f"{home}/Library/Preferences/org.blenderfoundation.blender", "macOS app defaults"),
    (f"{home}/Library/HTTPStorages/org.blenderfoundation.blender", "macOS app storage"),
    ("/Applications/Blender Viewport Motion Blur.app", "its own app bundle (Python cache)"),
    ("/Applications/Blender.app", "official app bundle (Python cache)"),
    (tmpdir, "temporary folder"),
    (cachedir, "per-user cache folder (Metal shader cache)"),
    ("/private/tmp", "temporary folder"),
    ("/tmp", "temporary folder"),
    (os.path.realpath(out_dir), "test output folder"),
    ("/dev", "devices"),
]


def classify(path):
    real = path.replace("/private/var/", "/var/") if path.startswith("/private/var/") else path
    for prefix, why in EXPECTED:
        for candidate in (path, real):
            if candidate == prefix or candidate.startswith(prefix.rstrip("/") + "/"):
                return why
    return None


def bucket(path, depth=6):
    shown = path.replace(tmpdir, "$TMPDIR").replace(cachedir, "$CACHEDIR").replace(home, "~")
    return "/".join(shown.split("/")[:depth])


if not os.path.exists(log_path):
    sys.exit(f"No fs_usage log at {log_path}; the file monitor did not run.")

counts = collections.Counter()
unexpected = collections.Counter()
lines = 0
with open(log_path, errors="replace") as f:
    for raw in f:
        lines += 1
        match = LINE.match(raw.rstrip("\n"))
        if not match:
            continue
        call, rest = match.group(1), " " + match.group(2)
        base_call = call.split("[")[0]
        slash = rest.find(" /")
        if slash < 0:
            continue
        path = rest[slash + 1:].strip()
        flags = rest[:slash]
        # Disk-level records (WrData etc.) list the device before the file.
        if path.startswith("/dev/disk") and "  /" in path:
            path = path[path.index("  /") + 2:].strip()
        is_write = base_call in WRITE_CALLS or (
            base_call in ("open", "open_nocancel", "openat", "openat_nocancel") and re.search(r"\([^)]*[WCT][^)]*\)", flags))
        if not is_write:
            continue
        counts[bucket(path)] += 1
        if classify(path) is None:
            unexpected[bucket(path)] += 1

print(f"fs_usage lines read: {lines}, write operations by Blender: {sum(counts.values())}")
print("Top folders written:")
for folder, n in counts.most_common(30):
    print(f"  {n:7d}  {folder}")
if unexpected:
    print("Writes OUTSIDE the expected places:")
    for folder, n in unexpected.most_common(50):
        print(f"  {n:7d}  {folder}")
else:
    print("No writes outside the expected places.")
