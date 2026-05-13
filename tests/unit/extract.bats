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

# --- Linux: file URI on clipboard ------------------------------------------

@test "extract_linux_file_reference: copies file from text/uri-list and sets SOURCE_LINE" {
    local src="$TEST_TMP/photo.png"
    printf 'png-from-uri-list' > "$src"
    install_mock xclip "$(cat <<EOF
for arg in "\$@"; do
    if [[ "\$arg" == "TARGETS" ]]; then
        printf 'TARGETS\ntext/uri-list\nUTF8_STRING\n'
        exit 0
    fi
    if [[ "\$arg" == "text/uri-list" ]]; then
        printf 'file://%s\n' "$src"
        exit 0
    fi
done
exit 1
EOF
)"
    SOURCE_LINE=""
    extract_linux_file_reference
    assert_equal "$(<"$TEMP_FILE")" "png-from-uri-list"
    assert_equal "$SOURCE_LINE" "source:file:$src"
}

@test "extract_linux_file_reference: returns 1 when TARGETS lacks text/uri-list" {
    install_mock xclip "$(cat <<'EOF'
for arg in "$@"; do
    if [[ "$arg" == "TARGETS" ]]; then
        printf 'TARGETS\nUTF8_STRING\n'
        exit 0
    fi
done
exit 1
EOF
)"
    run extract_linux_file_reference
    assert_failure
}

@test "extract_linux_file_reference: returns 1 when xclip is not installed" {
    # MOCK_BIN has no xclip; PATH falls back to coreutils-only.
    run extract_linux_file_reference
    assert_failure
}

@test "extract_linux_file_reference: rejects non-image extensions" {
    local src="$TEST_TMP/notes.txt"
    printf 'plain text' > "$src"
    install_mock xclip "$(cat <<EOF
for arg in "\$@"; do
    if [[ "\$arg" == "TARGETS" ]]; then
        printf 'TARGETS\ntext/uri-list\n'
        exit 0
    fi
    if [[ "\$arg" == "text/uri-list" ]]; then
        printf 'file://%s\n' "$src"
        exit 0
    fi
done
exit 1
EOF
)"
    run extract_linux_file_reference
    assert_failure
}

# --- Linux: text path on clipboard -----------------------------------------

@test "extract_linux_text_path: copies file when clipboard contains a plain image path" {
    local src="$TEST_TMP/screenshot.png"
    printf 'png-from-text-path' > "$src"
    install_mock xclip "$(cat <<EOF
for arg in "\$@"; do
    if [[ "\$arg" == "TARGETS" ]]; then
        # No text/uri-list -> file-reference detection fails, text-path runs.
        printf 'UTF8_STRING\n'
        exit 0
    fi
done
printf '%s' "$src"
EOF
)"
    SOURCE_LINE=""
    extract_linux_text_path
    assert_equal "$(<"$TEMP_FILE")" "png-from-text-path"
    assert_equal "$SOURCE_LINE" "source:path:$src"
}

@test "extract_linux_text_path: ignores multi-line clipboard text" {
    install_mock xclip "printf 'line1\nline2\n'"
    run extract_linux_text_path
    assert_failure
}

@test "extract_linux_text_path: ignores text that isn't an absolute or ~-prefixed path" {
    install_mock xclip "printf 'hello world'"
    run extract_linux_text_path
    assert_failure
}

@test "extract_linux_text_path: strips surrounding single quotes" {
    local src="$TEST_TMP/img.png"
    printf 'png' > "$src"
    install_mock xclip "printf \"'%s'\" \"$src\""
    SOURCE_LINE=""
    extract_linux_text_path
    assert_equal "$SOURCE_LINE" "source:path:$src"
}
