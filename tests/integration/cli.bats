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

@test "CLI: config get on an unset key prints '(not set)' and exits 1" {
    run -1 "$CLIPSSH_BIN" config get host
    assert_output --partial "(not set)"
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

# --- ssh option passthrough -------------------------------------------------

@test "CLI: -p / -i / -o flags are forwarded to ssh as separate argv slots" {
    install_xclip_with_recorder
    install_mock ssh "$(cat <<'EOF'
# Record each argv slot on its own line so we can assert positional layout.
printf '%s\n' "$@" > "$TEST_TMP/ssh.argv"
cat > /dev/null
echo "/tmp/remote.png"
EOF
)"
    "$CLIPSSH_BIN" config set host target@remote

    run -0 "$CLIPSSH_BIN" -p 2222 -i /tmp/key -o StrictHostKeyChecking=no
    assert_file_contains "$TEST_TMP/ssh.argv" "^-p$"
    assert_file_contains "$TEST_TMP/ssh.argv" "^2222$"
    assert_file_contains "$TEST_TMP/ssh.argv" "^-i$"
    assert_file_contains "$TEST_TMP/ssh.argv" "^/tmp/key$"
    assert_file_contains "$TEST_TMP/ssh.argv" "^StrictHostKeyChecking=no$"
    assert_file_contains "$TEST_TMP/ssh.argv" "^target@remote$"
}

# --- --file source ---------------------------------------------------------

@test "CLI: --file uploads the named file instead of reading the clipboard" {
    install_ssh_recorder
    printf 'png-from-disk' > "$TEST_TMP/diagram.png"
    "$CLIPSSH_BIN" config set host target@remote

    run -0 "$CLIPSSH_BIN" --file "$TEST_TMP/diagram.png"
    assert_output --partial "Uploaded:"
    # Filename is derived from the basename of the source.
    assert_output --partial "diagram-"
    assert_file_contains "$TEST_TMP/ssh.stdin" "^png-from-disk$"
}

@test "CLI: --file errors clearly when the path does not exist" {
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    run -1 "$CLIPSSH_BIN" --file /tmp/no-such-file-1234567890.png
    assert_output --partial "File not found"
}

# --- --remote-dir flag -----------------------------------------------------

@test "CLI: --remote-dir overrides the configured remote directory" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote
    "$CLIPSSH_BIN" config set remote_dir /from/config

    run -0 "$CLIPSSH_BIN" -r /from/flag
    assert_file_contains "$TEST_TMP/ssh.script" "/from/flag"
    # The configured value must NOT leak into the remote script — assert via
    # grep's exit code so a regression produces a clear "grep matched" failure.
    run grep -F '/from/config' "$TEST_TMP/ssh.script"
    assert_failure
}

# --- --print-only ----------------------------------------------------------

@test "CLI: --print-only writes path to stdout and does not touch the clipboard" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    run -0 "$CLIPSSH_BIN" --print-only
    # Path goes to stdout, by itself, no "Uploaded:" banner.
    assert_output --regexp '^/tmp/clipboard-'
    refute_output --partial "Path copied"
    # And no xclip.copy file was produced.
    assert_file_not_exists "$TEST_TMP/xclip.copy"
}

# --- enriched success line -------------------------------------------------

@test "CLI: success line reports size and detected source" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    run -0 "$CLIPSSH_BIN"
    assert_output --partial "Uploaded:"
    # 14 bytes of "fake-png-bytes" -> "14 B".
    assert_output --partial "14 B"
    assert_output --partial "clipboard"
}

# --- suggest-save host -----------------------------------------------------

@test "CLI: nudges the user to save the host after the third CLI-arg use" {
    install_xclip_with_recorder
    install_ssh_recorder

    "$CLIPSSH_BIN" repeat@host >/dev/null
    "$CLIPSSH_BIN" repeat@host >/dev/null
    run -0 "$CLIPSSH_BIN" repeat@host
    assert_output --partial "Tip:"
    assert_output --partial "config set host repeat@host"
}

@test "CLI: nudge resets when the CLI host changes" {
    install_xclip_with_recorder
    install_ssh_recorder

    "$CLIPSSH_BIN" first@host >/dev/null
    "$CLIPSSH_BIN" first@host >/dev/null
    run -0 "$CLIPSSH_BIN" different@host
    refute_output --partial "Tip:"
}

@test "CLI: nudge stays silent once the host is saved in config" {
    install_xclip_with_recorder
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host saved@host

    # Three runs passing the same host that's already saved. The early-return
    # in maybe_suggest_save_host should keep the tip suppressed indefinitely.
    run -0 "$CLIPSSH_BIN" saved@host
    refute_output --partial "Tip:"
    run -0 "$CLIPSSH_BIN" saved@host
    refute_output --partial "Tip:"
    run -0 "$CLIPSSH_BIN" saved@host
    refute_output --partial "Tip:"
}

# --- watch mode ------------------------------------------------------------

# Stateful xclip: any image read returns the current contents of $STATE_FILE.
# Lets a test drive the "clipboard" by rewriting that file mid-run.
install_stateful_xclip() {
    install_mock xclip "$(cat <<'EOF'
state_file="$TEST_TMP/clipboard.state"
# extract_linux_file_reference probes TARGETS / text/uri-list; fail both so
# extract falls through to PASTE_CMD (the image read).
for arg in "$@"; do
    case "$arg" in
        TARGETS|text/uri-list) exit 1 ;;
    esac
