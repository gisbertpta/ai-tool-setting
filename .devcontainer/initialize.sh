#!/usr/bin/env bash
# initialize.sh — runs on the HOST before the containers are created
# (devcontainer.json → initializeCommand).
#
# 1. Checks that a project layer is linked into the slot .devcontainer/project/
# 2. Checks the host prerequisites that Docker would otherwise silently "fix"
#    by creating directories
# 3. Builds the generic base image the project layer's Dockerfile starts FROM

set -euo pipefail
cd "$(dirname "$0")"

BASE_IMAGE="ai-envelope-base:latest"
FAIL=0

# ── 1. Project layer ──────────────────────────────────────────────────────────
if [ ! -e project ]; then
  if [ -L project ]; then
    echo "[init] ERROR: .devcontainer/project is a broken symlink (-> $(readlink project))."
  else
    echo "[init] ERROR: no project layer at .devcontainer/project."
  fi
  echo "       Link or copy one, e.g.:"
  echo "         ln -s ../<repo>/<layer-dir> .devcontainer/project"
  echo "         cp -r .devcontainer/project-template <somewhere> && ln -s ... .devcontainer/project"
  echo "       See README.md (\"Starting a new project\")."
  exit 1
fi

for f in compose.yml Dockerfile excluded-files allowlist.txt; do
  if [ ! -f "project/$f" ]; then
    echo "[init] ERROR: project layer is missing '$f' (compare with .devcontainer/project-template/)."
    FAIL=1
  fi
done

# ── 2. Host prerequisites ─────────────────────────────────────────────────────
# A missing bind-mount source file would be created by Docker as a DIRECTORY.
for f in "$HOME/.claude.json" "$HOME/.gitconfig"; do
  if [ ! -f "$f" ]; then
    echo "[init] ERROR: $f must exist as a file (e.g. echo '{}' > ~/.claude.json)."
    FAIL=1
  fi
done
if [ ! -d "$HOME/.claude" ]; then
  echo "[init] ERROR: $HOME/.claude must exist as a directory (mkdir ~/.claude)."
  FAIL=1
fi

[ "$FAIL" -eq 0 ] || exit 1

# ── 3. Base image ─────────────────────────────────────────────────────────────
echo "[init] Project layer: .devcontainer/project -> $(readlink -f project)"
echo "[init] Building base image ${BASE_IMAGE} ..."
docker build -t "$BASE_IMAGE" base
