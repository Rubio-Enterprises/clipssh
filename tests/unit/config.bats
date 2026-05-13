#!/usr/bin/env bats
#
# Unit tests for the config_get / config_set / config_list functions.
# These are sourced directly from clipssh so we exercise them as a library.

bats_require_minimum_version 1.5.0
load '../helpers/common'

setup() {
    common_setup
    source_clipssh
}

teardown() {
    common_teardown
}

# --- config_get -------------------------------------------------------------

@test "config_get: returns empty when config file does not exist" {
    run config_get host
    assert_success
    assert_output ""
}

@test "config_get: returns the stored value for a known key" {
    config_set host user@example.com
    run config_get host
    assert_success
    assert_output "user@example.com"
}

@test "config_get: returns empty for an unknown key" {
    config_set host user@example.com
    run config_get remote_dir
    assert_success
    assert_output ""
}

@test "config_get: returns the last value if a key appears multiple times" {
    # config_set always rewrites, so to test the tail-1 path we append manually.
    mkdir -p "$XDG_CONFIG_HOME/clipssh"
    cat > "$XDG_CONFIG_HOME/clipssh/config" <<EOF
host=first@host
host=second@host
EOF
    run config_get host
    assert_success
    assert_output "second@host"
}

@test "config_get: preserves '=' characters inside the value" {
    config_set remote_dir "/tmp/dir=with=equals"
    run config_get remote_dir
    assert_success
    assert_output "/tmp/dir=with=equals"
}

# --- config_set -------------------------------------------------------------

@test "config_set: creates the config directory if missing" {
    assert_dir_not_exists "$XDG_CONFIG_HOME/clipssh"
    config_set host user@example.com
    assert_dir_exists "$XDG_CONFIG_HOME/clipssh"
    assert_file_exists "$XDG_CONFIG_HOME/clipssh/config"
}

@test "config_set: appends a new key to an existing config" {
    config_set host user@example.com
    config_set remote_dir /tmp/uploads
    assert_file_contains "$XDG_CONFIG_HOME/clipssh/config" "^host=user@example.com$"
    assert_file_contains "$XDG_CONFIG_HOME/clipssh/config" "^remote_dir=/tmp/uploads$"
}

@test "config_set: rewrites an existing key in place (no duplicates)" {
    config_set host first@host
    config_set host second@host
    run grep -c "^host=" "$XDG_CONFIG_HOME/clipssh/config"
    assert_output "1"
    run config_get host
    assert_output "second@host"
}

@test "config_set: handles values containing slashes (sed delimiter safety)" {
    config_set remote_dir "/var/lib/clipssh/uploads"
    run config_get remote_dir
    assert_output "/var/lib/clipssh/uploads"
    # And rewriting works without breaking the sed expression.
    config_set remote_dir "/tmp/other"
    run config_get remote_dir
    assert_output "/tmp/other"
}

# --- config_list ------------------------------------------------------------

@test "config_list: shows defaults when nothing is configured" {
    run config_list
    assert_success
    assert_output --partial "Config file: $XDG_CONFIG_HOME/clipssh/config"
    assert_line --regexp '^[[:space:]]*host[[:space:]]+= \(not set\)$'
    assert_line --regexp '^[[:space:]]*remote_dir[[:space:]]+= /tmp[[:space:]]+\(default\)$'
}

@test "config_list: marks values from the config file with (config)" {
    config_set host user@example.com
    run config_list
    assert_success
    assert_line --regexp '^[[:space:]]*host[[:space:]]+= user@example\.com[[:space:]]+\(config\)$'
}

@test "config_list: env vars take precedence over config file and are marked (env)" {
    config_set host file@host
    CLIPSSH_HOST=env@host run config_list
    assert_success
    assert_line --regexp '^[[:space:]]*host[[:space:]]+= env@host[[:space:]]+\(env\)$'
}

@test "config_list: env var for remote_dir wins over default" {
    CLIPSSH_REMOTE_DIR=/custom/dir run config_list
    assert_success
    assert_line --regexp '^[[:space:]]*remote_dir[[:space:]]+= /custom/dir[[:space:]]+\(env\)$'
}
