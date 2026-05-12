#!/usr/bin/env bats
#
# End-to-end CLI tests. Each test invokes the clipssh binary with fakes for
# ssh and clipboard tools, then asserts on stdout/stderr/exit code and on
# files written by the fakes.

bats_require_minimum_version 1.5.0
load '../helpers/common'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

# --- help / version ---------------------------------------------------------

@test "CLI: --help prints usage and exits 0" {
    run -0 "$CLIPSSH_BIN" --help
    assert_output --partial "Usage: clipssh"
    assert_output --partial "Config keys: host, remote_dir"
}

@test "CLI: -h prints usage" {
    run -0 "$CLIPSSH_BIN" -h
    assert_output --partial "Usage: clipssh"
}

@test "CLI: --version prints version string" {
    run -0 "$CLIPSSH_BIN" --version
    assert_output --partial "clipssh"
}

@test "CLI: unknown flag errors with non-zero exit and helpful message" {
    run -1 "$CLIPSSH_BIN" --no-such-flag
    assert_output --partial "Unknown option: --no-such-flag"
}

# --- config subcommand ------------------------------------------------------

@test "CLI: config set writes to the XDG config file and reports success" {
    run -0 "$CLIPSSH_BIN" config set host me@example.com
    assert_output --partial "Set host = me@example.com"
    assert_file_exists "$XDG_CONFIG_HOME/clipssh/config"
    assert_file_contains "$XDG_CONFIG_HOME/clipssh/config" "^host=me@example.com$"
}

@test "CLI: config set without a value errors with usage" {
    run -1 "$CLIPSSH_BIN" config set host
    assert_output --partial "Usage: clipssh config set <key> <value>"
}

@test "CLI: config set without a key errors with usage" {
    run -1 "$CLIPSSH_BIN" config set
    assert_output --partial "Usage: clipssh config set <key> <value>"
}

@test "CLI: config get returns the stored value" {
    "$CLIPSSH_BIN" config set host me@example.com
    run -0 "$CLIPSSH_BIN" config get host
    assert_output "me@example.com"
}

@test "CLI: config get without a key errors with usage" {
    run -1 "$CLIPSSH_BIN" config get
    assert_output --partial "Usage: clipssh config get <key>"
}

@test "CLI: config list shows defaults when nothing is set" {
    run -0 "$CLIPSSH_BIN" config list
    assert_output --partial "remote_dir   = /tmp"
    assert_output --partial "(default)"
}

@test "CLI: config (no subcommand) defaults to list" {
    run -0 "$CLIPSSH_BIN" config
    assert_output --partial "Config file:"
    assert_output --partial "remote_dir   = /tmp"
}

@test "CLI: config with an unknown subcommand errors" {
    run -1 "$CLIPSSH_BIN" config bogus
    assert_output --partial "Unknown config command: bogus"
}

# --- upload flow ------------------------------------------------------------

@test "CLI: errors when no host is configured" {
    install_mock xclip "printf 'fake-png-bytes'"
    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No host specified"
}

@test "CLI: errors with a helpful message when the clipboard has no image" {
    install_mock xclip "exit 1"
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host me@example.com
    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No image in clipboard"
}

# xclip is invoked with -o to read (-> emit PNG) and with -selection clipboard
# to write (-> record what came in). Single binary handles both modes.
install_xclip_with_recorder() {
    install_mock xclip "$(cat <<'EOF'
for arg in "$@"; do
    if [[ "$arg" == "-o" ]]; then
        printf 'fake-png-bytes'
        exit 0
    fi
done
cat > "$TEST_TMP/xclip.copy"
EOF
)"
}

@test "CLI: full upload flow uses CLI host, ssh, and copies result to clipboard" {
    install_xclip_with_recorder
    install_ssh_recorder

    run -0 "$CLIPSSH_BIN" target@remote
    assert_output --partial "Uploaded: /tmp/clipboard-"
    assert_output --partial "Path copied to clipboard"

    assert_file_contains "$TEST_TMP/ssh.host" "^target@remote$"
    assert_file_contains "$TEST_TMP/ssh.stdin" "^fake-png-bytes$"
    assert_file_contains "$TEST_TMP/xclip.copy" "^/tmp/clipboard-"
}

@test "CLI: configured host is used when no CLI arg is given" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host configured@host

    run -0 "$CLIPSSH_BIN"
    assert_file_contains "$TEST_TMP/ssh.host" "^configured@host$"
}

@test "CLI: CLIPSSH_HOST overrides the configured host" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host configured@host

    CLIPSSH_HOST=env@host run -0 "$CLIPSSH_BIN"
    assert_file_contains "$TEST_TMP/ssh.host" "^env@host$"
}

@test "CLI: CLI arg overrides CLIPSSH_HOST and config" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host configured@host

    CLIPSSH_HOST=env@host run -0 "$CLIPSSH_BIN" cli@host
    assert_file_contains "$TEST_TMP/ssh.host" "^cli@host$"
}

@test "CLI: CLIPSSH_REMOTE_DIR is forwarded into the remote ssh script" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    CLIPSSH_REMOTE_DIR=/custom/upload/dir run -0 "$CLIPSSH_BIN"
    assert_file_contains "$TEST_TMP/ssh.script" "/custom/upload/dir"
}

@test "CLI: configured remote_dir is forwarded when env var is unset" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote
    "$CLIPSSH_BIN" config set remote_dir /var/clip/uploads

    run -0 "$CLIPSSH_BIN"
    assert_file_contains "$TEST_TMP/ssh.script" "/var/clip/uploads"
}

@test "CLI: errors when ssh produces no remote path" {
    install_mock xclip "printf 'fake-png-bytes'"
    install_mock ssh "cat > /dev/null; exit 0"
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "Failed to upload to target@remote"
}

@test "CLI: surfaces ssh's stderr in the failure message" {
    install_mock xclip "printf 'fake-png-bytes'"
    install_mock ssh "echo 'Permission denied (publickey)' >&2; exit 255"
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "Failed to upload to target@remote"
    assert_output --partial "Permission denied (publickey)"
}

@test "CLI: config set propagates errors instead of silently continuing" {
    # Point XDG_CONFIG_HOME at a path that's actually a regular file — the
    # mkdir -p inside config_set will fail. Without set -e on the config
    # codepath, the script would print "Set host = ..." anyway.
    : > "$TEST_TMP/not-a-dir"
    XDG_CONFIG_HOME="$TEST_TMP/not-a-dir" run "$CLIPSSH_BIN" config set host me@example.com
    refute [ "$status" -eq 0 ]
    refute_output --partial "Set host"
}

@test "CLI: errors when the extracted image is empty" {
    install_mock xclip "exit 0"
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "Clipboard image is empty"
}

@test "CLI: errors when no clipboard tool is installed" {
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No clipboard tool found"
}
