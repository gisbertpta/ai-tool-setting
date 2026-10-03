#!/usr/bin/env bash
# compose.sh — docker compose with the envelope's files (base + project layer).
# Use it instead of a bare 'docker compose' so both files are always merged:
#   .devcontainer/compose.sh ps
#   .devcontainer/compose.sh logs -f proxy
#   .devcontainer/compose.sh restart proxy
dir="$(cd "$(dirname "$0")" && pwd)"
exec docker compose -f "$dir/docker-compose.yml" -f "$dir/project/compose.yml" "$@"
