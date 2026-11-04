#!/usr/bin/env bash
# Fails when a spoken place line exists in KS_FactionCamps but not in the
# expected vocabulary fixture.
# Usage: bash scripts/knox-vocabulary.sh [project-root]
set -euo pipefail

root="${1:-.}"

# A Windows Store alias can answer `command -v python3` without being a real
# interpreter, so each candidate has to actually run before it is trusted.
PYBIN=""
for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import sys" >/dev/null 2>&1; then
        PYBIN="$candidate"
        break
    fi
done
if [ -z "$PYBIN" ]; then
    echo "vocabulary: no working python interpreter found"
    exit 2
fi

"$PYBIN" - "$root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
lua = root / "mod/42/media/lua/client/KS_FactionCamps.lua"
doc = root / "java/fixtures/place-vocabulary.md"

for path in (lua, doc):
    if not path.is_file():
        print("vocabulary: missing " + str(path))
        sys.exit(2)

source = lua.read_text(encoding="utf-8")
document = doc.read_text(encoding="utf-8")

start = source.find("local WARNING_LADDER")
end = source.find("function Camps.introductionFor")
if start < 0 or end < 0 or end <= start:
    print("vocabulary: cannot bound the speech region in KS_FactionCamps")
    sys.exit(2)
region = source[start:end]

# Sentences only. A quoted fragment sitting between Lua operators
# (" .. known .. ", " or disposition == ") is code, not copy.
sentences = set()
for match in re.finditer(r'"([^"\\]{10,})"', region):
    text = match.group(1)
    if not text[:1].isupper():
        continue
    if "=" in text or ".." in text:
        continue
    if not (text.endswith(".") or text.endswith(", ")):
        continue
    sentences.add(text)

missing = [text for text in sorted(sentences) if text not in document]
for text in missing:
    print("vocabulary: NOT DOCUMENTED: " + text)

rows = sum(1 for line in document.splitlines() if line.startswith("| `"))
print("vocabulary: source=%d documented-rows=%d missing=%d"
      % (len(sentences), rows, len(missing)))

if missing:
    sys.exit(1)
if len(sentences) < 20:
    print("vocabulary: only %d sentences found - the extraction is broken"
          % len(sentences))
    sys.exit(1)
print("VOCABULARY OK")
PY
