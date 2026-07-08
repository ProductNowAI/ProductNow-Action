#!/usr/bin/env bash
set -euo pipefail

# Proof of concept 1: Has access to diff
echo "Diff since last run ($DIFF_FILE):"
cat "$DIFF_FILE"

# Proof of concept 2: Can call Claude Code connected to MCP server
MCP_CONFIG_FILE="$(mktemp)"
trap 'rm -f "$MCP_CONFIG_FILE"' EXIT

cat > "$MCP_CONFIG_FILE" <<EOF
{
  "mcpServers": {
    "productnow": {
      "type": "http",
      "url": "${MCP_URL}",
      "headers": {
        "Authorization": "Bearer ${MCP_KEY}"
      }
    }
  }
}
EOF

CLAUDE_RESULT=$(claude --print \
  --mcp-config "$MCP_CONFIG_FILE" \
  "Call the ProductNow MCP server's list_folders tool. Reply with a short confirmation that the call succeeded and how many folders were returned.")

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$CLAUDE_RESULT" >> "$GITHUB_STEP_SUMMARY"
else
  echo "$CLAUDE_RESULT"
fi
