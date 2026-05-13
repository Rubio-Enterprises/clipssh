#!/usr/bin/env bats
#
# Unit tests for extract_clipboard_image. macOS path drives clipssh-paste and
# reads SOURCE_LINE off stderr; Linux path drives PASTE_CMD.

bats_require_minimum_version 1.5.0
load '../helpers/common'

setup() {
    common_setup
    source_clipssh
    TEMP_FILE="$TEST_TMP/clip.png"
    STDERR_FILE="$TEST_TMP/clip.err"
    : > "$STDERR_FILE"
    SOURCE_LINE=""
}

teardown() {
    common_teardown
}

# --- Linux path -------------------------------------------------------------

@test "extract_clipboard_image: linux writes the paste output to TEMP_FILE" {
    install_mock xclip "printf 'png-bytes-from-linux'"
    PASTE_CMD="xclip -selection clipboard -target image/png -o"

    extract_clipboard_image
    assert_equal "$(<"$TEMP_FILE")" "png-bytes-from-linux"
}

@test "extract_clipboard_image: linux errors when PASTE_CMD fails" {
    install_mock xclip "exit 1"
    PASTE_CMD="xclip -selection clipboard -target image/png -o"

    run -1 extract_clipboard_image
    assert_output --partial "No image in clipboard"
}

@test "extract_clipboard_image: errors when the produced file is empty" {
    install_mock xclip "exit 0"
    PASTE_CMD="xclip -selection clipboard -target image/png -o"

    run -1 extract_clipboard_image
    assert_output --partial "Clipboard image is empty"
}

# --- macOS path -------------------------------------------------------------

@test "extract_clipboard_image: macOS captures stdout to TEMP_FILE and SOURCE_LINE from stderr" {
    install_mock clipssh-paste "$(cat <<'EOF'
printf 'png-from-mac'
echo 'source:file:/Users/me/photo.png' >&2
EOF
)"
    OSTYPE="darwin23"
    extract_clipboard_image
    assert_equal "$(<"$TEMP_FILE")" "png-from-mac"
    assert_equal "$SOURCE_LINE" "source:file:/Users/me/photo.png"
}

@test "extract_clipboard_image: macOS uses only the last stderr line as the source" {
    install_mock clipssh-paste "$(cat <<'EOF'
printf 'data'
echo 'noisy diagnostic' >&2
echo 'source:image' >&2
EOF
)"
    OSTYPE="darwin23"
    extract_clipboard_image
    assert_equal "$SOURCE_LINE" "source:image"
}

@test "extract_clipboard_image: macOS propagates clipssh-paste's last stderr line as the error" {
    install_mock clipssh-paste "$(cat <<'EOF'
echo 'Failed to read image file: /missing.png' >&2
exit 1
EOF
)"
    OSTYPE="darwin23"
    run -1 extract_clipboard_image
    assert_output --partial "Failed to read image file: /missing.png"
}
