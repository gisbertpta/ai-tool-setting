#!/usr/bin/env bash
# Claude Code launcher — runs the file-exclusion check before starting Claude.
# If any monitored file is unmasked, Claude is blocked from starting.
# To skip the check (e.g. for debugging): run claude.real directly.

if ! check-exclusions; then
  echo ""
  echo "Claude Code is blocked: one or more files are not properly masked."
  echo "Fix the mounts listed above, then rebuild or restart the container."
  exit 1
fi

exec claude.real "$@"
