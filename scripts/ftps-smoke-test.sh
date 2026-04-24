#!/usr/bin/env bash
set -euo pipefail

readonly FTPS_SMOKE_PORT="${FTPS_SMOKE_PORT:-990}"
readonly FTPS_SMOKE_USERNAME_SECRET_NAME="${FTPS_SMOKE_USERNAME_SECRET_NAME:-ftps-local-username}"
readonly FTPS_SMOKE_PASSWORD_SECRET_NAME="${FTPS_SMOKE_PASSWORD_SECRET_NAME:-ftps-local-password}"
readonly FTPS_SMOKE_LIST_PATH="${FTPS_SMOKE_LIST_PATH:-upload/}"
readonly FTPS_SMOKE_CERT_VALIDITY_WINDOW_SECONDS="${FTPS_SMOKE_CERT_VALIDITY_WINDOW_SECONDS:-0}"

readonly CHECK_CONTAINER_STATE="FTPS container app state is available after deployment"
readonly CHECK_DNS="FTPS public FQDN resolves in DNS"
readonly CHECK_TCP="FTPS is reachable on control port 990"
readonly CHECK_TLS="FTPS responds to a TLS handshake on port 990"
readonly CHECK_CERT_HOSTNAME="FTPS presents a certificate on port 990 that matches the expected public hostname"
readonly CHECK_CERT_VALIDITY="FTPS presents a certificate on port 990 that is within its validity period"
readonly CHECK_LOGIN="FTPS login succeeds with credentials fetched from Key Vault"
readonly CHECK_LIST="FTPS returns a remote directory listing after successful login"

pass_count=0
fail_count=0
skip_count=0
overall_status=0

cert_file=""
sclient_output_file=""

container_name=""
provisioning_state=""
running_status=""
latest_ready_revision=""

dns_ok=false
tcp_ok=false
tls_ok=false
credentials_ok=false
login_ok=false

ftps_username=""
ftps_password=""

pass_check() {
  local label="$1"
  local detail="$2"

  pass_count=$((pass_count + 1))
  printf 'PASS: %s - %s\n' "${label}" "${detail}"
}

fail_check() {
  local label="$1"
  local detail="$2"

  fail_count=$((fail_count + 1))
  overall_status=1
  printf 'FAIL: %s - %s\n' "${label}" "${detail}"
  echo "##vso[task.logissue type=warning]${label}: ${detail}"
}

skip_check() {
  local label="$1"
  local detail="$2"

  skip_count=$((skip_count + 1))
  printf 'SKIP: %s - %s\n' "${label}" "${detail}"
}

require_env() {
  local required_var="$1"

  if [[ -z "${!required_var:-}" ]]; then
    echo "##vso[task.logissue type=warning]Missing required environment variable: ${required_var}"
    exit 1
  fi
}

require_tool() {
  local tool_name="$1"

  if ! command -v "${tool_name}" >/dev/null 2>&1; then
    echo "##vso[task.logissue type=warning]Required tool not found: ${tool_name}"
    exit 1
  fi
}

validate_prerequisites() {
  local required_vars=(
    FTPS_SMOKE_FQDN
    FTPS_SMOKE_CONTAINER_APP_ID
    FTPS_SMOKE_KEY_VAULT_NAME
  )
  local tools=(az curl openssl python3)
  local required_var
  local tool_name

  for required_var in "${required_vars[@]}"; do
    require_env "${required_var}"
  done

  for tool_name in "${tools[@]}"; do
    require_tool "${tool_name}"
  done
}

cleanup() {
  rm -f "${cert_file}" "${sclient_output_file}"
}

prepare_runtime() {
  cert_file="$(mktemp)"
  sclient_output_file="$(mktemp)"

  trap cleanup EXIT
  az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
}

run_python() {
  local script="$1"
  shift

  python3 - "$@" <<PY
${script}
PY
}

fetch_container_app_state() {
  container_name="$(az resource show --ids "${FTPS_SMOKE_CONTAINER_APP_ID}" --query name -o tsv 2>/dev/null || true)"
  provisioning_state="$(az containerapp show --ids "${FTPS_SMOKE_CONTAINER_APP_ID}" --query properties.provisioningState -o tsv 2>/dev/null || true)"
  running_status="$(az containerapp show --ids "${FTPS_SMOKE_CONTAINER_APP_ID}" --query properties.runningStatus -o tsv 2>/dev/null || true)"
  latest_ready_revision="$(az containerapp show --ids "${FTPS_SMOKE_CONTAINER_APP_ID}" --query properties.latestReadyRevisionName -o tsv 2>/dev/null || true)"
}

