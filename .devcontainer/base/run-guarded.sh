#!/usr/bin/env bash
# run-guarded <command> [args...] — runs the file-exclusion check, then execs the command.
# Every agent CLI (claude, copilot, ...) is installed behind a wrapper that calls this,
# so none of them starts while a monitored file is unmasked.
# To skip the check (e.g. for debugging): run <cli>.real directly.

if [ $# -eq 0 ]; then
  echo "usage: run-guarded <command> [args...]" >&2
  exit 2
fi

if ! check-exclusions; then
  echo ""
  echo "$(basename "$1" .real) is blocked: one or more files are not properly masked."
  echo "Fix the mounts listed above, then rebuild or restart the container."
  exit 1
fi

exec "$@"
