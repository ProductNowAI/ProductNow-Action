#!/usr/bin/env bash
set -euo pipefail

: "${MCP_URL:?MCP_URL must be set}"
: "${MCP_KEY:?MCP_KEY must be set}"
: "${UPDATE_PROMPT_FILE:?UPDATE_PROMPT_FILE must be set}"
: "${INTERVAL_HOURS:?INTERVAL_HOURS must be set}"

# --- MCP config (shared by the preflight and the main call) ---
MCP_CONFIG_FILE="$(mktemp)"
DIFF_FILE="$(mktemp)"
trap 'rm -f "$MCP_CONFIG_FILE" "$DIFF_FILE"' EXIT

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

# --- Preflight: read lastProcessedSha from the ProductNow registry ---
# ProductNow is the single source of truth for the window boundary. The runner
# is stateless, so we ask Claude (MCP-only) for the last processed sha, then
# diff from it. This chains runs with no gaps: the sha only advances in the
# main call's final step, so a failed run re-processes the same window instead
# of skipping it.
echo "Preflight: reading lastProcessedSha from the RTFM Registry..."
PREFLIGHT_RESULT=$(claude --print \
  --mcp-config="$MCP_CONFIG_FILE" \
  --allowedTools="mcp__productnow__search_documents,mcp__productnow__get_document" \
  "Call the ProductNow MCP tools: search_documents for 'RTFM Registry', then get_document it. Its body is a JSON object with a lastProcessedSha field. Output ONLY that sha value and nothing else — no prose, no quotes, no code fences. If the registry doc does not exist or has no lastProcessedSha, output exactly NONE." || true)

# The chained window diffs against lastProcessedSha, which must be present in
# the local checkout. If the caller used a shallow clone, deepen it first so we
# can stay in chained mode instead of dropping to the interval fallback.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --unshallow --quiet || git fetch --deepen=1000 --quiet || true
fi

# Extract the first commit-ish from whatever the preflight returned and confirm
# it actually resolves in this checkout (guards against chatty output and
# against a sha that isn't present because of a shallow clone).
SINCE_SHA=""
WINDOW_MODE="chained"
for cand in $(printf '%s' "$PREFLIGHT_RESULT" | grep -oiE '[0-9a-f]{7,40}' || true); do
  if git cat-file -e "${cand}^{commit}" 2>/dev/null; then
    SINCE_SHA="$cand"
    break
  fi
done

if [ -z "$SINCE_SHA" ]; then
  # First run, no usable sha, or the sha isn't in this checkout (shallow clone).
  # Fall back to a time-based window and flag it so the model can note overlap/gap risk.
  echo "Preflight sha unavailable or not in checkout; falling back to interval window."
  WINDOW_MODE="interval"
  SINCE_SHA=$(git rev-list -1 --before="${INTERVAL_HOURS} hours ago" HEAD || true)
fi

if [ -z "$SINCE_SHA" ]; then
  echo "No starting commit could be determined; nothing to process. Skipping."
  exit 0
fi

# --- Compute the change window ---
git diff "$SINCE_SHA" HEAD > "$DIFF_FILE"
if [ ! -s "$DIFF_FILE" ]; then
  echo "No changes since $SINCE_SHA; skipping."
  exit 0
fi

HEAD_SHA=$(git rev-parse HEAD)
COMMIT_RANGE="$(git rev-parse --short "$SINCE_SHA")..$(git rev-parse --short HEAD)"
COMMIT_DATE=$(git log -1 --format=%cs HEAD)

echo "Change window ($WINDOW_MODE): $COMMIT_RANGE"
cat "$DIFF_FILE"

# --- Build the prompt (Claude's only view of the code is this diff) ---
PROMPT="$(cat "$UPDATE_PROMPT_FILE")

---
Run metadata:
- Window mode: ${WINDOW_MODE}
- Commit range: ${COMMIT_RANGE}
- Head commit sha: ${HEAD_SHA}
- Commit date: ${COMMIT_DATE}

Change window diff (this is your ONLY view of the code for this run):

\`\`\`diff
$(cat "$DIFF_FILE")
\`\`\`"

# --- Main call: reconcile the docs and advance lastProcessedSha to HEAD_SHA ---
CLAUDE_RESULT=$(claude --print \
  --mcp-config="$MCP_CONFIG_FILE" \
  --allowedTools="mcp__productnow__*" \
  "$PROMPT")

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$CLAUDE_RESULT" >> "$GITHUB_STEP_SUMMARY"
else
  echo "$CLAUDE_RESULT"
fi
