#!/usr/bin/env bash
# One scroller per page, and no scrollable list nested inside it
# (OUTDATED DOCS/production/design/UI.md, acceptance 4).
#
# The audit found this broken twice: Missions and World were mounted with
# `addView` but never `UILayout.bindView`, so they had no page scroller at all,
# and World created its two lists at fixed pixel heights inside the bounded page.
# Hand-written cites did not catch either, so the rule is now a gate.
#
# THE RULE, AND WHAT IT ALLOWS
#   Scope: every .lua under mod/42/media/lua, discovered from the tree.
#   Rule 1: any `addView(..., self.foo)` must be followed, within three lines, by
#     `UILayout.bindView(self.foo)`, or the page has no page scroller.
#   Rule 2: every ISScrollingListBox created inside a mounted page class must be
#     given its height by `:setHeight(UILayout.stackHeight(...))` somewhere in
#     that class, i.e. measured from its rows rather than a fixed pixel height.
#   Allowed: a list in a window that is not a notebook page (a standalone window
#     owns its own single scroller), and a list whose height IS the stack height.
#   Nothing is skipped by filename: a new page added to this file is checked
#   because it is mounted, not because someone remembered it.
set -u
cd "$(dirname "$0")/.." || exit 2
exec python - "mod/42/media/lua" <<'PY'
import glob, io, re, sys

root = sys.argv[1]
files = sorted(glob.glob(root + "/**/*.lua", recursive=True))
if not files:
    print("FAIL: discovery found no Lua files under " + root)
    sys.exit(2)

def lines_of(path):
    return io.open(path, encoding="utf-8", errors="replace", newline="").read().splitlines()

problems = []
classes = {}

for path in files:
    lines = lines_of(path)
    for index, line in enumerate(lines):
        match = re.search(r':addView\(\s*"[^"]*"\s*,\s*(self\.\w+)\s*\)', line)
        if not match:
            continue
        view = match.group(1)
        window = "\n".join(lines[index:index + 3])
        if not re.search(r'bindView\(\s*' + re.escape(view) + r'\s*\)', window):
            problems.append((path, index + 1,
                "page %s is mounted without UILayout.bindView, so it has no page scroller" % view))
        created = re.search(re.escape(view) + r'\s*=\s*(\w+):new', line)
        if created:
            classes[created.group(1)] = path

for name, path in sorted(classes.items()):
    lines = lines_of(path)
    start = None
    for index, line in enumerate(lines):
        if re.search(r'local\s+' + name + r'\s*=\s*ISPanelJoypad:derive', line):
            start = index
            break
    if start is None:
        problems.append((path, 1, "mounted page class %s has no definition" % name))
        continue
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if re.search(r'^local\s+\w+\s*=\s*ISPanelJoypad:derive', lines[index]):
            end = index
            break
    body = "\n".join(lines[start:end])
    for index in range(start, end):
        created = re.search(r'(self\.\w+|[A-Za-z_]\w*)\s*=\s*ISScrollingListBox:new', lines[index])
        if not created:
            continue
        variable = created.group(1)
        measured = False
        for call in re.finditer(re.escape(variable) + r'\s*:\s*setHeight\(\s*([^)]*)\)', body):
            argument = call.group(1).strip()
            if "UILayout.stackHeight" in argument:
                measured = True
                break
            # A page may measure once into a local (zoneH = stackHeight(...)) and
            # then assign it; that is still measured, not a fixed height.
            if re.search(r'(^|[\s(])' + re.escape(argument) + r'\s*=\s*UILayout\.stackHeight', body):
                measured = True
                break
        if not measured:
            problems.append((path, index + 1,
                "list %s is created at a fixed height and never sized from Layout.stackHeight"
                % variable))

for path, line, message in problems:
    print("FAIL %s:%d: %s" % (path, line, message))
if problems:
    sys.exit(1)
print("PASS: %d mounted page(s) use the page scroller and no nested fixed-height list" % len(classes))
PY
