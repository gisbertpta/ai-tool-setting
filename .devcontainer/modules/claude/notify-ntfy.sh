#!/usr/bin/env bash
# Claude Code Stop hook — sends a fixed "finished" notification via ntfy.sh.
# Active only when the 'ntfy' module is enabled (it mounts the topic file and
# allowlists ntfy.sh); otherwise this is a no-op.
#
# Sends no message content on purpose: the topic is readable by anyone who
# knows its name.

TOPIC_FILE=/run/secrets/ntfy-topic
[ -s "$TOPIC_FILE" ] || exit 0

cat > /dev/null   # hook input (JSON) is not used
TOPIC="$(< "$TOPIC_FILE")"

curl -s -m 5 -X POST "https://ntfy.sh/${TOPIC}" \
  -H "Title: Claude Code finished" \
  -H "Tags: white_check_mark" \
  -d "Task finished in $(basename "$PWD")." \
  > /dev/null

exit 0
