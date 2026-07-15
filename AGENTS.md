# Agent guide — ProductNow-Action

Composite GitHub Action that keeps a ProductNow RTFM corpus in sync with consumer
code. On a schedule it diffs since the last successful run and asks Claude —
connected only to the ProductNow MCP server — to reconcile docs.

## Repo map

| Path | Role |
|------|------|
| `action.yml` | Composite action entrypoint and inputs |
| `scripts/update_documentation.sh` | Scheduled `update_rtfm` runner |
| `scripts/lib/` | Sourced, unit-tested bash helpers |
| `prompts/UPDATE.md` | Canonical RTFM update prompt (registry contract) |
| `tests/` | Bats unit tests (no live Claude/MCP) |
| `.github/workflows/ci.yml` | Lint + correctness + unit tests |

## Non-negotiables

1. **Claude stays MCP-only.** Its only code view is the injected diff. Do not add
   tools, filesystem access, or git access for the model.
2. **No writeback to the consumer repo.** This action updates ProductNow docs
   only; never commit, push, or open PRs in the caller's git tree.
3. **Never commit secrets.** `anthropic_api_key`, `mcp_url`, and `mcp_key` are
   inputs/secrets only. Do not echo them, write them into prompts, step
   summaries, or fixtures.
4. **Pin third-party Actions by full commit SHA** in this repo's workflows (with
   a version comment). Tag refs alone are not enough.
5. **Keep `prompts/UPDATE.md` aligned** with the registry shape produced by
   seed tooling (`lastProcessedSha`, slugs, changelog/overview IDs). Change both
   sides together.
6. **Prefer small testable helpers** under `scripts/lib/`. Pure window/sha logic
   must stay covered by Bats.

## Local checks

```bash
make lint
make test
```

Install on macOS: `brew install bats-core shellcheck actionlint`.

When adding behavior, extract helpers under `scripts/lib/` and cover them with
Bats under `tests/`. See [CONTRIBUTING.md](CONTRIBUTING.md#adding-tests).

## Docs to update with behavior changes

- `README.md` — consumer usage and inputs
- `SECURITY.md` — threat model / disclosure if the trust boundary moves
- `docs/COMPLIANCE.md` — if SDLC controls change