report_container_app_state() {
  fetch_container_app_state

  if [[ -n "${container_name}" && "${provisioning_state}" == "Succeeded" && ( -z "${running_status}" || "${running_status}" == "Running" ) ]]; then
    pass_check "${CHECK_CONTAINER_STATE}" "name=${container_name}, provisioningState=${provisioning_state}, runningStatus=${running_status:-unknown}, latestReadyRevision=${latest_ready_revision:-unknown}"
    return
  fi

  fail_check "${CHECK_CONTAINER_STATE}" "name=${container_name:-unknown}, provisioningState=${provisioning_state:-unknown}, runningStatus=${running_status:-unknown}, latestReadyRevision=${latest_ready_revision:-unknown}"
}

resolve_dns() {
  run_python '
import socket
import sys

hostname = sys.argv[1]
addresses = sorted({item[4][0] for item in socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM)})
print(", ".join(addresses))
' "${FTPS_SMOKE_FQDN}" 2>/dev/null
}

check_dns() {
  local dns_output

  if dns_output="$(resolve_dns)" && [[ -n "${dns_output}" ]]; then
    dns_ok=true
    pass_check "${CHECK_DNS}" "${FTPS_SMOKE_FQDN} -> ${dns_output}"
    return
  fi

  dns_ok=false
  fail_check "${CHECK_DNS}" "${FTPS_SMOKE_FQDN} did not resolve"
}

probe_tcp_port() {
  run_python '
import socket
import sys

hostname = sys.argv[1]
port = int(sys.argv[2])

with socket.create_connection((hostname, port), timeout=5):
    pass

print(f"{hostname}:{port} reachable")
' "${FTPS_SMOKE_FQDN}" "${FTPS_SMOKE_PORT}" 2>/dev/null
}

check_tcp_reachability() {
  local tcp_result

  if [[ "${dns_ok}" != "true" ]]; then
    skip_check "${CHECK_TCP}" "DNS resolution failed"
    tcp_ok=false
    return
  fi

  if tcp_result="$(probe_tcp_port)"; then
    tcp_ok=true
    pass_check "${CHECK_TCP}" "${tcp_result}"
    return
  fi

  tcp_ok=false
  fail_check "${CHECK_TCP}" "${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT} did not accept a TCP connection"
}

extract_first_certificate() {
  awk '
    /-----BEGIN CERTIFICATE-----/ {
      capture=1
    }
    capture {
      print
    }
    /-----END CERTIFICATE-----/ {
      exit
    }
  ' "${sclient_output_file}" > "${cert_file}"
}

perform_tls_handshake() {
  echo | openssl s_client \
    -connect "${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}" \
    -servername "${FTPS_SMOKE_FQDN}" \
    -showcerts \
    > "${sclient_output_file}" 2>/dev/null
}

check_tls_handshake() {
  if [[ "${tcp_ok}" != "true" ]]; then
    skip_check "${CHECK_TLS}" "TCP reachability failed"
    tls_ok=false
    return
  fi

  if ! perform_tls_handshake; then
    tls_ok=false
    fail_check "${CHECK_TLS}" "TLS handshake failed on ${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}"
    return
  fi

  extract_first_certificate

  if [[ -s "${cert_file}" ]]; then
    tls_ok=true
    pass_check "${CHECK_TLS}" "certificate chain was returned by ${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}"
    return
  fi

  tls_ok=false
  fail_check "${CHECK_TLS}" "no certificate was returned by ${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}"
}

certificate_subject() {
  openssl x509 -in "${cert_file}" -noout -subject 2>/dev/null | sed 's/^subject=//'
}

certificate_issuer() {
  openssl x509 -in "${cert_file}" -noout -issuer 2>/dev/null | sed 's/^issuer=//'
}

certificate_enddate() {
  openssl x509 -in "${cert_file}" -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
}

check_certificate_hostname() {
  local cert_subject
  local cert_issuer

  if [[ "${tls_ok}" != "true" ]]; then
    skip_check "${CHECK_CERT_HOSTNAME}" "TLS handshake failed"
    return
  fi

  cert_subject="$(certificate_subject)"
  cert_issuer="$(certificate_issuer)"

  if openssl x509 -in "${cert_file}" -noout -checkhost "${FTPS_SMOKE_FQDN}" >/dev/null 2>&1; then
    pass_check "${CHECK_CERT_HOSTNAME}" "subject=${cert_subject:-unknown}, issuer=${cert_issuer:-unknown}"
    return
  fi

  fail_check "${CHECK_CERT_HOSTNAME}" "subject=${cert_subject:-unknown}, issuer=${cert_issuer:-unknown}, expectedHostname=${FTPS_SMOKE_FQDN}"
}

