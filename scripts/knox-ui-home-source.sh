#!/usr/bin/env bash
# Stores & Stock and Base & Work must agree about whether the player has a home
# (OUTDATED DOCS/production/design/UI.md, acceptance 5).
#
# The pages once disagreed because each resolved the question its own way: one
# read the owner's base list, the other a base id through the persistence layer.
# Both now call notebookBase, and this gate keeps them doing it.
#
# THE RULE, AND WHAT IT ALLOWS
#   Scope: every .lua under mod/42/media/lua, discovered from the tree.
#   Rule 1: BaseView:selectedBase and StoresView:selectedBase must each call
#     notebookBase, the single resolution of home existence.
#   Rule 2: neither may call KnoxPersistence.getBase or getBasesForOwner itself;
#     that is a second resolution of the same question.
#   Rule 3: the two bodies must be identical once comments, whitespace and the
#     class name are removed, so neither page can read a different field.
#   Allowed: any other page reading a base id for its own display - the rule is
#     about the existence question, not about every lookup.
set -u
cd "$(dirname "$0")/.." || exit 2
exec python - "mod/42/media/lua" <<'PY'
import glob, io, re, sys

root = sys.argv[1]
files = sorted(glob.glob(root + "/**/*.lua", recursive=True))
if not files:
    print("FAIL: discovery found no Lua files under " + root)
    sys.exit(2)

want = ("BaseView", "StoresView")
bodies = {}
problems = []

for path in files:
    lines = io.open(path, encoding="utf-8", errors="replace", newline="").read().splitlines()
    for index, line in enumerate(lines):
        match = re.match(r'\s*function\s+(\w+)\s*:\s*selectedBase\s*\(', line)
        if not match or match.group(1) not in want:
            continue
        name = match.group(1)
        end = len(lines)
        for scan in range(index + 1, len(lines)):
            if re.match(r'\s*function\s', lines[scan]):
                end = scan
                break
        bodies[name] = (path, index + 1, "\n".join(lines[index:end]))

for name in want:
    if name not in bodies:
        problems.append((root, 1, "%s has no selectedBase resolution" % name))
        continue
    path, line, body = bodies[name]
    if "notebookBase(" not in body:
        problems.append((path, line,
            "%s:selectedBase does not use the shared notebookBase resolution" % name))
    for forbidden in ("KnoxPersistence.getBase(", "KnoxPersistence.getBasesForOwner"):
        if forbidden in body:
            problems.append((path, line,
                "%s:selectedBase re-derives home existence through %s" % (name, forbidden)))

def normalise(body):
    stripped = re.sub(r'--[^\n]*', '', body)
    stripped = re.sub(r'function\s+\w+\s*:\s*selectedBase', 'function :selectedBase', stripped)
    return re.sub(r'\s+', ' ', stripped).strip()

if len(bodies) == len(want):
    first, second = want
    if normalise(bodies[first][2]) != normalise(bodies[second][2]):
        path, line, _ = bodies[second]
        problems.append((path, line,
            "%s:selectedBase no longer matches %s:selectedBase, so the two pages can disagree"
            % (second, first)))

for path, line, message in problems:
    print("FAIL %s:%d: %s" % (path, line, message))
if problems:
    sys.exit(1)
print("PASS: Base & Work and Stores & Stock resolve home existence through one shared call")
PY
