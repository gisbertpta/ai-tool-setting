#!/usr/bin/env bash
# check-exclusions.sh — verify that sensitive workspace files are properly masked.
#
# Called automatically at container start via postStartCommand in devcontainer.json.
# Can also be run manually inside the container: check-exclusions
#
# Configuration: excluded-files in the project layer (.devcontainer/project/).
# Each line is a path relative to /workspace. Lines starting with # are ignored.
#
# A file is considered properly masked when it is one of:
#   absent      — file does not exist in the workspace at all
#   empty       — size 0 (result of bind-mounting /dev/null over it)
#   char device — the bind-mount of /dev/null itself is visible as a device node
#   dummy match — content is identical to the dummy (see below)
#
# A directory is considered properly masked when it is one of:
#   absent      — directory does not exist in the workspace at all
#   empty       — no entries (result of tmpfs or empty bind-mount overlay)
#   dummy match — contents identical to the dummy (see below)
#
# Dummies mirror the masked path inside the project layer:
#   .devcontainer/project/dummies/<path>   (e.g. dummies/my-repo/configs)

set -uo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
PROJECT_LAYER="${PROJECT_LAYER:-${WORKSPACE}/.devcontainer/project}"
CONFIG="${PROJECT_LAYER}/excluded-files"
DUMMY_DIR="${PROJECT_LAYER}/dummies"
FAIL=0

# No project layer at all — the setup is broken, don't pretend everything is fine
if [ ! -d "$PROJECT_LAYER" ]; then
  echo "[exclusions] ERROR: no project layer at ${PROJECT_LAYER}."
  echo "             See README.md (\"Starting a new project\")."
  exit 1
fi

# No config file — nothing to check
if [ ! -f "$CONFIG" ]; then
  echo "[exclusions] No ${CONFIG} found — skipping."
  exit 0
fi

echo "[exclusions] Checking masked files..."

while IFS= read -r relpath || [ -n "$relpath" ]; do
  # Skip blank lines and comments
  [[ -z "$relpath" || "$relpath" == \#* ]] && continue

  target="${WORKSPACE}/${relpath}"
  dummy="${DUMMY_DIR}/${relpath}"

  # 1. Absent — nothing to leak. But if the whole repo (first path component) is
  #    missing, it may just be cloned under another name, with its secrets unmasked.
  if [ ! -e "$target" ]; then
    printf "  OK (absent)  %s\n" "$relpath"
    repo="${relpath%%/*}"
    if [ "$repo" != "$relpath" ] && [ ! -e "${WORKSPACE}/${repo}" ]; then
      echo "               NOTE: ${repo}/ does not exist. If it is cloned under another"
      echo "               name, its secrets are NOT masked. Required repos belong in"
      echo "               the project layer's prereqs."
    fi
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
      echo "               expected: absent, empty, or matching ${dummy}/"
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
    echo "               expected: absent, empty, /dev/null overlay, or matching ${dummy}"
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
