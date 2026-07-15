#!/usr/bin/env bash
set -euo pipefail

: "${MCP_URL:?MCP_URL must be set}"
: "${MCP_KEY:?MCP_KEY must be set}"
: "${UPDATE_PROMPT_FILE:?UPDATE_PROMPT_FILE must be set}"
: "${INTERVAL_HOURS:?INTERVAL_HOURS must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/window.sh"

# Cumulative diff budget for one run. Windows bigger than this are processed as
# a prefix of commits that fits, and the remainder chains to the next run via
# lastProcessedSha. Any single file diff over the per-file cap is replaced by
# its stat summary (lockfile / generated-artifact churn).
DIFF_BUDGET_BYTES=300000
MAX_FILE_DIFF_BYTES=40000

# --- MCP config (shared by the preflight and the main call) ---
MCP_CONFIG_FILE="$(mktemp)"
DIFF_FILE="$(mktemp)"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$MCP_CONFIG_FILE" "$DIFF_FILE" "$PROMPT_FILE"' EXIT

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
#
# The preflight must be deterministic to consume: --output-format json and a
# strict output contract, one retry, and a HARD FAILURE if the registry exists
# but the sha can't be read. Silently dropping to the interval window converts
# a transient flake into a permanent gap in the doc corpus (observed 2026-07-13
# and 2026-07-14) — a red run that retries the same window is strictly better.
read_preflight_sha() {
  claude --print \
    --output-format json \
    --mcp-config="$MCP_CONFIG_FILE" \
    --allowedTools="mcp__productnow__search_documents,mcp__productnow__get_document" \
    "Call the ProductNow MCP tools: search_documents for 'RTFM Registry', then get_document it. Its body is a JSON object with a lastProcessedSha field. Output ONLY that sha value and nothing else — no prose, no quotes, no code fences. If the registry doc does not exist or has no lastProcessedSha, output exactly NONE." \
    2>/dev/null | jq -r '.result // empty' | tr -d '[:space:]'
}

echo "Preflight: reading lastProcessedSha from the RTFM Registry..."
PREFLIGHT_RESULT="$(read_preflight_sha || true)"
if ! printf '%s' "$PREFLIGHT_RESULT" | grep -qiE '^([0-9a-f]{7,40}|NONE)$'; then
  echo "Preflight attempt 1 unusable (raw: '${PREFLIGHT_RESULT}'); retrying once."
  PREFLIGHT_RESULT="$(read_preflight_sha || true)"
fi

# The chained window diffs against lastProcessedSha, which must be present in
# the local checkout. If the caller used a shallow clone, deepen it first so we
# can stay in chained mode instead of dropping to the interval fallback.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --unshallow --quiet || git fetch --deepen=1000 --quiet || true
fi

set +e
pn_resolve_change_window "$PREFLIGHT_RESULT" "$INTERVAL_HOURS"
RESOLVE_RC=$?
set -e

# Distinct outcomes from pn_resolve_change_window — never silent-fallback:
#   0 chained, 1 first-run NONE→interval, 2 unresolvable sha, 3 unusable preflight
case "$RESOLVE_RC" in
  0)
    ;;
  1)
    echo "Registry has no lastProcessedSha (first run); using interval window."
    ;;
  2)
    echo "ERROR: registry lastProcessedSha '${PREFLIGHT_RESULT}' does not resolve in this checkout even after deepening." >&2
    echo "A human must reconcile the registry sha with this repository's history." >&2
    exit 1
    ;;
  *)
    echo "ERROR: preflight could not read the registry after retry (raw: '${PREFLIGHT_RESULT}')." >&2
    echo "Refusing to fall back to an interval window while a registry may exist — that risks gapping the corpus. Failing so the next run retries the same window." >&2
    exit 1
    ;;
esac

if [ -z "$SINCE_SHA" ]; then
  echo "No starting commit could be determined; nothing to process. Skipping."
  exit 0
fi

