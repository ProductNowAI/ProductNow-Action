# ProductNow-Action

A GitHub Action that keeps your ProductNow "RTFM" documentation corpus in sync
with your code. On a schedule it computes the diff since the last successful
run and asks Claude — connected only to the ProductNow MCP server — to
reconcile the docs and record what changed.

Claude runs with **no access to your codebase, filesystem, or git**. Its only
view of the code is the diff the action injects into the prompt, and its only
tools are the ProductNow MCP tools. Nothing is written back to your repository.

## Usage

Add a workflow file to your repository at `.github/workflows/rtfm-update.yml`:

```yaml
name: RTFM Update
on:
  schedule:
    - cron: '0 */3 * * *'   # every 3 hours
concurrency:
  group: rtfm-update         # serialize runs so two can't double-process
  cancel-in-progress: false
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0      # full history — see Requirements
      - uses: your-org/ProductNow-Action@v1
        with:
          task: update_rtfm
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          mcp_url: ${{ secrets.PN_MCP_URL }}
          mcp_key: ${{ secrets.PN_MCP_KEY }}
          interval_hours: '3'
```

Store `ANTHROPIC_API_KEY`, `PN_MCP_URL`, and `PN_MCP_KEY` as
[repository secrets](https://docs.github.com/actions/security-guides/using-secrets-in-github-actions).
Replace `your-org/ProductNow-Action@v1` with the ref you publish.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `task` | yes | — | Task for the action to perform. Use `update_rtfm` for the scheduled documentation update. |
| `anthropic_api_key` | yes | — | Anthropic API key used to run Claude. |
| `mcp_url` | yes | — | ProductNow MCP server URL. |
| `mcp_key` | yes | — | ProductNow MCP API key (sent as a bearer token). |
| `interval_hours` | no | `3` | Fallback window size, in hours. Used only when the run can't chain off the last processed commit (see Requirements). Set it to match your `cron` cadence. |

## Requirements

Two settings live in **your** workflow (above), not in this action, and both
matter for correctness:

- **`fetch-depth: 0` on `actions/checkout`.** The action diffs from the last
  successfully processed commit (`lastProcessedSha`, stored in ProductNow), so
  that commit must be present in the checkout. With the default shallow clone
  it usually isn't. The action will try to unshallow the repo automatically as
  a safety net, but that is slower on large repos and can fail — setting
  `fetch-depth: 0` is the reliable path. Without history, the action falls back
  to a time-based window (`interval_hours`), which may overlap or skip commits.

- **A `concurrency` group.** Scheduled runs can overlap (a run starts while the
  previous one is still going). A `concurrency` group serializes them so the
  same change window isn't processed twice. This cannot be configured inside the
  action — it must be set in your workflow.

## How the update window works

The action is stateless; the source of truth for "what has been processed" is
`lastProcessedSha` in your ProductNow RTFM registry.

1. **Preflight:** read `lastProcessedSha` from the registry (MCP only).
2. **Diff:** compute `git diff <lastProcessedSha>..HEAD` — the change window.
3. **Reconcile:** Claude classifies affected docs and applies surgical edits
   through the ProductNow MCP tools.
4. **Record:** on success, `lastProcessedSha` is advanced to `HEAD`.

Because the sha only advances on success, a failed or interrupted run leaves it
unchanged and the next run re-processes the same window — no gaps. If the last
sha can't be resolved (first run, or history unavailable), the action falls back
to the `interval_hours` window and notes it in the run summary.
