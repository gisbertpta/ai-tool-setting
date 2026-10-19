#!/usr/bin/env bash
# Claude Code launcher — runs the file-exclusion check, then starts Claude with
# permission prompts skipped (the sandbox is the permission boundary).
# If any monitored file is unmasked, Claude is blocked from starting.
# To skip the check (e.g. for debugging): run claude.real directly.

# Nested repos: Claude only loads .claude/skills of the start directory, so when
# it starts in /workspace the skills of the repos below it are missing. Every
# repo directly below the start directory that has .claude/skills is added via
# --add-dir. Appended after the user's args (--add-dir is variadic and would
# swallow a prompt after it) and skipped for subcommands (claude mcp, claude
# update, ...), recognized as a single bare word.
add_dirs=()
if [[ $# -eq 0 || $1 == -* || $1 == *[[:space:]]* ]]; then
  for d in "$PWD"/*/.claude/skills; do
    [ -d "$d" ] && add_dirs+=(--add-dir "${d%/.claude/skills}")
  done
fi

exec run-guarded claude.real --dangerously-skip-permissions "$@" "${add_dirs[@]}"