# --- Compute the change window, bounded by the diff budget ---
# Take the largest prefix of window commits whose cumulative diff fits the
# budget; the remainder stays behind lastProcessedSha for the next run. A
# single commit that alone exceeds the budget is taken by itself (it cannot be
# chunked finer; per-file trimming below keeps it manageable).
CHUNK_HEAD=""
WINDOW_TRUNCATED="no"
for c in $(git rev-list --reverse --first-parent "${SINCE_SHA}..HEAD"); do
  size=$(git diff "$SINCE_SHA" "$c" | wc -c)
  if [ -n "$CHUNK_HEAD" ] && [ "$size" -gt "$DIFF_BUDGET_BYTES" ]; then
    break
  fi
  CHUNK_HEAD="$c"
  if [ "$size" -gt "$DIFF_BUDGET_BYTES" ]; then
    break
  fi
done

if [ -z "$CHUNK_HEAD" ]; then
  echo "No changes since $SINCE_SHA; skipping."
  exit 0
fi
if [ "$CHUNK_HEAD" != "$(git rev-parse HEAD)" ]; then
  WINDOW_TRUNCATED="yes"
  echo "Window exceeds diff budget; processing ${SINCE_SHA}..${CHUNK_HEAD} now — the remainder chains to the next run."
fi
HEAD_SHA="$CHUNK_HEAD"

# Build the diff, replacing any single file's diff over the per-file cap with
# its stat summary so churn can't consume the context budget. The prompt's
# defer-to-human rules cover anything this hides.
: > "$DIFF_FILE"
while IFS= read -r changed_file; do
  file_bytes=$(git diff "$SINCE_SHA" "$HEAD_SHA" -- "$changed_file" | wc -c)
  if [ "$file_bytes" -gt "$MAX_FILE_DIFF_BYTES" ]; then
    {
      printf '### %s — full diff omitted (%s bytes); summary:\n' "$changed_file" "$file_bytes"
      git diff --stat "$SINCE_SHA" "$HEAD_SHA" -- "$changed_file"
      printf '\n'
    } >> "$DIFF_FILE"
  else
    git diff "$SINCE_SHA" "$HEAD_SHA" -- "$changed_file" >> "$DIFF_FILE"
  fi
done < <(git diff --name-only "$SINCE_SHA" "$HEAD_SHA")

if [ ! -s "$DIFF_FILE" ]; then
  echo "No changes since $SINCE_SHA; skipping."
  exit 0
fi

COMMIT_RANGE="$(git rev-parse --short "$SINCE_SHA")..$(git rev-parse --short "$HEAD_SHA")"
COMMIT_DATE=$(git log -1 --format=%cs "$HEAD_SHA")

echo "Change window ($WINDOW_MODE): $COMMIT_RANGE (truncated: $WINDOW_TRUNCATED)"
cat "$DIFF_FILE"

# --- Build the prompt (Claude's only view of the code is this diff) ---
# Written to a file and fed via stdin: Linux caps a single argv argument at
# 128KiB, and a large change-window diff blows it (execve E2BIG → exit 126,
# observed 2026-07-14).
{
  cat "$UPDATE_PROMPT_FILE"
  printf '\n---\nRun metadata:\n'
  printf -- '- Window mode: %s\n' "$WINDOW_MODE"
  printf -- '- Commit range: %s\n' "$COMMIT_RANGE"
  printf -- '- Head commit sha: %s\n' "$HEAD_SHA"
  printf -- '- Commit date: %s\n' "$COMMIT_DATE"
  printf -- '- Window truncated to fit diff budget: %s (if yes, later commits are processed by subsequent runs)\n' "$WINDOW_TRUNCATED"
  printf '\nChange window diff (this is your ONLY view of the code for this run):\n\n```diff\n'
  cat "$DIFF_FILE"
  printf '```\n'
} > "$PROMPT_FILE"

# --- Main call: reconcile the docs and advance lastProcessedSha to HEAD_SHA ---
CLAUDE_RESULT=$(claude --print \
  --mcp-config="$MCP_CONFIG_FILE" \
  --allowedTools="mcp__productnow__*" \
  < "$PROMPT_FILE")

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$CLAUDE_RESULT" >> "$GITHUB_STEP_SUMMARY"
else
  echo "$CLAUDE_RESULT"
fi