done
# Plain text clipboard reads (extract_linux_text_path) shouldn't match an
# image path — emit empty so that branch returns nonzero.
if [[ "$*" != *"-target image/png"* ]]; then
    exit 1
fi
if [[ -s "$state_file" ]]; then
    cat "$state_file"
else
    exit 1
fi
EOF
)"
}

# Per-upload-counting ssh mock: each call writes its stdin to a numbered file
# so a test can prove exactly how many uploads ran and with what payload.
install_counting_ssh() {
    install_mock ssh "$(cat <<'EOF'
counter="$TEST_TMP/ssh.counter"
n=$(($(cat "$counter" 2>/dev/null || echo 0)+1))
echo "$n" > "$counter"
cat > "$TEST_TMP/ssh.stdin.$n"
filename=$(printf '%s\n' "$@" | grep -oE 'PATH_FULL="\$DIR/[^"]+' | head -1 | sed 's|.*\$DIR/||')
echo "/tmp/$filename"
EOF
)"
}

@test "CLI: watch mode uploads new clipboards and dedupes identical ones" {
    install_stateful_xclip
    install_counting_ssh
    "$CLIPSSH_BIN" config set host target@remote

    export CLIPSSH_DEBUG_LOG="$TEST_TMP/watch.debug"
    printf 'image-A' > "$TEST_TMP/clipboard.state"
    "$CLIPSSH_BIN" --watch --interval 0.1 >"$TEST_TMP/watch.stdout" 2>"$TEST_TMP/watch.stderr" &
    WATCH_PID=$!
    sleep 1.0  # Many polls of image-A — only the first should upload.
    printf 'image-B' > "$TEST_TMP/clipboard.state"
    sleep 1.0  # Many polls of image-B — only the first should upload.
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true

    # Debug dump on failure
    if [[ ! -f "$TEST_TMP/ssh.stdin.1" ]]; then
        echo "--- watch.debug ---" >&3
        cat "$TEST_TMP/watch.debug" >&3 2>/dev/null || echo "(no debug file)" >&3
        echo "--- watch.stdout ---" >&3
        cat "$TEST_TMP/watch.stdout" >&3 2>/dev/null
        echo "--- watch.stderr ---" >&3
        cat "$TEST_TMP/watch.stderr" >&3 2>/dev/null
        echo "--- clipboard.state ---" >&3
        cat "$TEST_TMP/clipboard.state" >&3 2>/dev/null
        echo "--- ls TEST_TMP ---" >&3
        ls -la "$TEST_TMP" >&3 2>/dev/null
        echo "--- OSTYPE in test = $OSTYPE ---" >&3
        echo "--- bash --version ---" >&3
        bash --version >&3 2>&1
    fi

    # Two uploads, in order, no third.
    assert_file_exists "$TEST_TMP/ssh.stdin.1"
    assert_file_exists "$TEST_TMP/ssh.stdin.2"
    assert_file_not_exists "$TEST_TMP/ssh.stdin.3"
    assert_file_contains "$TEST_TMP/ssh.stdin.1" "^image-A$"
    assert_file_contains "$TEST_TMP/ssh.stdin.2" "^image-B$"
}

@test "CLI: watch mode survives a poll with no image (does not exit)" {
    # xclip always exits 1: extract_clipboard_image will error() inside the
    # iteration's subshell. Without the subshell isolation, the parent would
    # exit and watch would die — `kill -0 $pid` would then fail.
    install_mock xclip "exit 1"
    install_ssh_recorder
    "$CLIPSSH_BIN" config set host target@remote

    "$CLIPSSH_BIN" --watch --interval 0.1 >/dev/null 2>&1 &
    WATCH_PID=$!
    sleep 0.5
    run kill -0 "$WATCH_PID"
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
    assert_success
    # And no upload ever happened.
    assert_file_not_exists "$TEST_TMP/ssh.stdin"
}

@test "CLI: watch mode does not retry the same hash after a failed upload" {
    install_stateful_xclip
    # ssh always fails: counts attempts but returns nonzero with no stdout.
    install_mock ssh "$(cat <<'EOF'
counter="$TEST_TMP/ssh.counter"
n=$(($(cat "$counter" 2>/dev/null || echo 0)+1))
echo "$n" > "$counter"
cat > /dev/null
echo "remote refused" >&2
exit 1
EOF
)"
    "$CLIPSSH_BIN" config set host target@remote
    printf 'doomed' > "$TEST_TMP/clipboard.state"

    "$CLIPSSH_BIN" --watch --interval 0.1 >/dev/null 2>&1 &
    WATCH_PID=$!
    sleep 0.8
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true

    # Exactly one ssh attempt — subsequent polls see the same hash as
    # last_hash (recorded even on upload failure) and skip.
    local n
    n=$(cat "$TEST_TMP/ssh.counter" 2>/dev/null || echo 0)
    [[ "$n" -eq 1 ]]
}

# --- setup wizard ----------------------------------------------------------

@test "CLI: 'setup' refuses to run without a TTY (no interactive input piped)" {
    # No stdin/stdout TTY in bats; this exercises the guard.
    run -1 "$CLIPSSH_BIN" setup < /dev/null
    assert_output --partial "interactive terminal"
}
