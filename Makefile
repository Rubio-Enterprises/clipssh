.PHONY: help test test-shell test-swift test-coverage lint clean

help:
	@echo "Targets:"
	@echo "  test           Run the shell test suite (bats)"
	@echo "  test-shell     Same as test"
	@echo "  test-swift     Run the Swift unit tests (macOS only)"
	@echo "  test-coverage  Run shell tests under kcov and print summary"
	@echo "  lint           Run shellcheck against clipssh"
	@echo "  clean          Remove coverage and build artifacts"

test: test-shell

test-shell:
	bats tests/unit tests/integration

test-swift:
	$(MAKE) -C swift test

test-coverage:
	@rm -rf coverage
	@mkdir -p coverage
	kcov --include-path=$(CURDIR)/clipssh coverage bats tests/unit tests/integration
	@python3 -c "import json; d=json.load(open('coverage/bats.$$(ls coverage | grep ^bats | head -1 | cut -d. -f2)/coverage.json')); print('Coverage:', d['percent_covered'] + '%')" 2>/dev/null || \
	  find coverage -name coverage.json -exec python3 -c "import json,sys; d=json.load(open(sys.argv[1])); [print(f['percent_covered']+'%  '+f['file']) for f in d['files']]" {} \;

lint:
	shellcheck clipssh

clean:
	rm -rf coverage build
	$(MAKE) -C swift clean 2>/dev/null || true