check_certificate_validity() {
  local cert_enddate

  if [[ "${tls_ok}" != "true" ]]; then
    skip_check "${CHECK_CERT_VALIDITY}" "TLS handshake failed"
    return
  fi

  cert_enddate="$(certificate_enddate)"

  if openssl x509 -in "${cert_file}" -noout -checkend "${FTPS_SMOKE_CERT_VALIDITY_WINDOW_SECONDS}" >/dev/null 2>&1; then
    pass_check "${CHECK_CERT_VALIDITY}" "notAfter=${cert_enddate:-unknown}"
    return
  fi

  fail_check "${CHECK_CERT_VALIDITY}" "certificate is expired or expires within ${FTPS_SMOKE_CERT_VALIDITY_WINDOW_SECONDS} seconds; notAfter=${cert_enddate:-unknown}"
}

fetch_ftps_credentials() {
  ftps_username="$(az keyvault secret show --vault-name "${FTPS_SMOKE_KEY_VAULT_NAME}" --name "${FTPS_SMOKE_USERNAME_SECRET_NAME}" --query value -o tsv 2>/dev/null || true)"
  ftps_password="$(az keyvault secret show --vault-name "${FTPS_SMOKE_KEY_VAULT_NAME}" --name "${FTPS_SMOKE_PASSWORD_SECRET_NAME}" --query value -o tsv 2>/dev/null || true)"

  if [[ -n "${ftps_username}" && -n "${ftps_password}" ]]; then
    credentials_ok=true
    return
  fi

  credentials_ok=false
  fail_check "${CHECK_LOGIN}" "required FTPS secrets were not available from ${FTPS_SMOKE_KEY_VAULT_NAME}"
}

authenticate_ftps() {
  curl \
    --silent \
    --show-error \
    --ssl-reqd \
    --insecure \
    --ftp-pasv \
    --user "${ftps_username}:${ftps_password}" \
    --quote "PWD" \
    --output /dev/null \
    "ftps://${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}/" \
    >/dev/null 2>&1
}

check_ftps_login() {
  fetch_ftps_credentials

  if [[ "${tls_ok}" != "true" ]]; then
    skip_check "${CHECK_LOGIN}" "TLS handshake failed"
    login_ok=false
    return
  fi

  if [[ "${credentials_ok}" != "true" ]]; then
    login_ok=false
    return
  fi

  if authenticate_ftps; then
    login_ok=true
    pass_check "${CHECK_LOGIN}" "authenticated successfully to ${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT} using secrets from ${FTPS_SMOKE_KEY_VAULT_NAME}"
    return
  fi

  login_ok=false
  fail_check "${CHECK_LOGIN}" "FTPS authentication failed for ${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}"
}

list_remote_directory() {
  curl \
    --silent \
    --show-error \
    --ssl-reqd \
    --insecure \
    --ftp-pasv \
    --user "${ftps_username}:${ftps_password}" \
    --list-only \
    "ftps://${FTPS_SMOKE_FQDN}:${FTPS_SMOKE_PORT}/${FTPS_SMOKE_LIST_PATH}" 2>/dev/null
}

check_remote_listing() {
  local list_output
  local condensed_output

  if [[ "${login_ok}" != "true" ]]; then
    skip_check "${CHECK_LIST}" "FTPS login failed"
    return
  fi

  if ! list_output="$(list_remote_directory)"; then
    fail_check "${CHECK_LIST}" "directory listing failed for path=${FTPS_SMOKE_LIST_PATH}"
    return
  fi

  condensed_output="$(printf '%s' "${list_output}" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
  pass_check "${CHECK_LIST}" "path=${FTPS_SMOKE_LIST_PATH}, entries=${condensed_output:-<empty>}"
}

print_summary() {
  printf 'SUMMARY: passes=%s failures=%s skipped=%s\n' "${pass_count}" "${fail_count}" "${skip_count}"
}

main() {
  validate_prerequisites
  prepare_runtime

  report_container_app_state
  check_dns
  check_tcp_reachability
  check_tls_handshake
  check_certificate_hostname
  check_certificate_validity
  check_ftps_login
  check_remote_listing

  print_summary
  exit "${overall_status}"
}

main "$@"