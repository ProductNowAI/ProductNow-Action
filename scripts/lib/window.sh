# shellcheck shell=bash
# Source-only library (do not execute). Sourced by update_documentation.sh and
# Bats tests; inherits the caller's `set` options — do not add set -euo pipefail
# here. Pure helpers for change-window resolution (no Claude / network).

# Extract hex candidates (7–40 chars) from preflight text, in order of appearance.
# Prints one candidate per line.
pn_extract_sha_candidates() {
  local text="${1:-}"
  printf '%s' "$text" | grep -oiE '[0-9a-f]{7,40}' || true
}

# Return 0 if $1 resolves to a commit in the current git repository.
pn_is_resolvable_commit() {
  local cand="${1:-}"
  [ -n "$cand" ] || return 1
  git cat-file -e "${cand}^{commit}" 2>/dev/null
}

# Resolve interval fallback sha: git rev-list -1 --before="<hours> hours ago" HEAD
# Prints sha on stdout; exit 0 if found, 1 otherwise.
pn_resolve_interval_sha() {
  local interval_hours="${1:?interval_hours required}"
  local sha
  sha=$(git rev-list -1 --before="${interval_hours} hours ago" HEAD 2>/dev/null || true)
  if [ -n "$sha" ]; then
    printf '%s\n' "$sha"
    return 0
  fi
  return 1
}

# Resolve SINCE_SHA and WINDOW_MODE from a normalized preflight result.
# Preflight must be exactly a commit sha or NONE (no chatty wrapping).
#
# Interval fallback is ONLY used when preflight is exactly NONE (true first
# run). Unresolvable registry shas and unparseable preflight never fall back.
#
# Exit codes (caller must hard-fail on 2 and 3):
#   0 — chained success (registry sha resolved in this checkout)
#   1 — no registry / first run (NONE); WINDOW_MODE=interval; SINCE_SHA may be empty
#   2 — registry sha present but does not resolve in this checkout
#   3 — unusable preflight (not NONE and not a bare hex sha)
pn_resolve_change_window() {
  local preflight="${1:-}"
  local interval_hours="${2:?interval_hours required}"
  local resolved

  SINCE_SHA=""
  WINDOW_MODE="chained"

  if printf '%s' "$preflight" | grep -qiE '^[0-9a-f]{7,40}$'; then
    if pn_is_resolvable_commit "$preflight"; then
      SINCE_SHA="$preflight"
      WINDOW_MODE="chained"
      export SINCE_SHA WINDOW_MODE
      return 0
    fi
    export SINCE_SHA WINDOW_MODE
    return 2
  fi

  if printf '%s' "$preflight" | grep -qiE '^NONE$'; then
    WINDOW_MODE="interval"
    if resolved=$(pn_resolve_interval_sha "$interval_hours"); then
      SINCE_SHA="$resolved"
    else
      SINCE_SHA=""
    fi
    export SINCE_SHA WINDOW_MODE
    return 1
  fi

  export SINCE_SHA WINDOW_MODE
  return 3
}

# Return 0 if git diff from $1 to HEAD is non-empty.
pn_has_changes_since() {
  local since_sha="${1:?since_sha required}"
  ! git diff --quiet "$since_sha" HEAD
}
