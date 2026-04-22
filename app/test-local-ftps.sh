#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_PROJECT_PREFIX="ftps-local-smoke"
PRESERVE_STACK="${FTPS_TEST_PRESERVE_STACK:-false}"
TEMP_DIR="$(mktemp -d "${SCRIPT_DIR}/.ftps-local-smoke.XXXXXX")"
TEST_TIMESTAMP="$(date +%s)"
ALL_CASES=(pem pkcs12-chain)
KNOWN_COMPOSE_PROJECTS=(
    "${COMPOSE_PROJECT_PREFIX}"
    "${COMPOSE_PROJECT_PREFIX}-pem"
    "${COMPOSE_PROJECT_PREFIX}-pkcs12-chain"
)

CURRENT_COMPOSE_PROJECT_NAME=""
STARTED_COMPOSE_PROJECTS=()
TEST_FILENAME=""
TEST_PAYLOAD=""
UPLOAD_FILE=""
CERTS_DIR=""
CURRENT_CERTIFICATE_PATH=""
SELECTED_CASES=()
CASE_RESULTS=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_CYAN=$'\033[36m'
    COLOR_BOLD=$'\033[1m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_CYAN=""
    COLOR_BOLD=""
    COLOR_RESET=""
fi

print_blank_line() {
    printf '\n'
}

print_banner() {
    local message="$1"

    print_blank_line
    printf '%b%s%b\n' "${COLOR_BOLD}${COLOR_CYAN}" "${message}" "${COLOR_RESET}"
}

print_case_start() {
    local case_name="$1"

    print_blank_line
    printf '%b%s%b\n' "${COLOR_BOLD}${COLOR_CYAN}" "=== START ${case_name} ===" "${COLOR_RESET}"
}

print_case_finish() {
    local case_name="$1"
    local status="$2"
    local color="${COLOR_GREEN}"

    if [[ "${status}" != "PASS" ]]; then
        color="${COLOR_RED}"
    fi

    printf '%b%s%b\n' "${color}${COLOR_BOLD}" "=== FINISH ${case_name}: ${status} ===" "${COLOR_RESET}"
}

record_case_result() {
    local case_name="$1"
    local status="$2"

    CASE_RESULTS+=("${case_name}|${status}")
}

print_summary() {
    local result_entry case_name status color

    print_banner "FTPS local smoke summary"
    printf '%-20s %-8s\n' "Case" "Result"
    printf '%-20s %-8s\n' "--------------------" "--------"

    for result_entry in "${CASE_RESULTS[@]}"; do
        case_name="${result_entry%%|*}"
        status="${result_entry##*|}"
        color="${COLOR_GREEN}"

        if [[ "${status}" != "PASS" ]]; then
            color="${COLOR_RED}"
        fi

        printf '%-20s %b%-8s%b\n' "${case_name}" "${color}${COLOR_BOLD}" "${status}" "${COLOR_RESET}"
    done
}

show_usage() {
    cat <<EOF
Usage: ./test-local-ftps.sh [case ...]

Available cases:
  pem
  pkcs12-chain

Examples:
  ./test-local-ftps.sh
  ./test-local-ftps.sh pem
  ./test-local-ftps.sh pkcs12-chain
EOF
}

validate_case_name() {
    local case_name="$1"
    local known_case

    for known_case in "${ALL_CASES[@]}"; do
        if [[ "${known_case}" == "${case_name}" ]]; then
            return 0
        fi
    done

    echo "Unknown smoke test case: ${case_name}" >&2
    return 1
}

