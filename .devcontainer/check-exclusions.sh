#!/usr/bin/env bash
# check-exclusions.sh — verify that sensitive workspace files are properly masked.
#
# Called automatically at container start via postStartCommand in devcontainer.json.
# Can also be run manually inside the container: check-exclusions
#
# Configuration: .devcontainer/excluded-files in the workspace root.
# Each line is a path relative to /workspace. Lines starting with # are ignored.
#
# A file is considered properly masked when it is one of:
#   absent      — file does not exist in the workspace at all
#   empty       — size 0 (result of bind-mounting /dev/null over it)
#   char device — the bind-mount of /dev/null itself is visible as a device node
#   dummy match — content is identical to the dummy template (see below)
#
# A directory is considered properly masked when it is one of:
#   absent      — directory does not exist in the workspace at all
#   empty       — no entries (result of tmpfs or empty bind-mount overlay)
#   dummy match — contents identical to the dummy template (see below)
#
# Dummy templates are looked up in this order:
#   .devcontainer/dummy-<top-dir>/dummy.<basename>   (e.g. dummy-ki-zfw-wm-code/dummy.configs)
#   .devcontainer/dummy.<basename>

set -uo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
CONFIG="${WORKSPACE}/.devcontainer/excluded-files"
DUMMY_DIR="${WORKSPACE}/.devcontainer"
FAIL=0

# No config file — nothing to check
if [ ! -f "$CONFIG" ]; then
  echo "[exclusions] No .devcontainer/excluded-files found — skipping."
  exit 0
fi

echo "[exclusions] Checking masked files..."

while IFS= read -r relpath || [ -n "$relpath" ]; do
  # Skip blank lines and comments
  [[ -z "$relpath" || "$relpath" == \#* ]] && continue

  target="${WORKSPACE}/${relpath}"
  # Prefer a per-repo dummy (.devcontainer/dummy-<top-dir>/dummy.<basename>),
  # fall back to the flat layout (.devcontainer/dummy.<basename>)
  dummy="${DUMMY_DIR}/dummy-${relpath%%/*}/dummy.$(basename "$relpath")"
  [ -e "$dummy" ] || dummy="${DUMMY_DIR}/dummy.$(basename "$relpath")"

  # 1. Absent — nothing to leak
  if [ ! -e "$target" ]; then
    printf "  OK (absent)  %s\n" "$relpath"
    continue
  fi

  # ── Directory checks ────────────────────────────────────────────────────────
  if [ -d "$target" ]; then
    # 2. Empty directory — tmpfs or empty bind-mount overlay
    if [ -z "$(ls -A "$target")" ]; then
      printf "  OK (empty)   %s\n" "$relpath"
      continue
    fi

    # 3. Matches known-safe dummy directory template
    if [ -d "$dummy" ] && diff -rq "$target" "$dummy" > /dev/null 2>&1; then
      printf "  OK (dummy)   %s\n" "$relpath"
      continue
    fi

    # None of the above — directory has real content
    printf "  WARN         %s  <-- not masked!\n" "$relpath"
    if [ -d "$dummy" ]; then
      echo "               expected: absent, empty, or matching $(basename "$dummy")/"
    else
      echo "               expected: absent, or empty (tmpfs overlay)"
      echo "               to add a dummy template: create ${dummy}/"
    fi
    FAIL=1
    continue
  fi

  # ── File checks ─────────────────────────────────────────────────────────────
  # 2. Empty — /dev/null overlay produces a size-0 regular file
  if [ ! -s "$target" ]; then
    printf "  OK (empty)   %s\n" "$relpath"
    continue
  fi

  # 3. Character device — the /dev/null node itself was bind-mounted
  if [ -c "$target" ]; then
    printf "  OK (devnull) %s\n" "$relpath"
    continue
  fi

  # 4. Matches known-safe dummy template
  if [ -f "$dummy" ] && diff -q "$target" "$dummy" > /dev/null 2>&1; then
    printf "  OK (dummy)   %s\n" "$relpath"
    continue
  fi

  # None of the above — file is present with real content
  printf "  WARN         %s  <-- not masked!\n" "$relpath"
  if [ -f "$dummy" ]; then
    echo "               expected: absent, empty, /dev/null overlay, or matching $(basename "$dummy")"
  else
    echo "               expected: absent, or empty (/dev/null overlay)"
    echo "               to add a dummy template: create ${dummy}"
  fi
  FAIL=1

done < "$CONFIG"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "[exclusions] WARNING: one or more files may be unmasked inside the container."
  echo "             See .devcontainer/README.md (\"Mask an additional secret file\" / \"Debugging\")."
  exit 1
fi

echo "[exclusions] All checks passed."
