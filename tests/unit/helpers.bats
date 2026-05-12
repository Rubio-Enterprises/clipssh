#!/usr/bin/env bats
#
# Unit tests for pure helper functions: usage, error/success printers,
# parse_args, resolve_host, compute_remote_filename, resolve_remote_dir,
# detect_clipboard_tool, copy_to_local_clipboard.

bats_require_minimum_version 1.5.0
load '../helpers/common'

setup() {
    common_setup
    source_clipssh
}

teardown() {
    common_teardown
}

# --- usage ------------------------------------------------------------------

@test "usage: lists key sections" {
    run usage
    assert_success
    assert_output --partial "Usage: clipssh"
    assert_output --partial "Commands:"
    assert_output --partial "Options:"
    assert_output --partial "Environment"
    assert_output --partial "CLIPSSH_HOST"
    assert_output --partial "CLIPSSH_REMOTE_DIR"
}

# --- error / success --------------------------------------------------------

@test "error: writes to stderr, exits 1, includes the message" {
    run -1 error "boom"
    assert_output --partial "Error:"
    assert_output --partial "boom"
}

@test "success: writes to stdout in green" {
    run success "done"
    assert_success
    # ANSI green prefix and reset are present; grep them via partial match.
    assert_output --partial "done"
}

# --- parse_args -------------------------------------------------------------

@test "parse_args: -h prints usage and exits 0" {
    run parse_args -h
    assert_success
    assert_output --partial "Usage: clipssh"
}

@test "parse_args: --help prints usage and exits 0" {
    run parse_args --help
    assert_success
    assert_output --partial "Usage: clipssh"
}

@test "parse_args: -v prints version and exits 0" {
    run parse_args -v
    assert_success
    assert_output --partial "clipssh"
}

@test "parse_args: --version prints version and exits 0" {
    run parse_args --version
    assert_success
    assert_output --partial "clipssh"
}

@test "parse_args: unknown flag errors out" {
    run -1 parse_args --bogus
    assert_output --partial "Unknown option: --bogus"
}

@test "parse_args: positional argument is captured as HOST" {
    HOST=""
    parse_args user@server
    assert_equal "$HOST" "user@server"
}

@test "parse_args: last positional wins when multiple are given" {
    HOST=""
    parse_args first@host second@host
    assert_equal "$HOST" "second@host"
}

# --- resolve_host -----------------------------------------------------------

@test "resolve_host: prefers an already-set HOST (CLI arg) over env and config" {
    config_set host config@host
    HOST="cli@host"
    CLIPSSH_HOST="env@host" resolve_host
    assert_equal "$HOST" "cli@host"
}

@test "resolve_host: falls back to CLIPSSH_HOST when CLI arg is empty" {
    config_set host config@host
    HOST=""
    CLIPSSH_HOST="env@host" resolve_host
    assert_equal "$HOST" "env@host"
}

@test "resolve_host: falls back to the config file when neither CLI nor env is set" {
    config_set host config@host
    HOST=""
    resolve_host
    assert_equal "$HOST" "config@host"
}

@test "resolve_host: errors when nothing is configured" {
    HOST=""
    run -1 resolve_host
    assert_output --partial "No host specified"
}

# --- detect_clipboard_tool --------------------------------------------------

@test "detect_clipboard_tool: picks xclip on linux when available" {
    install_mock xclip 'exit 0'
    PASTE_CMD=""
    detect_clipboard_tool
    assert_equal "$PASTE_CMD" "xclip -selection clipboard -target image/png -o"
}

@test "detect_clipboard_tool: falls back to wl-paste when xclip is missing" {
    install_mock wl-paste 'exit 0'
    PASTE_CMD=""
    detect_clipboard_tool
    assert_equal "$PASTE_CMD" "wl-paste --type image/png"
}

@test "detect_clipboard_tool: errors on linux when no tool is found" {
    # MOCK_BIN is empty and the rest of PATH only holds coreutils, so neither
    # xclip nor wl-paste are reachable.
    run -1 detect_clipboard_tool
    assert_output --partial "No clipboard tool found"
}

