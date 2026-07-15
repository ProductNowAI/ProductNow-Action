# Contributing

This repository is maintained by ProductNow. Pull requests are opened by
internal maintainers; unsolicited external PRs are generally not accepted.
Security issues: see [SECURITY.md](SECURITY.md).

## Development setup

```bash
# macOS
brew install bats-core shellcheck actionlint

make lint
make test
```

## Change process

1. Create a branch from `main`.
2. Make focused changes. Prefer small, reviewable commits.
3. Update docs when behavior or trust boundaries change (`README.md`,
   `SECURITY.md`, `docs/COMPLIANCE.md`, `prompts/UPDATE.md` as applicable).
4. Open a pull request and ensure CI is green (`lint-and-test`).
5. Require a human review before merge.

## Local checks (same as CI)

| Target | What it runs |
|--------|----------------|
| `make lint` | ShellCheck, `bash -n`, actionlint |
| `make test` | Bats unit tests under `tests/` |

Do not commit secrets, API keys, or real MCP URLs. Use placeholders in examples.

## Adding tests

CI runs every `*.bats` file under `tests/` via `make test`. Prefer testing **pure
helpers** in `scripts/lib/` — not the full `update_documentation.sh` path that
calls Claude or MCP.

### Pattern

1. **Extract logic** into a function in `scripts/lib/*.sh` (no network, no
   secrets). Source that file from the runner script.
2. **Add or extend** a Bats file under `tests/` (one file per lib/topic is fine).
3. In `setup()`, `source` the helper and build any needed fixtures (e.g. a temp
   git repo). Clean up in `teardown()`.
4. Write `@test` cases that assert exit status and stdout.

Minimal skeleton (see [`tests/window.bats`](tests/window.bats) for a full
example):

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/your_helpers.sh"
}

@test "pn_example returns expected output" {
  run pn_example "input"
  [ "$status" -eq 0 ]
  [ "$output" = "expected" ]
}
```

### Conventions

- **No live Claude/MCP** in unit tests. Mock or skip anything that needs
  credentials.
- **Git helpers:** build a throwaway repo with `mktemp` + `git init` (and fixed
  `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` when testing time-based windows).
- **Name tests** after the behavior (`pn_resolve_change_window interval when
  preflight is NONE`), not the implementation detail.
- **Keep ShellCheck green** on new lib functions (`make lint`).
- Static sample strings can live under `tests/fixtures/` if they get noisy
  inline.

### Run a single file

```bash
bats tests/window.bats
# or
make test
```

## Release notes for consumers

When cutting a release consumers will pin to, mention any prompt/registry
contract changes and any new required workflow settings.