parse_args() {
    local case_name

    if [[ $# -eq 0 ]]; then
        SELECTED_CASES=("${ALL_CASES[@]}")
        return 0
    fi

    for case_name in "$@"; do
        case "${case_name}" in
            -h|--help)
                show_usage
                exit 0
                ;;
        esac

        validate_case_name "${case_name}" || exit 1
        SELECTED_CASES+=("${case_name}")
    done
}

compose() {
    docker compose -p "${CURRENT_COMPOSE_PROJECT_NAME}" -f "${SCRIPT_DIR}/docker-compose.yaml" "$@"
}

compose_down() {
    if [[ -z "${CURRENT_COMPOSE_PROJECT_NAME}" ]]; then
        return 0
    fi

    compose down -v --remove-orphans >/dev/null 2>&1 || true
}

cleanup_known_smoke_projects() {
    local project_name

    for project_name in "${KNOWN_COMPOSE_PROJECTS[@]}"; do
        CURRENT_COMPOSE_PROJECT_NAME="${project_name}"
        compose_down
    done
}

cleanup() {
    if [[ "${PRESERVE_STACK}" == "true" ]]; then
        echo "Preserving local smoke stack for inspection" >&2
        printf 'Compose projects:%s\n' "" >&2
        printf '  %s\n' "${STARTED_COMPOSE_PROJECTS[@]}" >&2
        echo "Temporary directory: ${TEMP_DIR}" >&2
        return 0
    fi

    cleanup_known_smoke_projects

    if [[ ${#STARTED_COMPOSE_PROJECTS[@]} -gt 0 ]]; then
        local project_name

        for project_name in "${STARTED_COMPOSE_PROJECTS[@]}"; do
            CURRENT_COMPOSE_PROJECT_NAME="${project_name}"
            compose_down
        done
    fi

    rm -rf "${TEMP_DIR}"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

wait_for_ftps() {
    local attempt
    for attempt in $(seq 1 30); do
        if echo | openssl s_client -connect 127.0.0.1:990 -tls1_2 >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done

    echo "FTPS service did not become ready in time" >&2
    compose logs ftps >&2 || true
    return 1
}

wait_for_forwarded_file() {
    local attempt
    for attempt in $(seq 1 30); do
        if compose exec -T sftp-target sh -lc "test -f /home/sftpuser/dropoff/${TEST_FILENAME}"; then
            return 0
        fi
        sleep 2
    done

    echo "Forwarded file did not appear on the SFTP target in time" >&2
    compose logs ftps >&2 || true
    return 1
}

base64_no_wrap() {
    openssl base64 -A -in "$1"
}

prepare_pem_case() {
    local case_dir="$1"

    CERTS_DIR="${case_dir}/certs"
    mkdir -p "${CERTS_DIR}"

    openssl req -x509 -newkey rsa:2048 \
        -keyout "${CERTS_DIR}/server.key" \
        -out "${CERTS_DIR}/server.crt" \
        -sha256 -days 1 -nodes \
        -subj '/CN=ftps.local' >/dev/null 2>&1
    cat "${CERTS_DIR}/server.key" "${CERTS_DIR}/server.crt" > "${CERTS_DIR}/ftps.pem"

    export FTPS_CERTS_DIR="${CERTS_DIR}"
    unset FTPS_CERTIFICATE_PEM
    unset FTPS_CERTIFICATE_KEY_PEM
    unset FTPS_CERTIFICATE_PKCS12_PASSWORD
    unset FTPS_CERTIFICATE_PATH

    CURRENT_CERTIFICATE_PATH="/certs/ftps.pem"
}

prepare_pkcs12_chain_case() {
    local case_dir="$1"
    local bundle_file fixture_file

    CERTS_DIR="${case_dir}/certs"
    bundle_file="${case_dir}/server-chain.p12"
    mkdir -p "${CERTS_DIR}"

    fixture_file="${FTPS_TEST_PKCS12_CHAIN_BUNDLE_FILE:-}"
    if [[ -n "${fixture_file}" ]]; then
        if [[ ! -f "${fixture_file}" ]]; then
            echo "PKCS12 chain fixture file not found: ${fixture_file}" >&2
            return 1
        fi

        cp "${fixture_file}" "${bundle_file}"
    else
        openssl req -x509 -newkey rsa:2048 \
            -keyout "${CERTS_DIR}/ca.key" \
            -out "${CERTS_DIR}/ca.crt" \
            -sha256 -days 1 -nodes \
            -subj '/CN=ftps.local-test-ca' >/dev/null 2>&1
        openssl req -new -newkey rsa:2048 \
            -keyout "${CERTS_DIR}/server.key" \
            -nodes \
            -out "${CERTS_DIR}/server.csr" \
            -subj '/CN=ftps.local-pkcs12-chain' >/dev/null 2>&1
        openssl x509 -req \
            -in "${CERTS_DIR}/server.csr" \
            -CA "${CERTS_DIR}/ca.crt" \
            -CAkey "${CERTS_DIR}/ca.key" \
            -CAcreateserial \
            -out "${CERTS_DIR}/server.crt" \
            -days 1 \
            -sha256 >/dev/null 2>&1
        openssl pkcs12 -export \
            -out "${bundle_file}" \
            -inkey "${CERTS_DIR}/server.key" \
            -in "${CERTS_DIR}/server.crt" \
            -certfile "${CERTS_DIR}/ca.crt" \
            -passout pass: >/dev/null 2>&1
    fi

    export FTPS_CERTS_DIR="${CERTS_DIR}"
    export FTPS_CERTIFICATE_PATH="/etc/proftpd/tls/ftps.pem"
    export FTPS_CERTIFICATE_PEM="$(base64_no_wrap "${bundle_file}")"
    unset FTPS_CERTIFICATE_KEY_PEM
    unset FTPS_CERTIFICATE_PKCS12_PASSWORD

    CURRENT_CERTIFICATE_PATH="${FTPS_CERTIFICATE_PATH}"
}

assert_container_logs_contain() {
    local expected_message="$1"
    local container_logs

    container_logs="$(compose logs ftps 2>&1 || true)"

    if ! grep -Fq "${expected_message}" <<<"${container_logs}"; then
        echo "Expected FTPS logs to contain: ${expected_message}" >&2
        printf '%s\n' "${container_logs}" >&2
        return 1
    fi
}

assert_certificate_blocks() {
    local expected_private_keys="$1"
    local expected_certificates="$2"
    local actual_private_keys actual_certificates

    actual_private_keys="$(compose exec -T ftps sh -lc "grep -Ec 'BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY' '${CURRENT_CERTIFICATE_PATH}'")"
    actual_certificates="$(compose exec -T ftps sh -lc "grep -c 'BEGIN CERTIFICATE' '${CURRENT_CERTIFICATE_PATH}'")"

    if [[ "${actual_private_keys}" != "${expected_private_keys}" || "${actual_certificates}" != "${expected_certificates}" ]]; then
        echo "Generated certificate PEM blocks did not match expected counts" >&2
        echo "Expected private keys: ${expected_private_keys}" >&2
        echo "Actual private keys:   ${actual_private_keys}" >&2
        echo "Expected certificates: ${expected_certificates}" >&2
        echo "Actual certificates:   ${actual_certificates}" >&2
        compose exec -T ftps sh -lc "grep 'BEGIN ' '${CURRENT_CERTIFICATE_PATH}'" >&2 || true
        return 1
    fi
}

run_smoke_case() {
    local case_name="$1"
    local case_dir="${TEMP_DIR}/${case_name}"
    local project_name="${COMPOSE_PROJECT_PREFIX}-${case_name}"

    CURRENT_COMPOSE_PROJECT_NAME="${project_name}"
    STARTED_COMPOSE_PROJECTS+=("${project_name}")
    TEST_FILENAME="ftps-smoke-${case_name}-${TEST_TIMESTAMP}.txt"
    TEST_PAYLOAD="local ftps smoke ${case_name} $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UPLOAD_FILE="${case_dir}/${TEST_FILENAME}"

    mkdir -p "${case_dir}"

    case "${case_name}" in
        pem)
            prepare_pem_case "${case_dir}"
            ;;
        pkcs12-chain)
            prepare_pkcs12_chain_case "${case_dir}"
            ;;
        *)
            echo "Unknown smoke test case: ${case_name}" >&2
            return 1
            ;;
    esac

    cleanup_known_smoke_projects
    compose up -d --build

    wait_for_ftps

    if [[ "${case_name}" == pkcs12-* ]]; then
        assert_container_logs_contain "Certificate content does not look like PEM; attempting PKCS12 conversion"
        assert_container_logs_contain "PKCS12 conversion completed and PEM bundle written"
    fi

    case "${case_name}" in
        pem)
            assert_certificate_blocks 1 1
            ;;
        pkcs12-chain)
            assert_certificate_blocks 1 2
            ;;
    esac

    printf '%s\n' "${TEST_PAYLOAD}" > "${UPLOAD_FILE}"
    curl -k --silent --show-error --ssl-reqd \
        --user "ftpssvc:${FTPS_LOCAL_PASSWORD}" \
        --ftp-pasv \
        --upload-file "${UPLOAD_FILE}" \
        "ftps://127.0.0.1:990/upload/${TEST_FILENAME}"

    wait_for_forwarded_file

    FORWARDED_PAYLOAD="$(compose exec -T sftp-target sh -lc "cat /home/sftpuser/dropoff/${TEST_FILENAME}")"

    if [[ "${FORWARDED_PAYLOAD}" != "${TEST_PAYLOAD}" ]]; then
        echo "Forwarded file contents do not match uploaded payload" >&2
        echo "Expected: ${TEST_PAYLOAD}" >&2
        echo "Actual:   ${FORWARDED_PAYLOAD}" >&2
        return 1
    fi

    if [[ "${PRESERVE_STACK}" != "true" ]]; then
        compose_down
    fi
}

