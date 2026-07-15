# Security Policy

## Reporting a vulnerability

Email **security@productnow.ai**. Do not open a public GitHub issue for security
reports.

Please include:

- A description of the issue and its impact
- Steps to reproduce, or a proof of concept if available
- Affected refs (tag, branch, or commit SHA) if known

We will acknowledge receipt and follow up with next steps. Please allow a
reasonable time for triage before any public disclosure.

## Supported versions

Security fixes are applied to the default branch (`main`) and to the latest
published release tag. Older tags may not receive backports; pin consumers to a
current SHA or release when possible.

## Threat model (summary)

| Trust domain | What it can see / do |
|--------------|----------------------|
| GitHub Actions runner | Consumer checkout, action inputs (including secrets), network to Anthropic and ProductNow MCP |
| Claude (via Claude Code) | Injected change-window **diff** only as code context; ProductNow **MCP tools** only — no filesystem, no git, no arbitrary shell in the intended design |
| ProductNow MCP | Docs corpus and registry updates for the caller's ProductNow workspace |

This action does **not** write commits or open pull requests in the consumer
repository. Documentation changes land in ProductNow, not in git.

### Out of scope for this Action

- Securing the consumer's Anthropic or ProductNow credentials (store them as
  GitHub Actions secrets; rotate if leaked)
- Secrets present inside the git diff (if a commit introduces a secret, the
  model may see that hunk — prevent secrets from landing in git)
- ProductNow platform security outside this repository's code

## Hardening recommendations for consumers

1. Store `ANTHROPIC_API_KEY`, `PN_MCP_URL`, and `PN_MCP_KEY` as repository or
   organization secrets — never in workflow YAML.
2. Pin this action to a full commit SHA (not only a floating tag).
3. Use `fetch-depth: 0` and a `concurrency` group as described in the README.
4. Limit who can modify workflows that pass these secrets.
