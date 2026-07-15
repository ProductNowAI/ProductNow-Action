## Summary

<!-- What changed and why -->

## Risk / trust boundary

<!-- secrets, MCP scope, prompt/registry contract, writeback behavior -->

- [ ] No secrets or real credentials in the diff
- [ ] Claude remains MCP-only + injected diff (if runner/prompt changed)

## Test plan

- [ ] `make lint`
- [ ] `make test`
- [ ] Docs updated if consumer-facing behavior changed (`README.md`, `SECURITY.md`, etc.)
