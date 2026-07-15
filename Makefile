.PHONY: lint test ci

SCRIPTS := $(shell find scripts -name '*.sh' -type f)

lint:
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed"; exit 1; }
	@command -v actionlint >/dev/null || { echo "actionlint not installed"; exit 1; }
	shellcheck -x $(SCRIPTS)
	@for f in $(SCRIPTS); do bash -n "$$f"; done
	actionlint

test:
	@command -v bats >/dev/null || { echo "bats not installed"; exit 1; }
	bats tests/

ci: lint test
