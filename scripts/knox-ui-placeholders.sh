#!/usr/bin/env bash
# A missing value must say what is missing (OUTDATED DOCS/production/design/UI.md,
# acceptance 1 and 8). A lone `?` was used as the fallback for a survivor with
# no initials, a person with no name and an area with no coordinates; in game it
# reads exactly like the missing-glyph box the ASCII sweep removed.
#
# THE RULE, AND WHAT IT ALLOWS
#   Scope: every .lua file under mod/42/media/lua, discovered from the tree.
#   Refused: `or "?"` - a question mark used as the value of a missing field.
#   Allowed: a question mark that is part of a sentence ("Send the squad?"), a
#     Lua pattern such as "%?" or "[?]", and any diagnostic that is not drawn.
#     Those are prose and matching, not placeholders, so the pattern is narrow on
#     purpose: it matches the fallback shape, not the character.
set -u
cd "$(dirname "$0")/.." || exit 2
exec python - "${1:-mod/42/media/lua}" <<'PY'
import os, re, stat, sys

root = sys.argv[1]
files = sorted(os.path.join(directory, name).replace(os.sep, "/")
    for directory, _, names in os.walk(root)
    for name in names if name.endswith(".lua")
    and stat.S_ISREG(os.lstat(os.path.join(directory, name)).st_mode))
if not files:
    print("FAIL: discovery found no Lua files under " + root)
    sys.exit(2)
pattern = re.compile('or[\\t\\n\\v\\f\\r ]*"\\?"', re.ASCII)
status = 0
for path in files:
    with open(path, "rb") as source:
        lines = source.read().decode("latin-1").split("\n")
    hits = [(i, line) for i, line in enumerate(lines, 1) if pattern.search(line)]
    if hits:
        print("FAIL %s: a missing value falls back to a question mark" % path)
        for number, line in hits[:5]:
            print("%d:%s" % (number, line))
        status = 1
if not status:
    print("PASS: no file under %s uses a question mark as a value" % root)
sys.exit(status)
PY
