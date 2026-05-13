# Tests

Two layers, run together by `task test`:

- **`tests/unit/`** — bats tests that `source` `clipssh` and exercise functions
  directly. Fast, no subprocesses unless explicitly mocked.
- **`tests/integration/`** — bats tests that invoke `./clipssh` as a binary
  with `ssh`, `xclip`, `pbcopy`, etc. replaced by per-test mocks. These cover
  the end-to-end CLI surface including arg precedence, the upload flow, and
  failure modes.

The `clipssh` script is structured so that sourcing it only defines functions;
the actual orchestration in `main` runs only when the script is the program's
entry point. See the `BASH_SOURCE` guard at the bottom of `clipssh`.

## Conventions

- `tests/helpers/common.bash` provides `common_setup` / `common_teardown` and
  the `install_mock` helper. Every test file should `load '../helpers/common'`
  and call `common_setup` / `common_teardown` from its `setup` / `teardown`.
- Each test runs with `HOME`, `XDG_CONFIG_HOME`, and `PATH` sandboxed into
  `$TEST_TMP` so the developer's real config and clipboard tooling are never
  touched.
- `PATH` is reduced to `$MOCK_BIN:/usr/bin:/bin` so tests can deterministically
  assert "no clipboard tool installed" cases without depending on what happens
  to be on the host.

## Running

```
task test            # bats only (fast feedback)
task test-coverage   # bats + kcov, prints per-file coverage
task lint            # shellcheck
task test-swift      # Swift XCTests (requires macOS / Xcode)
task check           # what CI runs: lint + tests + coverage floor
```

## Coverage

Coverage is measured with [kcov](https://github.com/SimonKagstrom/kcov) against
the `clipssh` script. The `check-coverage` target enforces a floor of
`COVERAGE_FLOOR` (default 80%); the suite currently covers ≥97%. The handful
of "uncovered" lines are continuation lines of a single multi-line ssh
heredoc — they execute in tests but kcov accounts for them per physical line.

kcov on macOS uses an lldb-based backend that hangs when traced against bats
(see kcov #458). CI enforces the coverage floor on `ubuntu-latest` only;
macOS still runs `task lint test-shell` so the 81-test bats suite executes on
both OSes.

## Swift

`swift/Sources/ClipsshPasteCore/` holds the AppKit-free helpers used by
`clipssh-paste`. Tests in `swift/Tests/ClipsshPasteCoreTests/` exercise them
via `swift test`. The executable target (`clipssh-paste`) wires those helpers
to `NSPasteboard` and is intentionally thin so most of its behavior is tested
through the core module.
