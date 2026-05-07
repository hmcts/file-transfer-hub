#!/usr/bin/env bats

load './test_helper.bash'

setup() {
    common_setup
    create_combined_pem_fixture

    ftps_log() {
        :
    }

    ftps_warn() {
        :
    }

    install() {
        mkdir -p "${@: -1}"
    }

    chown() {
        :
    }

    chmod() {
        :
    }

    export FTPS_CERTIFICATE_PATH="${TEST_TMPDIR}/normalized.pem"
    export FTPS_CERTIFICATE_PKCS12_PASSWORD=""
    export FTPS_CERTIFICATE_GROUP="$(id -gn)"
    export FTPS_TLS_CHAIN_DIRECTIVE=""

    # shellcheck source=../../lib/ftps-entrypoint-certificates.sh
    source "${BATS_TEST_DIRNAME}/../../lib/ftps-entrypoint-certificates.sh"
}

teardown() {
    common_teardown
}

@test "extracts the private key block from a combined pem bundle" {
    run ftps_extract_private_key_block \
        "${TEST_TMPDIR}/combined.pem" \
        "${TEST_TMPDIR}/extracted.key"

    [ "${status}" -eq 0 ]
    grep -Eq 'BEGIN (RSA )?PRIVATE KEY' "${TEST_TMPDIR}/extracted.key"
}

@test "matches the correct certificate to the extracted private key" {
    ftps_extract_private_key_block \
        "${TEST_TMPDIR}/combined.pem" \
        "${TEST_TMPDIR}/extracted.key"

    ftps_extract_certificate_blocks \
        "${TEST_TMPDIR}/combined.pem" \
        "${TEST_TMPDIR}/cert"

    run ftps_certificate_matches_private_key \
        "${TEST_TMPDIR}/cert.2" \
        "${TEST_TMPDIR}/extracted.key"
    [ "${status}" -eq 0 ]

    run ftps_certificate_matches_private_key \
        "${TEST_TMPDIR}/cert.1" \
        "${TEST_TMPDIR}/extracted.key"
    [ "${status}" -ne 0 ]
}

@test "normalizes a pem bundle so the matching leaf certificate comes first" {
    run ftps_normalize_pem_bundle \
        "${TEST_TMPDIR}/combined.pem" \
        "${TEST_TMPDIR}/normalized.pem"

    [ "${status}" -eq 0 ]
    [ "$(grep -c 'BEGIN CERTIFICATE' "${TEST_TMPDIR}/normalized.pem")" -eq 2 ]

    extract_nth_certificate \
        "${TEST_TMPDIR}/normalized.pem" \
        1 \
        "${TEST_TMPDIR}/normalized-first.crt"

    [ "$(certificate_fingerprint "${TEST_TMPDIR}/normalized-first.crt")" = "$(certificate_fingerprint "${TEST_TMPDIR}/leaf.crt")" ]
}

@test "prepares a separate ProFTPD chain file when extra certificates are present" {
    ftps_prepare_proftpd_tls_material \
        "${TEST_TMPDIR}/combined.pem" \
        "${TEST_TMPDIR}/runtime/server.pem" \
        "${TEST_TMPDIR}/runtime/chain.pem"

    [ -f "${TEST_TMPDIR}/runtime/server.pem" ]
    [ -f "${TEST_TMPDIR}/runtime/chain.pem" ]
    [ "$(grep -c 'BEGIN CERTIFICATE' "${TEST_TMPDIR}/runtime/chain.pem")" -eq 1 ]
    [ "${FTPS_TLS_CHAIN_DIRECTIVE}" = "  TLSCertificateChainFile       ${TEST_TMPDIR}/runtime/chain.pem" ]

    extract_nth_certificate \
        "${TEST_TMPDIR}/runtime/server.pem" \
        1 \
        "${TEST_TMPDIR}/runtime/server-first.crt"

    [ "$(certificate_fingerprint "${TEST_TMPDIR}/runtime/server-first.crt")" = "$(certificate_fingerprint "${TEST_TMPDIR}/leaf.crt")" ]
}