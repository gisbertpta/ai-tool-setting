#!/usr/bin/env bash
# GitHub Copilot CLI launcher — loads the Copilot token into this process only,
# runs the file-exclusion check, then starts Copilot.
# To skip the check (e.g. for debugging): run copilot.real directly.

TOKEN_FILE=/run/secrets/copilot-token

if [ -s "$TOKEN_FILE" ]; then
  COPILOT_GITHUB_TOKEN="$(< "$TOKEN_FILE")"
  export COPILOT_GITHUB_TOKEN
else
  echo "[copilot] WARNING: no token in ${TOKEN_FILE}; Copilot will ask for a login,"
  echo "          which the proxy blocks. See .devcontainer/modules/README.md."
fi

exec run-guarded copilot.real "$@"