require_command docker
require_command openssl
require_command curl

trap cleanup EXIT

parse_args "$@"

export FTPS_LOCAL_PASSWORD="localpass123!"
export FTPS_FORWARD_INTERVAL_SECONDS="${FTPS_FORWARD_INTERVAL_SECONDS:-2}"

print_banner "FTPS local smoke test"
printf 'Selected cases: %s\n' "${SELECTED_CASES[*]}"

overall_status=0

for case_name in "${SELECTED_CASES[@]}"; do
    print_case_start "${case_name}"

    if run_smoke_case "${case_name}"; then
        record_case_result "${case_name}" "PASS"
        print_case_finish "${case_name}" "PASS"
    else
        record_case_result "${case_name}" "FAIL"
        print_case_finish "${case_name}" "FAIL"
        overall_status=1
    fi
done

print_summary

if [[ "${overall_status}" -eq 0 ]]; then
    print_blank_line
    printf '%b%s%b\n' "${COLOR_GREEN}${COLOR_BOLD}" "FTPS local smoke test passed" "${COLOR_RESET}"
else
    print_blank_line
    printf '%b%s%b\n' "${COLOR_RED}${COLOR_BOLD}" "FTPS local smoke test failed" "${COLOR_RESET}"
fi

printf 'Verified cases: %s\n' "${SELECTED_CASES[*]}"

exit "${overall_status}"