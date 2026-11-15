#!/usr/bin/env bash
# An internal key is not a name (OUTDATED DOCS/production/design/UI.md, acceptance 6).
# A row, tooltip or detail line may fall back to a word, never to an id: the
# 2026-11-04 captures showed a raw survivor key reaching the page because a
# display expression was written as `name or base.id`.
#
# THE RULE, AND WHAT IT ALLOWS
#   Scope: every .lua file under mod/42/media/lua, discovered from the tree.
#   Refused, shape 1: a display expression that falls back to an id, i.e.
#     `... name ... or <something>.id`.
#   Refused, shape 2: a label assignment whose built text ends in a bare id,
#     i.e. `something.name = ... .. tostring(<something>.id)`.
#   Allowed: ids used as keys, comparisons, lookups, storage and developer log
#     lines. Those are not display, and the two patterns above cannot match them
#     by accident because they require a name/label slot or a `.name =` target.
#   The patterns are deliberately narrow. Widening this gate to "any tostring of
#   an id" flagged 26 files of composite keys and debug output, which would have
#   forced either a filename allowlist or a rule nobody could keep.
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
pattern = re.compile('\\b(name|label|title|text)[\\t\\n\\v\\f\\r ]*=[^=]*[^=.][\\t\\n\\v\\f\\r ]or[\\t\\n\\v\\f\\r ]+[A-Za-z_][A-Za-z0-9_.]*\\.id\\b|\\.name[\\t\\n\\v\\f\\r ]*=.*\\.\\.[\\t\\n\\v\\f\\r ]*tostring\\([A-Za-z_][A-Za-z0-9_.]*\\.id\\)', re.ASCII)
status = 0
for path in files:
    with open(path, "rb") as source:
        lines = source.read().decode("latin-1").split("\n")
    hits = [(i, line) for i, line in enumerate(lines, 1) if pattern.search(line)]
    if hits:
        print("FAIL %s: a display line falls back to an internal id" % path)
        for number, line in hits[:5]:
            print("%d:%s" % (number, line))
        status = 1
if not status:
    print("PASS: no display line under %s falls back to an internal id" % root)
sys.exit(status)
PY
