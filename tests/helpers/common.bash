# Shared helpers loaded by every bats test file.
#
# Conventions:
#   - $CLIPSSH_BIN points at the script under test.
#   - $TEST_TMP is a per-test temp directory cleaned up in teardown.
#   - XDG_CONFIG_HOME is redirected into $TEST_TMP so config writes are sandboxed.
#   - $MOCK_BIN is a per-test PATH-prefix holding fake ssh / clipboard tools.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CLIPSSH_BIN="$PROJECT_ROOT/clipssh"

# /usr/bin:/bin holds coreutils (rm, sed, grep) but neither xclip nor pbcopy,
# which lets tests deterministically reproduce "no clipboard tool installed".
ISOLATED_PATH="/usr/bin:/bin"

# Locate bats-support/assert/file across apt + Homebrew layouts and abort the
# test run with a clear message if any of them is missing — otherwise tests
# fail later with cryptic "command not found: assert_output" errors.
load_bats_libs() {
    BATS_LIB_PATH="/usr/lib/bats:/usr/local/lib:/opt/homebrew/lib${BATS_LIB_PATH:+:$BATS_LIB_PATH}"
    export BATS_LIB_PATH
    local lib
    for lib in bats-support bats-assert bats-file; do
        if declare -F bats_load_library >/dev/null; then
            bats_load_library "$lib" 2>/dev/null || true
        else
            local prefix
            for prefix in ${BATS_LIB_PATH//:/ }; do
                if [[ -f "$prefix/$lib/load.bash" ]]; then
                    # shellcheck disable=SC1090
                    load "$prefix/$lib/load.bash"
                    break
                fi
            done
        fi
    done
    if ! declare -F assert_output >/dev/null \
        || ! declare -F assert_file_exists >/dev/null; then
        echo "common.bash: bats-assert / bats-file not found." >&2
        echo "  Searched: $BATS_LIB_PATH" >&2
        echo "  Run 'make setup' to install them." >&2
        exit 1
    fi
}

common_setup() {
    load_bats_libs

    TEST_TMP="$(mktemp -d)"
    export TEST_TMP

    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$TEST_TMP/xdg"

    MOCK_BIN="$TEST_TMP/bin"
    mkdir -p "$MOCK_BIN"
    export MOCK_BIN
    export PATH="$MOCK_BIN:$ISOLATED_PATH"

    export OSTYPE="linux-gnu"

    unset CLIPSSH_HOST CLIPSSH_REMOTE_DIR
}

common_teardown() {
    rm -rf "${TEST_TMP:?}"
}

# Install a fake executable in $MOCK_BIN. Body is the script body (sans shebang).
install_mock() {
    local name="$1" body="$2"
    local path="$MOCK_BIN/$name"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
    chmod +x "$path"
}

# Source the clipssh script so its functions are available in the test shell.
source_clipssh() {
    # shellcheck disable=SC1090
    source "$CLIPSSH_BIN"
}

# Records the host arg, remote script, and stdin payload to $TEST_TMP/ssh.*,
# then echoes the synthesized remote path the real script would produce.
install_ssh_recorder() {
    install_mock ssh "$(cat <<'EOF'
echo "$1" > "$TEST_TMP/ssh.host"
echo "$2" > "$TEST_TMP/ssh.script"
cat > "$TEST_TMP/ssh.stdin"
filename=$(printf '%s\n' "$2" | grep -oE 'PATH_FULL="\$DIR/[^"]+' | sed 's|.*\$DIR/||')
echo "/tmp/$filename"
EOF
)"
}
