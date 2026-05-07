#!/usr/bin/env bats

load './test_helper.bash'

setup() {
    common_setup

    export FTPS_FORWARD_LOCAL_DIR="${TEST_TMPDIR}/upload"
    mkdir -p "${FTPS_FORWARD_LOCAL_DIR}"

    # shellcheck source=../../lib/ftps-storage-forward.sh
    source "${BATS_TEST_DIRNAME}/../../lib/ftps-storage-forward.sh"
    ftps_forward_reset_targets
}

teardown() {
    common_teardown
}

@test "urlencode escapes reserved characters used in passwords" {
    run urlencode 'p@ss word:+/'

    [ "${status}" -eq 0 ]
    [ "${output}" = 'p%40ss%20word%3A%2B%2F' ]
}

@test "append_target skips incomplete targets" {
    append_target 'missing-host' '' '22' 'user' 'password' '.'

    [ "${#target_hosts[@]}" -eq 0 ]
}

@test "append_target skips invalid target ports" {
    append_target 'bad-port' 'sftp-a' '70000' 'user' 'password' '.'

    [ "${#target_hosts[@]}" -eq 0 ]
}

@test "append_target skips remote directories unsafe for lftp commands" {
    append_target 'bad-remote-dir' 'sftp-a' '22' 'user' 'password' 'drop"off'

    [ "${#target_hosts[@]}" -eq 0 ]
}

@test "discover_targets prefers indexed forwarding targets" {
    export FTPS_FORWARD_TARGET_COUNT='2'
    export FTPS_FORWARD_TARGET_0_NAME='primary'
    export FTPS_FORWARD_TARGET_0_HOST='sftp-a'
    export FTPS_FORWARD_TARGET_0_PORT='22'
    export FTPS_FORWARD_TARGET_0_USERNAME='alice'
    export FTPS_FORWARD_TARGET_0_PASSWORD='secret-a'
    export FTPS_FORWARD_TARGET_0_REMOTE_DIR='/drop/a'
    export FTPS_FORWARD_TARGET_1_NAME='secondary'
    export FTPS_FORWARD_TARGET_1_HOST='sftp-b'
    export FTPS_FORWARD_TARGET_1_PORT='2022'
    export FTPS_FORWARD_TARGET_1_USERNAME='bob'
    export FTPS_FORWARD_TARGET_1_PASSWORD='secret-b'
    export FTPS_FORWARD_TARGET_1_REMOTE_DIR='/drop/b'

    discover_targets

    [ "${#target_hosts[@]}" -eq 2 ]
    [ "${target_names[0]}" = 'primary' ]
    [ "${target_ports[1]}" = '2022' ]
}

@test "discover_targets falls back to legacy single-target variables" {
    unset FTPS_FORWARD_TARGET_COUNT
    export FTPS_STORAGE_SFTP_HOST='legacy-host'
    export FTPS_STORAGE_SFTP_PORT='22'
    export FTPS_STORAGE_SFTP_USERNAME='legacy-user'
    export FTPS_STORAGE_SFTP_PASSWORD='legacy-pass'
    export FTPS_STORAGE_SFTP_REMOTE_DIR='/legacy'

    discover_targets

    [ "${#target_hosts[@]}" -eq 1 ]
    [ "${target_names[0]}" = 'storage' ]
    [ "${target_remote_dirs[0]}" = '/legacy' ]
}

@test "forward_to_target encodes credentials and passes the remove-source flag to lftp" {
    printf 'payload' >"${FTPS_FORWARD_LOCAL_DIR}/payload.txt"

    create_stub_command \
        'lftp' \
        'printf "%s\n" "$*" >"${TEST_TMPDIR}/lftp.args"; cat >"${TEST_TMPDIR}/lftp.stdin"; printf "mirror-complete\n"'

    run forward_to_target \
        'primary' \
        'sftp.example' \
        '2022' \
        'user@example' \
        'p@ss word:+/' \
        '/drop' \
        '--Remove-source-files'

    [ "${status}" -eq 0 ]
    grep -q 'sftp://user%40example:p%40ss%20word%3A%2B%2F@sftp.example:2022' "${TEST_TMPDIR}/lftp.args"
    grep -q -- '--Remove-source-files' "${TEST_TMPDIR}/lftp.stdin"
    grep -q '"/drop"' "${TEST_TMPDIR}/lftp.stdin"
}

@test "ftps_storage_forward_main rejects local directories unsafe for lftp commands" {
    export FTPS_FORWARD_LOCAL_DIR="${TEST_TMPDIR}/bad\"upload"
    mkdir -p "${FTPS_FORWARD_LOCAL_DIR}"
    printf 'payload' >"${FTPS_FORWARD_LOCAL_DIR}/payload.txt"

    run ftps_storage_forward_main

    [ "${status}" -ne 0 ]
}