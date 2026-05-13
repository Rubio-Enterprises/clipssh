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

@test "parse_args: -p / --port accumulates into SSH_OPTS" {
    SSH_OPTS=()
    parse_args -p 2222 user@host
    assert_equal "${SSH_OPTS[0]}" "-p"
    assert_equal "${SSH_OPTS[1]}" "2222"
    assert_equal "$HOST" "user@host"
}

@test "parse_args: -i / --identity accumulates into SSH_OPTS" {
    SSH_OPTS=()
    parse_args -i /tmp/key user@host
    assert_equal "${SSH_OPTS[0]}" "-i"
    assert_equal "${SSH_OPTS[1]}" "/tmp/key"
}

@test "parse_args: -o options can be repeated" {
    SSH_OPTS=()
    parse_args -o StrictHostKeyChecking=no -o ConnectTimeout=5
    assert_equal "${#SSH_OPTS[@]}" "4"
    assert_equal "${SSH_OPTS[1]}" "StrictHostKeyChecking=no"
    assert_equal "${SSH_OPTS[3]}" "ConnectTimeout=5"
}

@test "parse_args: -p without a value errors" {
    run -1 parse_args -p
    assert_output --partial "Missing value for -p"
}

@test "parse_args: -f / --file sets FILE_SOURCE" {
    FILE_SOURCE=""
    parse_args -f /tmp/photo.png user@host
    assert_equal "$FILE_SOURCE" "/tmp/photo.png"
    assert_equal "$HOST" "user@host"
}

@test "parse_args: -r / --remote-dir sets REMOTE_DIR_OVERRIDE" {
    REMOTE_DIR_OVERRIDE=""
    parse_args --remote-dir /var/uploads user@host
    assert_equal "$REMOTE_DIR_OVERRIDE" "/var/uploads"
}

@test "parse_args: -P / --print-only sets PRINT_ONLY=1" {
    PRINT_ONLY=0
    parse_args --print-only user@host
    assert_equal "$PRINT_ONLY" "1"
}

@test "parse_args: -w / --watch sets WATCH=1" {
    WATCH=0
    parse_args -w user@host
    assert_equal "$WATCH" "1"
}

@test "parse_args: --interval sets WATCH_INTERVAL" {
    WATCH_INTERVAL=2
    parse_args --interval 7 user@host
    assert_equal "$WATCH_INTERVAL" "7"
}

