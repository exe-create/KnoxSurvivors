#!/usr/bin/env bash
# Compare the staged Knox Survivors payload across the Workshop candidate,
# the local mods folder and the Workshop folder. Read-only.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
props="$root/local.properties"

if [[ ! -f "$props" ]]; then
  echo "missing: $props (copy gradle.properties.example and set the paths)" >&2
  exit 2
fi

prop() {
  local key="$1"
  grep -m1 "^${key}=" "$props" | cut -d= -f2- | tr -d '\r'
}

candidate="$root/build/workshop-candidate/KnoxSurvivors/Contents/mods/KnoxSurvivors"
local_dir="$(prop localModsRoot)/KnoxSurvivors"
workshop_dir="$(prop workshopRoot)/$(prop workshopModFolder)/Contents/mods/KnoxSurvivors"

for dir in "$candidate" "$local_dir" "$workshop_dir"; do
  if [[ ! -d "$dir" ]]; then
    echo "missing: $dir" >&2
    exit 2
  fi
done

manifest() {
  local dir="$1" out="$2"
  ( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum ) > "$out"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

manifest "$candidate" "$tmp/candidate"
manifest "$local_dir" "$tmp/local"
manifest "$workshop_dir" "$tmp/workshop"

count_candidate=$(wc -l < "$tmp/candidate" | tr -d ' ')
count_local=$(wc -l < "$tmp/local" | tr -d ' ')
count_workshop=$(wc -l < "$tmp/workshop" | tr -d ' ')

echo "candidate: $count_candidate files"
echo "local:     $count_local files"
echo "workshop:  $count_workshop files"

status=0
if ! diff -u "$tmp/candidate" "$tmp/local" > "$tmp/local.diff"; then
  echo "--- local differs from candidate ---"
  head -40 "$tmp/local.diff"
  status=1
fi
if ! diff -u "$tmp/candidate" "$tmp/workshop" > "$tmp/workshop.diff"; then
  echo "--- workshop differs from candidate ---"
  head -40 "$tmp/workshop.diff"
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "PARITY OK ($count_candidate files)"
fi
exit $status
