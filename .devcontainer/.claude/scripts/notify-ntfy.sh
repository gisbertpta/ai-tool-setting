#!/bin/bash
# ~/.claude/scripts/notify-ntfy.sh
# Claude Code Stop hook — sends completion notification via ntfy.sh

NTFY_TOPIC="claude-done-gisbert"   # ← change this
NTFY_URL="https://ntfy.sh/$NTFY_TOPIC"

INPUT=$(cat)

# Extract transcript path from hook JSON
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Get last assistant message from transcript
SUMMARY=""
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  SUMMARY=$(tail -n 200 "$TRANSCRIPT" \
    | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null \
    | tail -n 1 \
    | cut -c1-200)
fi

# Fallback message if no summary found
[[ -z "$SUMMARY" ]] && SUMMARY="Task finished."

PROJECT=$(basename "$(pwd)")

curl -s -X POST "$NTFY_URL" \
  -H "Title: ✓ Claude Code — $PROJECT" \
  -H "Priority: default" \
  -H "Tags: white_check_mark" \
  -d "$SUMMARY" \
  > /dev/null

exit 0
