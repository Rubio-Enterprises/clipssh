.PHONY: help setup test test-shell test-swift test-coverage check-coverage check lint clean

# Minimum coverage percentage the shell test suite must hit. CI enforces this
# via `make check-coverage`; running the same target locally produces an
# identical pass/fail result.
COVERAGE_FLOOR ?= 80

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
	@jq -r '.files[] | "\(.percent_covered)%  \(.file)"' coverage/bats/coverage.json

check-coverage: test-coverage
	@pct=$$(jq -r '.files[] | select(.file|endswith("/clipssh")).percent_covered' coverage/bats/coverage.json); \
	echo "clipssh coverage: $$pct% (floor: $(COVERAGE_FLOOR)%)"; \
	awk "BEGIN{exit !($$pct >= $(COVERAGE_FLOOR))}"

check: lint check-coverage

lint:
	shellcheck clipssh script/bootstrap

clean:
	rm -rf coverage build
	$(MAKE) -C swift clean
