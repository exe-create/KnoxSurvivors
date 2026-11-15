#!/usr/bin/env bash
# Player-facing text is printable ASCII (OUTDATED DOCS/production/design/UI.md).
# A glyph the runtime font cannot draw is not a separator - it is a hole in the
# sentence: the 2026-11-04 playtest read "Home Base ? 1 resident" because a
# middle dot reached the UI font.
#
# THE RULE, AND WHAT IT ALLOWS
#   Scope: every .lua file under mod/42/media/lua, discovered from the tree.
#   Allowed: bytes 0x20-0x7E (space through tilde), tab and the line endings.
#   Refused: everything else - em dash, middle dot, curly quotes, arrows,
#   non-breaking space, accented letters.
#
# Why the whole tree and not a list of files that "look like UI": a rendered
# string is composed by callers, not only by the file that draws it. Order
# labels, activity lines, kit shortages and captions are built in catalogue and
# view-model files that never call drawText themselves, and a shared or server
# file can seed the same text. Any list of "UI files" would therefore miss a
# file the moment a new one composes a label, and a filename allowlist would
# exempt the next file silently. Sweeping the tree is the only rule that cannot
# go stale.
#
# Comments are swept too. There is no safe way for a shell check to decide
# whether a byte sits inside a string or after "--", and a rule that needs that
# decision invites a parser bug to hide a rendered glyph. Prose punctuation is
# cheap to write in ASCII.
set -u
cd "$(dirname "$0")/.." || exit 2
exec python - "${1:-mod/42/media/lua}" <<'PY'
import os, stat, sys

root = sys.argv[1]
files = sorted(os.path.join(directory, name).replace(os.sep, "/")
    for directory, _, names in os.walk(root)
    for name in names if name.endswith(".lua")
    and stat.S_ISREG(os.lstat(os.path.join(directory, name)).st_mode))
if not files:
    print("FAIL: discovery found no Lua files under " + root)
    sys.exit(2)
status = 0
for path in files:
    with open(path, "rb") as source:
        lines = source.read().split(b"\n")
    hits = [(i, line) for i, line in enumerate(lines, 1)
        if any(byte not in (9, 13) and not 32 <= byte <= 126 for byte in line)]
    if hits:
        print("FAIL %s: %d line(s) contain a character outside printable ASCII" % (path, len(hits)))
        for number, line in hits[:5]:
            print("%d:%s" % (number, line.decode("utf-8", errors="replace")))
        status = 1
if not status:
    print("PASS: no non-ASCII in %d Lua files under %s" % (len(files), root))
sys.exit(status)
PY