@test "detect_clipboard_tool: errors on macOS when clipssh-paste is missing" {
    OSTYPE="darwin23" run -1 detect_clipboard_tool
    assert_output --partial "clipssh-paste not found"
}

@test "detect_clipboard_tool: accepts clipssh-paste when present on macOS" {
    install_mock clipssh-paste 'exit 0'
    OSTYPE="darwin23" run detect_clipboard_tool
    assert_success
}

@test "detect_clipboard_tool: errors on unsupported OS" {
    OSTYPE="freebsd14" run -1 detect_clipboard_tool
    assert_output --partial "Unsupported OS"
}

# --- compute_remote_filename ------------------------------------------------

@test "compute_remote_filename: returns generic name on linux" {
    run compute_remote_filename 1700000000 "source:file:/x.png"
    assert_success
    assert_output "clipboard-1700000000.png"
}

@test "compute_remote_filename: uses file basename for source:file: on macOS" {
    OSTYPE="darwin23" run compute_remote_filename 1700000000 "source:file:/Users/me/Pictures/photo.JPG"
    assert_success
    assert_output "photo-1700000000.png"
}

@test "compute_remote_filename: uses file basename for source:path: on macOS" {
    OSTYPE="darwin23" run compute_remote_filename 1700000000 "source:path:/tmp/screenshot.gif"
    assert_success
    assert_output "screenshot-1700000000.png"
}

@test "compute_remote_filename: handles unknown source line on macOS" {
    OSTYPE="darwin23" run compute_remote_filename 1700000000 "source:image"
    assert_success
    assert_output "clipboard-1700000000.png"
}

@test "compute_remote_filename: handles empty source line on macOS" {
    OSTYPE="darwin23" run compute_remote_filename 1700000000 ""
    assert_success
    assert_output "clipboard-1700000000.png"
}

@test "compute_remote_filename: strips multi-dot extensions correctly" {
    OSTYPE="darwin23" run compute_remote_filename 42 "source:file:/tmp/my.photo.v2.png"
    assert_success
    assert_output "my.photo.v2-42.png"
}

# --- resolve_remote_dir -----------------------------------------------------

@test "resolve_remote_dir: defaults to /tmp when nothing is set" {
    run resolve_remote_dir
    assert_success
    assert_output "/tmp"
}

@test "resolve_remote_dir: uses the config file value when env is unset" {
    config_set remote_dir /var/uploads
    run resolve_remote_dir
    assert_success
    assert_output "/var/uploads"
}

@test "resolve_remote_dir: env var takes precedence over config" {
    config_set remote_dir /var/uploads
    CLIPSSH_REMOTE_DIR=/env/dir run resolve_remote_dir
    assert_success
    assert_output "/env/dir"
}

# --- copy_to_local_clipboard ------------------------------------------------

@test "copy_to_local_clipboard: pipes to xclip on linux when available" {
    install_mock xclip "cat > \"$TEST_TMP/xclip.in\""
    copy_to_local_clipboard "hello"
    assert_equal "$(<"$TEST_TMP/xclip.in")" "hello"
}

@test "copy_to_local_clipboard: falls back to wl-copy when xclip is missing" {
    install_mock wl-copy "cat > \"$TEST_TMP/wl.in\""
    copy_to_local_clipboard "from-wl"
    assert_equal "$(<"$TEST_TMP/wl.in")" "from-wl"
}

@test "copy_to_local_clipboard: uses pbcopy on macOS" {
    install_mock pbcopy "cat > \"$TEST_TMP/pb.in\""
    OSTYPE="darwin23" copy_to_local_clipboard "from-mac"
    assert_equal "$(<"$TEST_TMP/pb.in")" "from-mac"
}

@test "copy_to_local_clipboard: no-op when no clipboard tool is available" {
    run copy_to_local_clipboard "ignored"
    assert_success
    assert_output ""
}