@test "parse_args: HOST_FROM_CLI tracks the positional host" {
    HOST_FROM_CLI=""
    parse_args cli@host
    assert_equal "$HOST_FROM_CLI" "cli@host"
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

@test "compute_remote_filename: uses file basename for source:file: on linux" {
    run compute_remote_filename 1700000000 "source:file:/home/me/diagram.png"
    assert_success
    assert_output "diagram-1700000000.png"
}

@test "compute_remote_filename: falls back to 'clipboard' on linux when source is unknown" {
    run compute_remote_filename 1700000000 ""
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

@test "compute_remote_filename: sanitizes shell metacharacters in the clipboard-derived basename" {
    # Defense in depth: even if a malicious file ends up on the clipboard,
    # the basename interpolated into the remote ssh command must not be
    # able to break out and run arbitrary code.
    OSTYPE="darwin23" run compute_remote_filename 42 'source:file:/tmp/foo";rm -rf ~;echo "x.png'
    assert_success
    refute_output --partial '"'
    refute_output --partial ';'
    refute_output --partial '$'
    refute_output --partial '`'
    refute_output --partial ' '
}

# --- sanitize_filename ------------------------------------------------------

@test "sanitize_filename: leaves safe basenames alone" {
    run sanitize_filename "my-photo.v2_final"
    assert_output "my-photo.v2_final"
}

@test "sanitize_filename: replaces shell metacharacters with underscores" {
    run sanitize_filename 'foo";rm -rf ~;echo "x'
    refute_output --partial '"'
    refute_output --partial ';'
    refute_output --partial ' '
    refute_output --partial '`'
}

@test "sanitize_filename: passes through dots, dashes, and underscores" {
    run sanitize_filename "a.b-c_d.e"
    assert_output "a.b-c_d.e"
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

@test "resolve_remote_dir: --remote-dir override beats env and config" {
    config_set remote_dir /from/config
    REMOTE_DIR_OVERRIDE=/from/flag CLIPSSH_REMOTE_DIR=/from/env \
        run resolve_remote_dir
    assert_success
    assert_output "/from/flag"
}

# --- make_timestamp ---------------------------------------------------------

@test "make_timestamp: produces a sortable UTC stamp" {
    run make_timestamp
    assert_success
    # Must be the ISO form (YYYYMMDDTHHMMSSZ) — the epoch-seconds fallback is
    # only there for busybox `date`, which we don't bless as a supported env.
    [[ "$output" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

# --- format_source_label ----------------------------------------------------

@test "format_source_label: image -> 'screenshot'" {
    run format_source_label "source:image"
    assert_output "screenshot"
}

@test "format_source_label: file -> 'file: <path>'" {
    run format_source_label "source:file:/tmp/x.png"
    assert_output "file: /tmp/x.png"
}

@test "format_source_label: path -> 'path: <path>'" {
    run format_source_label "source:path:/home/x.png"
    assert_output "path: /home/x.png"
}

@test "format_source_label: empty -> 'clipboard'" {
    run format_source_label ""
    assert_output "clipboard"
}

# --- human_size -------------------------------------------------------------

@test "human_size: bytes under 1 KB stay in bytes" {
    run human_size 512
    assert_output "512 B"
}

@test "human_size: medium values format as KB" {
    run human_size 4096
    assert_output "4.0 KB"
}

@test "human_size: large values format as MB" {
    run human_size 1572864
    assert_output "1.5 MB"
}

@test "human_size: uses '.' as the decimal point under non-C locales" {
    # Without the LC_ALL=C pin inside human_size, gawk would emit `1,5 MB`
    # when the user's locale uses a comma as decimal separator. We don't
    # know whether de_DE is installed on the runner, but the assertion is
    # one-sided: there must NEVER be a comma.
    LC_ALL=de_DE.UTF-8 run human_size 1572864
    refute_output --partial ","
    assert_output --partial "."
}

# --- is_supported_image_path ------------------------------------------------

@test "is_supported_image_path: accepts common image extensions case-insensitively" {
    run is_supported_image_path /tmp/x.PNG
    assert_success
    run is_supported_image_path /tmp/x.jpeg
    assert_success
    run is_supported_image_path /tmp/x.webp
    assert_success
}

@test "is_supported_image_path: rejects non-images" {
    run is_supported_image_path /tmp/notes.txt
    assert_failure
    run is_supported_image_path /tmp/noext
    assert_failure
}

# --- load_from_file_source --------------------------------------------------

@test "load_from_file_source: copies the file into TEMP_FILE and sets SOURCE_LINE" {
    TEMP_FILE="$TEST_TMP/dest.png"
    : > "$TEMP_FILE"
    local src="$TEST_TMP/photo.png"
    printf 'pretend-png' > "$src"
    SOURCE_LINE=""
    load_from_file_source "$src"
    assert_equal "$(<"$TEMP_FILE")" "pretend-png"
    assert_equal "$SOURCE_LINE" "source:file:$src"
}

@test "load_from_file_source: errors when file is missing" {
    TEMP_FILE="$TEST_TMP/dest.png"
    run -1 load_from_file_source "$TEST_TMP/does-not-exist.png"
    assert_output --partial "File not found"
}

@test "load_from_file_source: errors when file is empty" {
    TEMP_FILE="$TEST_TMP/dest.png"
    local src="$TEST_TMP/empty.png"
    : > "$src"
    run -1 load_from_file_source "$src"
    assert_output --partial "File is empty"
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

# --- config_set special-character handling ---------------------------------

@test "config_set: preserves '|' on update (the old sed delimiter would corrupt this)" {
    config_set host "initial@host"
    config_set host "user@host|alt"
    assert_equal "$(config_get host)" "user@host|alt"
}

@test "config_set: preserves '&' on update (sed replacement would re-expand it)" {
    config_set remote_dir "/tmp/before"
    config_set remote_dir "/tmp/a&b"
    assert_equal "$(config_get remote_dir)" "/tmp/a&b"
}

@test "config_set: preserves backslashes on update" {
    config_set host "initial@host"
    config_set host 'user@host\name'
    assert_equal "$(config_get host)" 'user@host\name'
}

@test "config_set: overwrites instead of duplicating on repeat" {
    config_set host "first@host"
    config_set host "second@host"
    # Only one host= line should remain in the config file.
    local count
    count=$(grep -c '^host=' "$XDG_CONFIG_HOME/clipssh/config")
    assert_equal "$count" "1"
    assert_equal "$(config_get host)" "second@host"
}

# --- setup_preconditions_met (TTY-independent half of should_offer_setup) --

@test "setup_preconditions_met: returns 0 when nothing is configured and no flags are set" {
    HOST=""
    unset CLIPSSH_HOST
    PRINT_ONLY=0
    WATCH=0
    FILE_SOURCE=""
    SSH_OPTS=()
    REMOTE_DIR_OVERRIDE=""
    run setup_preconditions_met
    assert_success
}

@test "setup_preconditions_met: returns 1 when HOST is set (CLI host given)" {
    HOST="cli@host"
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when CLIPSSH_HOST is set" {
    HOST=""
    CLIPSSH_HOST="env@host" run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when host is saved in config" {
    HOST=""
    config_set host "config@host"
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when --print-only was passed" {
    HOST=""
    PRINT_ONLY=1
    WATCH=0
    FILE_SOURCE=""
    SSH_OPTS=()
    REMOTE_DIR_OVERRIDE=""
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when --watch was passed" {
    HOST=""
    PRINT_ONLY=0
    WATCH=1
    FILE_SOURCE=""
    SSH_OPTS=()
    REMOTE_DIR_OVERRIDE=""
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when --file was passed" {
    HOST=""
    PRINT_ONLY=0
    WATCH=0
    FILE_SOURCE="/tmp/x.png"
    SSH_OPTS=()
    REMOTE_DIR_OVERRIDE=""
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when ssh options were passed" {
    HOST=""
    PRINT_ONLY=0
    WATCH=0
    FILE_SOURCE=""
    SSH_OPTS=(-p 2222)
    REMOTE_DIR_OVERRIDE=""
    run setup_preconditions_met
    assert_failure
}

@test "setup_preconditions_met: returns 1 when --remote-dir was passed" {
    HOST=""
    PRINT_ONLY=0
    WATCH=0
    FILE_SOURCE=""
    SSH_OPTS=()
    REMOTE_DIR_OVERRIDE="/var/uploads"
    run setup_preconditions_met
    assert_failure
}

# --- watch_hash -------------------------------------------------------------

@test "watch_hash: returns a fingerprint of the file" {
    local f="$TEST_TMP/x.bin"
    printf 'abc' > "$f"
    run watch_hash "$f"
    assert_success
    # SHA-1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
    assert_output "a9993e364706816aba3e25717850c26c9cd0d89d"
}

@test "watch_hash: returns a different digest for different bytes" {
    local a="$TEST_TMP/a.bin" b="$TEST_TMP/b.bin"
    printf 'one' > "$a"
    printf 'two' > "$b"
    local ha hb
    ha=$(watch_hash "$a")
    hb=$(watch_hash "$b")
    [[ -n "$ha" && -n "$hb" && "$ha" != "$hb" ]]
}
