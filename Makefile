.PHONY: help setup test test-shell test-swift test-coverage check-coverage check lint clean

COVERAGE_FLOOR ?= 80
COVERAGE_JSON  ?= coverage/bats/coverage.json

help:
	@echo "Targets:"
	@echo "  setup           Install bats, shellcheck, jq, kcov (Linux/macOS)"
	@echo "  test            Run the shell test suite (bats)"
	@echo "  test-shell      Same as test"
	@echo "  test-swift      Run the Swift unit tests (macOS only)"
	@echo "  test-coverage   Run shell tests under kcov and print summary"
	@echo "  check-coverage  Run test-coverage and fail if below $(COVERAGE_FLOOR)%"
	@echo "  check           Lint + check-coverage (what CI runs)"
	@echo "  lint            Run shellcheck against clipssh"
	@echo "  clean           Remove coverage and build artifacts"

setup:
	./script/bootstrap

test: test-shell

test-shell:
	bats tests/unit tests/integration

test-swift:
	$(MAKE) -C swift test

test-coverage:
	@rm -rf coverage
	@mkdir -p coverage
	kcov --include-path=$(CURDIR)/clipssh coverage bats tests/unit tests/integration
	@jq -r '.files[] | "\(.percent_covered)%  \(.file)"' $(COVERAGE_JSON)

check-coverage: test-coverage
	@pct=$$(jq -r '.files[] | select(.file|endswith("/clipssh")).percent_covered' $(COVERAGE_JSON)); \
	echo "clipssh coverage: $$pct% (floor: $(COVERAGE_FLOOR)%)"; \
	awk "BEGIN{exit !($$pct >= $(COVERAGE_FLOOR))}"

check: lint check-coverage

lint:
	shellcheck clipssh script/bootstrap

clean:
	rm -rf coverage build
	$(MAKE) -C swift clean
