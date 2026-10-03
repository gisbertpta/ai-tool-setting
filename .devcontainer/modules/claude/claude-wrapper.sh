#!/usr/bin/env bash
# Claude Code launcher — runs the file-exclusion check, then starts Claude with
# permission prompts skipped (the sandbox is the permission boundary).
# If any monitored file is unmasked, Claude is blocked from starting.
# To skip the check (e.g. for debugging): run claude.real directly.
exec run-guarded claude.real --dangerously-skip-permissions "$@"
