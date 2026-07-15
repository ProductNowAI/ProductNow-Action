#!/usr/bin/env bats

_iso_days_ago() {
  local days="$1"
  if date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ
  fi
}

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=../scripts/lib/window.sh
  source "${REPO_ROOT}/scripts/lib/window.sh"

  TEST_REPO="$(mktemp -d)"
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  export GIT_AUTHOR_DATE
  export GIT_COMMITTER_DATE
  GIT_AUTHOR_DATE="$(_iso_days_ago 2)"
  GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
  echo "a" > file.txt
  git add file.txt
  git commit -q -m "initial"
  OLD_SHA=$(git rev-parse HEAD)

  GIT_AUTHOR_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
  echo "b" > file.txt
  git add file.txt
  git commit -q -m "second"
  NEW_SHA=$(git rev-parse HEAD)
}

teardown() {
  cd /
  rm -rf "$TEST_REPO"
}

@test "pn_extract_sha_candidates finds hex from chatty preflight" {
  run pn_extract_sha_candidates "Here is the sha: ${OLD_SHA:0:12} thanks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${OLD_SHA:0:12}"* ]]
}

@test "pn_resolve_change_window chained when preflight sha resolvable" {
  run pn_resolve_change_window "$OLD_SHA" "3"
  [ "$status" -eq 0 ]
  pn_resolve_change_window "$OLD_SHA" "3"
  [ "$WINDOW_MODE" = "chained" ]
  [ "$SINCE_SHA" = "$OLD_SHA" ]
}

@test "pn_resolve_change_window interval only when preflight is NONE" {
  run pn_resolve_change_window "NONE" "24"
  [ "$status" -eq 1 ]
  set +e
  pn_resolve_change_window "NONE" "24"
  local_rc=$?
  set -e
  [ "$local_rc" -eq 1 ]
  [ "$WINDOW_MODE" = "interval" ]
  [ -n "$SINCE_SHA" ]
  pn_is_resolvable_commit "$SINCE_SHA"
}

@test "pn_resolve_change_window hard-fails when sha not in checkout" {
  run pn_resolve_change_window "ffffffffffffffffffffffffffffffffffffffff" "24"
  [ "$status" -eq 2 ]
}

@test "pn_resolve_change_window hard-fails on unusable preflight" {
  run pn_resolve_change_window "sorry I could not find it" "24"
  [ "$status" -eq 3 ]
}

@test "pn_resolve_change_window hard-fails on chatty wrapped sha" {
  run pn_resolve_change_window "sha=${OLD_SHA}" "24"
  [ "$status" -eq 3 ]
}

@test "pn_has_changes_since detects diff" {
  run pn_has_changes_since "$OLD_SHA"
  [ "$status" -eq 0 ]
}

@test "pn_has_changes_since empty at HEAD" {
  run pn_has_changes_since "$NEW_SHA"
  [ "$status" -ne 0 ]
}

@test "pn_resolve_interval_sha returns a commit for 24h window" {
  run pn_resolve_interval_sha "24"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  pn_is_resolvable_commit "$output"
}
