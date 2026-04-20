#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_PROJECT_NAME="ftps-local-smoke"
COMPOSE_ARGS=(-p "${COMPOSE_PROJECT_NAME}" -f "${SCRIPT_DIR}/docker-compose.yaml")
TEST_FILENAME="ftps-smoke-$(date +%s).txt"
TEST_PAYLOAD="local ftps smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRESERVE_STACK="${FTPS_TEST_PRESERVE_STACK:-false}"
TEMP_DIR="$(mktemp -d "${SCRIPT_DIR}/.ftps-local-smoke.XXXXXX")"
UPLOAD_FILE="${TEMP_DIR}/${TEST_FILENAME}"
CERTS_DIR="${TEMP_DIR}/certs"

compose_down() {
    docker compose "${COMPOSE_ARGS[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}

cleanup() {
    if [[ "${PRESERVE_STACK}" == "true" ]]; then
        echo "Preserving local smoke stack for inspection" >&2
        echo "Compose project: ${COMPOSE_PROJECT_NAME}" >&2
        echo "Temporary directory: ${TEMP_DIR}" >&2
        return 0
    fi

    compose_down
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
    docker compose "${COMPOSE_ARGS[@]}" logs ftps >&2 || true
    return 1
}

wait_for_forwarded_file() {
    local attempt
    for attempt in $(seq 1 30); do
        if docker compose "${COMPOSE_ARGS[@]}" exec -T sftp-target sh -lc "test -f /home/sftpuser/dropoff/${TEST_FILENAME}"; then
            return 0
        fi
        sleep 2
    done

    echo "Forwarded file did not appear on the SFTP target in time" >&2
    docker compose "${COMPOSE_ARGS[@]}" logs ftps >&2 || true
    return 1
}

require_command docker
require_command openssl
require_command curl

trap cleanup EXIT

mkdir -p "${CERTS_DIR}"

openssl req -x509 -newkey rsa:2048 \
    -keyout "${CERTS_DIR}/server.key" \
    -out "${CERTS_DIR}/server.crt" \
    -sha256 -days 1 -nodes \
    -subj '/CN=ftps.local' >/dev/null 2>&1
cat "${CERTS_DIR}/server.key" "${CERTS_DIR}/server.crt" > "${CERTS_DIR}/ftps.pem"

export FTPS_LOCAL_PASSWORD="localpass123!"
export FTPS_CERTS_DIR="${CERTS_DIR}"
export FTPS_FORWARD_INTERVAL_SECONDS="${FTPS_FORWARD_INTERVAL_SECONDS:-2}"

compose_down
docker compose "${COMPOSE_ARGS[@]}" up -d --build

wait_for_ftps

printf '%s\n' "${TEST_PAYLOAD}" > "${UPLOAD_FILE}"
curl -k --silent --show-error --ssl-reqd \
    --user "ftpssvc:${FTPS_LOCAL_PASSWORD}" \
    --ftp-pasv \
    --upload-file "${UPLOAD_FILE}" \
    "ftps://127.0.0.1:990/upload/${TEST_FILENAME}"

wait_for_forwarded_file

FORWARDED_PAYLOAD="$(docker compose "${COMPOSE_ARGS[@]}" exec -T sftp-target sh -lc "cat /home/sftpuser/dropoff/${TEST_FILENAME}")"

if [[ "${FORWARDED_PAYLOAD}" != "${TEST_PAYLOAD}" ]]; then
    echo "Forwarded file contents do not match uploaded payload" >&2
    echo "Expected: ${TEST_PAYLOAD}" >&2
    echo "Actual:   ${FORWARDED_PAYLOAD}" >&2
    exit 1
fi

echo "FTPS local smoke test passed"
echo "Uploaded file: ${TEST_FILENAME}"
echo "Forwarded payload verified on SFTP target"