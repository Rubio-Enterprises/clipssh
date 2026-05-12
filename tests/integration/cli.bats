#!/usr/bin/env bats
#
# End-to-end CLI tests. These execute the clipssh binary with fakes for ssh
# and the clipboard tools, asserting on stdout/stderr/exit code and on the
# files the fakes record.

bats_require_minimum_version 1.5.0
load '../helpers/common'

setup() {
    common_setup
}

teardown() {
    common_teardown
}

# Builds a fake ssh that records the host arg + stdin payload, then prints
# a fabricated remote path on stdout (matching the real script's contract).
install_ssh_mock() {
    install_mock ssh "$(cat <<'EOF'
host_arg="$1"
remote_script="$2"
echo "$host_arg" > "$TEST_TMP/ssh.host"
echo "$remote_script" > "$TEST_TMP/ssh.script"
cat > "$TEST_TMP/ssh.stdin"
# Extract the desired filename from the script that clipssh sent.
filename=$(printf '%s\n' "$remote_script" | grep -oE 'PATH_FULL="\$DIR/[^"]+' | sed 's|.*\$DIR/||')
echo "/tmp/$filename"
EOF
)"
}

# Fake xclip image source that emits a tiny PNG-ish blob.
install_xclip_with_image() {
    install_mock xclip "printf 'fake-png-bytes' && exit 0"
}

# Fake xclip that pretends there is no image on the clipboard.
install_xclip_empty() {
    install_mock xclip "exit 1"
}

# Fake xclip for the "copy result" path; records what was piped in.
install_xclip_copy_recorder() {
    # Single binary handles both -o (read) and -selection clipboard (write).
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
    [[ -f "$XDG_CONFIG_HOME/clipssh/config" ]]
    grep -q "^host=me@example.com$" "$XDG_CONFIG_HOME/clipssh/config"
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
    install_xclip_with_image
    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No host specified"
}

@test "CLI: errors with a helpful message when the clipboard has no image" {
    install_xclip_empty
    install_ssh_mock
    "$CLIPSSH_BIN" config set host me@example.com
    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No image in clipboard"
}

@test "CLI: full upload flow uses CLI host, ssh, and copies result to clipboard" {
    install_xclip_copy_recorder
    install_ssh_mock

    run -0 "$CLIPSSH_BIN" target@remote
    assert_output --partial "Uploaded: /tmp/clipboard-"
    assert_output --partial "Path copied to clipboard"

    # ssh was called with the right host.
    [[ "$(cat "$TEST_TMP/ssh.host")" == "target@remote" ]]
    # ssh received the fake image data on stdin.
    [[ "$(cat "$TEST_TMP/ssh.stdin")" == "fake-png-bytes" ]]
    # The remote path was written to the local clipboard.
    grep -q "^/tmp/clipboard-" "$TEST_TMP/xclip.copy"
}

@test "CLI: configured host is used when no CLI arg is given" {
    install_xclip_copy_recorder
    install_ssh_mock
    "$CLIPSSH_BIN" config set host configured@host

    run -0 "$CLIPSSH_BIN"
    [[ "$(cat "$TEST_TMP/ssh.host")" == "configured@host" ]]
}

@test "CLI: CLIPSSH_HOST overrides the configured host" {
    install_xclip_copy_recorder
    install_ssh_mock
    "$CLIPSSH_BIN" config set host configured@host

    CLIPSSH_HOST=env@host run -0 "$CLIPSSH_BIN"
    [[ "$(cat "$TEST_TMP/ssh.host")" == "env@host" ]]
}

@test "CLI: CLI arg overrides CLIPSSH_HOST and config" {
    install_xclip_copy_recorder
    install_ssh_mock
    "$CLIPSSH_BIN" config set host configured@host

    CLIPSSH_HOST=env@host run -0 "$CLIPSSH_BIN" cli@host
    [[ "$(cat "$TEST_TMP/ssh.host")" == "cli@host" ]]
}

@test "CLI: CLIPSSH_REMOTE_DIR is forwarded into the remote ssh script" {
    install_xclip_copy_recorder
    install_ssh_mock
    "$CLIPSSH_BIN" config set host target@remote

    CLIPSSH_REMOTE_DIR=/custom/upload/dir run -0 "$CLIPSSH_BIN"
    grep -q "/custom/upload/dir" "$TEST_TMP/ssh.script"
}

@test "CLI: configured remote_dir is forwarded when env var is unset" {
    install_xclip_copy_recorder
    install_ssh_mock
    "$CLIPSSH_BIN" config set host target@remote
    "$CLIPSSH_BIN" config set remote_dir /var/clip/uploads

    run -0 "$CLIPSSH_BIN"
    grep -q "/var/clip/uploads" "$TEST_TMP/ssh.script"
}

@test "CLI: errors when ssh produces no remote path" {
    install_xclip_with_image
    # ssh succeeds but emits nothing — exercises the failure-to-upload branch.
    install_mock ssh "cat > /dev/null; exit 0"
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "Failed to upload to target@remote"
}

@test "CLI: errors when the extracted image is empty" {
    # xclip succeeds but writes zero bytes to stdout.
    install_mock xclip "exit 0"
    install_ssh_mock
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN"
    assert_output --partial "Clipboard image is empty"
}

@test "CLI: errors when no clipboard tool is installed" {
    install_ssh_mock
    "$CLIPSSH_BIN" config set host target@remote

    # MOCK_BIN has no xclip / wl-paste, and ISOLATED_PATH doesn't either.
    run -1 "$CLIPSSH_BIN"
    assert_output --partial "No clipboard tool found"
}
