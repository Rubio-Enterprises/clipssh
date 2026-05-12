# Shared helpers loaded by every bats test file.
#
# Conventions:
#   - $CLIPSSH_BIN points at the script under test.
#   - $TEST_TMP is a per-test temp directory cleaned up in teardown.
#   - XDG_CONFIG_HOME is redirected into $TEST_TMP so config writes are sandboxed.
#   - $MOCK_BIN is a per-test PATH-prefix holding fake ssh / clipboard tools.

# Resolve project root regardless of which test file pulled us in.
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CLIPSSH_BIN="$PROJECT_ROOT/clipssh"
MOCKS_DIR="$TESTS_DIR/mocks"

# Load bats-assert / bats-file / bats-support if available (apt-installed paths).
load_bats_libs() {
    local lib
    for lib in /usr/lib/bats/bats-support/load.bash \
               /usr/lib/bats/bats-assert/load.bash \
               /usr/lib/bats/bats-file/load.bash; do
        # shellcheck disable=SC1090
        [[ -f "$lib" ]] && load "$lib"
    done
}

# A minimal but functional PATH used by tests that need to strip out clipboard
# tools without losing coreutils. /usr/bin and /bin are intentional — they hold
# rm, sed, grep, etc. which the script under test relies on.
ISOLATED_PATH="/usr/bin:/bin"

# Standard per-test setup.
common_setup() {
    load_bats_libs

    TEST_TMP="$(mktemp -d)"
    export TEST_TMP

    # Sandbox config + home so tests never touch the developer's real files.
    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$TEST_TMP/xdg"

    # Per-test mock bin directory at the front of PATH so fakes win over reals.
    MOCK_BIN="$TEST_TMP/bin"
    mkdir -p "$MOCK_BIN"
    export MOCK_BIN
    export PATH="$MOCK_BIN:$ISOLATED_PATH"

    # Default to linux behavior; macOS-specific tests override OSTYPE.
    export OSTYPE="linux-gnu"

    # Clear inheritable config so behavior is deterministic.
    unset CLIPSSH_HOST CLIPSSH_REMOTE_DIR
}

common_teardown() {
    rm -rf "$TEST_TMP"
}

# Install a fake executable in $MOCK_BIN. Body is run with the script's args.
install_mock() {
    local name="$1"
    local body="$2"
    local path="$MOCK_BIN/$name"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
    chmod +x "$path"
}

# Source the clipssh script as a library (functions only, no main).
# This works because the script guards `main "$@"` behind a BASH_SOURCE check.
source_clipssh() {
    # shellcheck disable=SC1090
    source "$CLIPSSH_BIN"
}
