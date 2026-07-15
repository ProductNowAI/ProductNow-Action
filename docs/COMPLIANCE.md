# Compliance and secure SDLC notes

This document describes how **this repository** supports ProductNow's secure
development and change-management practices (including evidence useful for
SOC 2 Type II programs). It does **not** assert that the Action is itself
"SOC 2 certified," and it does not replace ProductNow platform policies.

## Control mapping (repository scope)

| Practice area | How this repo supports it |
|---------------|---------------------------|
| Secure development | Composite action + bash under review; coding agent rules in `AGENTS.md` / `.cursor/rules`; ShellCheck and syntax checks in CI |
| Change management | Changes land via pull request; CI must pass; human review expected before merge to `main` |
| Access control | Secrets are GitHub Actions secrets (consumer-side); this repo does not ship credentials; workflow token permission default is read-only |
| Vulnerability management | Public disclosure path in `SECURITY.md` (`security@productnow.ai`); Dependabot for GitHub Actions dependencies |
| Least privilege / supply chain | CI pins third-party Actions by commit SHA; consumers are guided to pin this Action by SHA |
| Logging / evidence | CI runs on push/PR; GitHub retains workflow logs and PR history as change evidence |
| Testing | Bats unit tests for window/sha resolution logic; no live credentialed Claude/MCP in CI |

## Trust boundary (runtime)

When a consumer runs the Action:

1. The **runner** has the checkout and the configured secrets.
2. **Claude** receives the change-window diff and ProductNow MCP access only
   (by design of `scripts/update_documentation.sh` and `prompts/UPDATE.md`).
3. **ProductNow** holds the docs corpus and `lastProcessedSha`; the consumer
   git remotes are not modified by this Action.

See [SECURITY.md](../SECURITY.md) for reporting and consumer hardening.

## Operator checklist (GitHub settings)

Maintainers should keep these enabled in the GitHub UI (not encoded in this
repo):

- [ ] Branch protection on `main` requiring the `lint-and-test` CI check
- [ ] Restrict who can approve workflows that use production secrets (consumer orgs)
- [ ] Optional: GitHub private vulnerability reporting in addition to email

## Related files

- [SECURITY.md](../SECURITY.md)
- [CONTRIBUTING.md](../CONTRIBUTING.md)
- [README.md](../README.md)
- [AGENTS.md](../AGENTS.md)
