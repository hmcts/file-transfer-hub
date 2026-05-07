#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${FTPS_LIB_DIR:-${SCRIPT_DIR}/lib}"

# The image copies helper libraries to /usr/local/lib, while local tests source the
# checkout copy. Resolve both locations explicitly so startup fails with a useful
# message instead of a generic Bash source error.
if [[ ! -d "${LIB_DIR}" && -d "/usr/local/lib/file-transfer-hub" ]]; then
    LIB_DIR="/usr/local/lib/file-transfer-hub"
fi

export FTPS_LOCAL_USER="${FTPS_LOCAL_USER:-ftpssvc}"
export FTPS_LOCAL_PASSWORD="${FTPS_LOCAL_PASSWORD:-}"
export FTPS_ADDITIONAL_USER="${FTPS_ADDITIONAL_USER:-}"
export FTPS_ADDITIONAL_PASSWORD="${FTPS_ADDITIONAL_PASSWORD:-}"
export FTPS_LOCAL_ROOT="${FTPS_LOCAL_ROOT:-/srv/ftps/${FTPS_LOCAL_USER}}"
export FTPS_LOCAL_UPLOAD_DIR="${FTPS_LOCAL_UPLOAD_DIR:-${FTPS_LOCAL_ROOT}/upload}"
export FTPS_LOCAL_DOWNLOAD_DIR="${FTPS_LOCAL_DOWNLOAD_DIR:-${FTPS_LOCAL_ROOT}/download}"
export FTPS_BANNER_PATH="${FTPS_BANNER_PATH:-${FTPS_LOCAL_ROOT}/.banner}"
export FTPS_WELCOME_MESSAGE="${FTPS_WELCOME_MESSAGE:-HMCTS FTPS service ready.}"
export FTPS_AUTH_USER_FILE="${FTPS_AUTH_USER_FILE:-/etc/proftpd/auth/ftpd.passwd}"
export FTPS_AUTH_GROUP_FILE="${FTPS_AUTH_GROUP_FILE:-/etc/proftpd/auth/ftpd.group}"
export FTPS_CERTIFICATE_PATH="${FTPS_CERTIFICATE_PATH:-/etc/proftpd/tls/ftps.pem}"
export FTPS_PROFTPD_CERTIFICATE_PATH="${FTPS_PROFTPD_CERTIFICATE_PATH:-/etc/proftpd/tls/runtime/server.pem}"
export FTPS_PROFTPD_CHAIN_PATH="${FTPS_PROFTPD_CHAIN_PATH:-/etc/proftpd/tls/runtime/chain.pem}"
export FTPS_CERTIFICATE_PEM="${FTPS_CERTIFICATE_PEM:-}"
export FTPS_CERTIFICATE_KEY_PEM="${FTPS_CERTIFICATE_KEY_PEM:-}"
export FTPS_CERTIFICATE_PKCS12_PASSWORD="${FTPS_CERTIFICATE_PKCS12_PASSWORD:-}"
export FTPS_PUBLIC_IP="${FTPS_PUBLIC_IP:-localhost}"
export FTPS_LISTEN_PORT="${FTPS_LISTEN_PORT:-990}"
export FTPS_PASSIVE_MIN_PORT="${FTPS_PASSIVE_MIN_PORT:-1024}"
export FTPS_PASSIVE_MAX_PORT="${FTPS_PASSIVE_MAX_PORT:-1034}"
export FTPS_ENABLE_STORAGE_FORWARD="${FTPS_ENABLE_STORAGE_FORWARD:-true}"
export FTPS_FORWARD_INTERVAL_SECONDS="${FTPS_FORWARD_INTERVAL_SECONDS:-60}"
export FTPS_FORWARD_LOCAL_DIR="${FTPS_FORWARD_LOCAL_DIR:-${FTPS_LOCAL_UPLOAD_DIR}}"
export FTPS_FORWARD_DELETE_AFTER="${FTPS_FORWARD_DELETE_AFTER:-false}"

ftps_log() {
    printf '[ftps-entrypoint] %s\n' "$*"
}

ftps_warn() {
    printf '[ftps-entrypoint] %s\n' "$*" >&2
}

if [[ ! -r "${LIB_DIR}/ftps-entrypoint-certificates.sh" ]]; then
    ftps_warn "Certificate helper library not found at ${LIB_DIR}/ftps-entrypoint-certificates.sh"
    exit 1
fi

# shellcheck source=lib/ftps-entrypoint-certificates.sh
source "${LIB_DIR}/ftps-entrypoint-certificates.sh"

ftps_is_valid_linux_account_name() {
    local value="$1"

    [[ "${value}" =~ ^[a-z_][a-z0-9_-]{0,30}\$?$ ]]
}

ftps_is_positive_integer() {
    local value="$1"

    [[ "${value}" =~ ^[1-9][0-9]*$ ]]
}

ftps_is_port_number() {
    local value="$1"

    [[ "${value}" =~ ^[0-9]{1,5}$ ]] && ((10#${value} >= 1 && 10#${value} <= 65535))
}

ftps_validate_linux_account_name() {
    local variable_name="$1"
    local value="$2"

    if ! ftps_is_valid_linux_account_name "${value}"; then
        ftps_warn "${variable_name} must be a valid Linux account name: start with a lowercase letter or underscore, then use lowercase letters, digits, underscores, or hyphens"
        exit 1
    fi
}

ftps_validate_port() {
    local variable_name="$1"
    local value="$2"

    if ! ftps_is_port_number "${value}"; then
        ftps_warn "${variable_name} must be an integer port between 1 and 65535"
        exit 1
    fi
}

# Validates startup configuration before mutating container state.
#
# Globals:
#   FTPS_LOCAL_PASSWORD: Required.
#   FTPS_LOCAL_USER: Read and validated as a Linux account name.
#   FTPS_ADDITIONAL_USER: Read as the optional second account name.
#   FTPS_ADDITIONAL_PASSWORD: Read as the optional second account password.
#   FTPS_LISTEN_PORT: Read and validated as a TCP port.
#   FTPS_PASSIVE_MIN_PORT: Read and validated as a TCP port.
#   FTPS_PASSIVE_MAX_PORT: Read and validated as a TCP port.
#   FTPS_FORWARD_INTERVAL_SECONDS: Read and validated as a positive integer.
# Outputs:
#   Writes validation failures to stderr via ftps_warn.
# Returns:
#   Exits with 1 on invalid configuration; returns 0 otherwise.
ftps_validate_runtime_config() {
    if [[ -z "${FTPS_LOCAL_PASSWORD}" ]]; then
        ftps_warn "FTPS_LOCAL_PASSWORD must be set"
        exit 1
    fi

    # These values cross the container boundary into useradd, passwd files and
    # ProFTPD config. Validate them once at startup instead of relying on later
    # command failures or duplicating checks at every internal call site.
    ftps_validate_linux_account_name "FTPS_LOCAL_USER" "${FTPS_LOCAL_USER}"

    if [[ -n "${FTPS_ADDITIONAL_USER}" && -z "${FTPS_ADDITIONAL_PASSWORD}" ]]; then
        ftps_warn "FTPS_ADDITIONAL_PASSWORD must be set when FTPS_ADDITIONAL_USER is provided"
        exit 1
    fi

    if [[ -z "${FTPS_ADDITIONAL_USER}" && -n "${FTPS_ADDITIONAL_PASSWORD}" ]]; then
        ftps_warn "FTPS_ADDITIONAL_USER must be set when FTPS_ADDITIONAL_PASSWORD is provided"
        exit 1
    fi

    if [[ "${FTPS_ADDITIONAL_USER}" == "${FTPS_LOCAL_USER}" ]]; then
        ftps_warn "FTPS_ADDITIONAL_USER must be different from FTPS_LOCAL_USER"
        exit 1
    fi

    if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
        ftps_validate_linux_account_name "FTPS_ADDITIONAL_USER" "${FTPS_ADDITIONAL_USER}"
    fi

    ftps_validate_port "FTPS_LISTEN_PORT" "${FTPS_LISTEN_PORT}"
    ftps_validate_port "FTPS_PASSIVE_MIN_PORT" "${FTPS_PASSIVE_MIN_PORT}"
    ftps_validate_port "FTPS_PASSIVE_MAX_PORT" "${FTPS_PASSIVE_MAX_PORT}"

    if ((10#${FTPS_PASSIVE_MIN_PORT} > 10#${FTPS_PASSIVE_MAX_PORT})); then
        ftps_warn "FTPS_PASSIVE_MIN_PORT must be less than or equal to FTPS_PASSIVE_MAX_PORT"
        exit 1
    fi

    if ! ftps_is_positive_integer "${FTPS_FORWARD_INTERVAL_SECONDS}"; then
        ftps_warn "FTPS_FORWARD_INTERVAL_SECONDS must be a positive integer"
        exit 1
    fi
}

# Chooses the Unix and ProFTPD group model for the configured accounts.
#
# Globals:
#   FTPS_LOCAL_USER: Read as the default group name.
#   FTPS_ADDITIONAL_USER: Read to decide whether a shared group is needed.
#   FTPS_SHARED_GROUP: Set for Linux account and directory ownership.
#   FTPS_AUTH_GROUP_NAME: Set for the ProFTPD group auth file.
ftps_resolve_shared_group() {
    FTPS_SHARED_GROUP="${FTPS_LOCAL_USER}"
    FTPS_AUTH_GROUP_NAME="${FTPS_LOCAL_USER}"

    if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
        FTPS_SHARED_GROUP="ftpsusers"
        FTPS_AUTH_GROUP_NAME="${FTPS_SHARED_GROUP}"
    fi
}

# Ensures one local FTPS account exists with the expected group and home.
#
# Globals:
#   FTPS_SHARED_GROUP: Read as the account primary group.
#   FTPS_LOCAL_ROOT: Read as the account home directory.
# Arguments:
#   $1: Linux username to create or update.
# Returns:
#   0 when the account exists or is updated; non-zero if useradd/usermod fails.
ftps_ensure_user_account() {
    local username="$1"

    if ! id -u "${username}" >/dev/null 2>&1; then
        useradd -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" -M -s /bin/bash "${username}"
        return 0
    fi

    usermod -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" "${username}"
}

# Hashes and applies an account password.
#
# Arguments:
#   $1: Linux username whose password is updated.
#   $2: Clear-text password to hash; callers must not log it.
# Outputs:
#   Writes the generated password hash to stdout.
# Returns:
#   0 when hashing and usermod succeed; non-zero otherwise.
ftps_set_user_password() {
    local username="$1"
    local password="$2"
    local password_hash

    password_hash="$(openssl passwd -6 "${password}")"
    usermod -p "${password_hash}" "${username}"
    printf '%s' "${password_hash}"
}

# Creates the shared group and configured FTPS accounts.
#
# Globals:
#   FTPS_SHARED_GROUP: Read as the group to create and assign.
#   FTPS_LOCAL_USER: Read as the primary account name.
#   FTPS_LOCAL_PASSWORD: Read as the primary account password.
#   FTPS_ADDITIONAL_USER: Read as the optional second account name.
#   FTPS_ADDITIONAL_PASSWORD: Read as the optional second account password.
#   FTPS_LOCAL_PASSWORD_HASH: Set for auth-file rendering.
#   FTPS_ADDITIONAL_PASSWORD_HASH: Set for auth-file rendering.
# Returns:
#   0 when all required accounts are configured; non-zero if account tools fail.
ftps_configure_local_users() {
    groupadd -f "${FTPS_SHARED_GROUP}"

    ftps_ensure_user_account "${FTPS_LOCAL_USER}"
    FTPS_LOCAL_PASSWORD_HASH="$(ftps_set_user_password "${FTPS_LOCAL_USER}" "${FTPS_LOCAL_PASSWORD}")"

    if [[ -z "${FTPS_ADDITIONAL_USER}" ]]; then
        FTPS_ADDITIONAL_PASSWORD_HASH=""
        return 0
    fi

    ftps_ensure_user_account "${FTPS_ADDITIONAL_USER}"
    FTPS_ADDITIONAL_PASSWORD_HASH="$(ftps_set_user_password "${FTPS_ADDITIONAL_USER}" "${FTPS_ADDITIONAL_PASSWORD}")"
}

# Creates the FTPS directory tree and permission boundaries.
#
# Globals:
#   FTPS_LOCAL_ROOT: Read as the service root path.
#   FTPS_LOCAL_UPLOAD_DIR: Read as the client-writable upload path.
#   FTPS_LOCAL_DOWNLOAD_DIR: Read as the read-only client download path.
#   FTPS_LOCAL_USER: Read as the upload directory owner.
#   FTPS_SHARED_GROUP: Read as the shared access group.
#   FTPS_ADDITIONAL_USER: Read to choose single-user or shared upload mode.
#   FTPS_WELCOME_MESSAGE: Read for the banner file.
#   FTPS_BANNER_PATH: Read as the banner file path.
# Outputs:
#   Creates directories and writes download README and banner files.
# Returns:
#   0 when filesystem setup succeeds; non-zero on mkdir/chown/chmod/write failure.
ftps_prepare_local_directories() {
    mkdir -p /srv/ftps "${FTPS_LOCAL_ROOT}" "${FTPS_LOCAL_UPLOAD_DIR}" "${FTPS_LOCAL_DOWNLOAD_DIR}" /var/log/proftpd
    chown root:root /srv/ftps "${FTPS_LOCAL_ROOT}"
    chmod 0755 /srv/ftps "${FTPS_LOCAL_ROOT}"

    # Uploads are the only client-writable area. When a second FTPS account is
    # configured, both accounts share one group so fan-in uploads land in the
    # same directory without making the service root broadly writable.
    if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
        chmod 0770 "${FTPS_LOCAL_UPLOAD_DIR}"
    else
        chmod 0750 "${FTPS_LOCAL_UPLOAD_DIR}"
    fi

    chown "${FTPS_LOCAL_USER}:${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_UPLOAD_DIR}"
    chown root:"${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_DOWNLOAD_DIR}"
    chmod 0550 "${FTPS_LOCAL_DOWNLOAD_DIR}"

    cat >"${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt" <<EOF
HMCTS FTPS service

Upload files into the upload directory.
Download-only content can be placed in the download directory by an administrator.
EOF
    chown root:"${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt"
    chmod 0440 "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt"

    printf '%s\n' "${FTPS_WELCOME_MESSAGE}" >"${FTPS_BANNER_PATH}"
    chown root:root "${FTPS_BANNER_PATH}"
    chmod 0644 "${FTPS_BANNER_PATH}"
}

# Resolves the group that must be able to read TLS material.
#
# Globals:
#   FTPS_CERTIFICATE_GROUP: Set to the ProFTPD group, or root when absent.
ftps_detect_certificate_group() {
    FTPS_CERTIFICATE_GROUP="root"
    if id -u proftpd >/dev/null 2>&1; then
        FTPS_CERTIFICATE_GROUP="$(id -gn proftpd)"
    fi
}

# Creates parent directories for the ProFTPD user and group auth files.
#
# Globals:
#   FTPS_AUTH_USER_FILE: Read as the user auth file path.
#   FTPS_AUTH_GROUP_FILE: Read as the group auth file path.
#   FTPS_AUTH_DIR: Set to the user auth file directory.
# Outputs:
#   Creates auth-file parent directories when needed.
# Returns:
#   0 when directories exist; non-zero if mkdir fails.
ftps_prepare_auth_directory() {
    FTPS_AUTH_DIR="$(dirname "${FTPS_AUTH_USER_FILE}")"
    mkdir -p "${FTPS_AUTH_DIR}"

    if [[ "$(dirname "${FTPS_AUTH_GROUP_FILE}")" != "${FTPS_AUTH_DIR}" ]]; then
        mkdir -p "$(dirname "${FTPS_AUTH_GROUP_FILE}")"
    fi
}

# Renders ProFTPD auth files from prepared account state.
#
# Globals:
#   FTPS_CERTIFICATE_GROUP: Read as the runtime-readable group.
#   FTPS_LOCAL_USER: Read as the primary account name.
#   FTPS_LOCAL_ROOT: Read as the account home in auth entries.
#   FTPS_LOCAL_PASSWORD_HASH: Read as the primary account password hash.
#   FTPS_ADDITIONAL_USER: Read as the optional second account name.
#   FTPS_ADDITIONAL_PASSWORD_HASH: Read as the optional second password hash.
#   FTPS_AUTH_GROUP_NAME: Read as the ProFTPD auth group name.
#   FTPS_AUTH_DIR: Read for ownership and permissions.
#   FTPS_AUTH_USER_FILE: Read as the output user auth file path.
#   FTPS_AUTH_GROUP_FILE: Read as the output group auth file path.
#   FTPS_RUNTIME_GROUP: Set to the group that can read auth files.
#   FTPS_AUTH_GROUP_ID: Set to the local FTPS account group id.
#   FTPS_TLS_CHAIN_DIRECTIVE: Reset before TLS material preparation.
# Outputs:
#   Writes ProFTPD user and group auth files.
# Returns:
#   0 when files are written and permissions are set; non-zero otherwise.
ftps_write_auth_files() {
    FTPS_RUNTIME_GROUP="${FTPS_CERTIFICATE_GROUP}"
    FTPS_AUTH_GROUP_ID="$(id -g "${FTPS_LOCAL_USER}")"
    export FTPS_TLS_CHAIN_DIRECTIVE=""

    cat >"${FTPS_AUTH_USER_FILE}" <<EOF
${FTPS_LOCAL_USER}:${FTPS_LOCAL_PASSWORD_HASH}:$(id -u "${FTPS_LOCAL_USER}"):${FTPS_AUTH_GROUP_ID}::${FTPS_LOCAL_ROOT}:/bin/bash
EOF

    if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
        cat >>"${FTPS_AUTH_USER_FILE}" <<EOF
${FTPS_ADDITIONAL_USER}:${FTPS_ADDITIONAL_PASSWORD_HASH}:$(id -u "${FTPS_ADDITIONAL_USER}"):${FTPS_AUTH_GROUP_ID}::${FTPS_LOCAL_ROOT}:/bin/bash
EOF
    fi

    cat >"${FTPS_AUTH_GROUP_FILE}" <<EOF
${FTPS_AUTH_GROUP_NAME}:x:${FTPS_AUTH_GROUP_ID}:${FTPS_LOCAL_USER}${FTPS_ADDITIONAL_USER:+,${FTPS_ADDITIONAL_USER}}
EOF

    chown root:"${FTPS_RUNTIME_GROUP}" "${FTPS_AUTH_DIR}" "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"
    chmod 0750 "${FTPS_AUTH_DIR}"
    chmod 0640 "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"
}

# Combines separate PEM certificate and private-key environment values.
#
# Globals:
#   FTPS_CERTIFICATE_KEY_PEM: Read as the private-key PEM content.
#   FTPS_CERTIFICATE_PEM: Read as the certificate PEM content.
#   FTPS_CERTIFICATE_PATH: Read as the normalized PEM destination.
# Outputs:
#   Writes a temporary PEM bundle and the normalized certificate file.
# Returns:
#   0 when normalization succeeds; exits via the normalizer on invalid PEM.
ftps_write_combined_pem_from_env() {
    local raw_pem_file

    raw_pem_file="$(mktemp)"
    cat >"${raw_pem_file}" <<EOF
${FTPS_CERTIFICATE_KEY_PEM}
${FTPS_CERTIFICATE_PEM}
EOF
    ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
    rm -f "${raw_pem_file}"
}

# Normalizes single PEM certificate content from the environment.
#
# Globals:
#   FTPS_CERTIFICATE_PEM: Read as PEM bundle content.
#   FTPS_CERTIFICATE_PATH: Read as the normalized PEM destination.
# Outputs:
#   Writes a temporary PEM file and the normalized certificate file.
# Returns:
#   0 when normalization succeeds; exits via the normalizer on invalid PEM.
ftps_write_single_pem_content() {
    local raw_pem_file

    raw_pem_file="$(mktemp)"
    printf '%s\n' "${FTPS_CERTIFICATE_PEM}" >"${raw_pem_file}"
    ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
    rm -f "${raw_pem_file}"
}

# Prepares mounted, PEM or PKCS#12 certificate input for ProFTPD.
#
# Globals:
#   FTPS_CERTIFICATE_PATH: Read as source or normalized certificate path.
#   FTPS_CERTIFICATE_GROUP: Read for certificate directory/file ownership.
#   FTPS_CERTIFICATE_PEM: Read as optional PEM or base64 PKCS#12 input.
#   FTPS_CERTIFICATE_KEY_PEM: Read as optional separate private-key PEM input.
#   FTPS_PROFTPD_CERTIFICATE_PATH: Read as the runtime server PEM destination.
#   FTPS_PROFTPD_CHAIN_PATH: Read as the runtime chain PEM destination.
#   FTPS_CERTIFICATE_DIR: Set to the certificate source directory.
#   FTPS_CERTIFICATE_MANAGED: Set to track whether this script wrote the source certificate.
#   FTPS_TLS_CHAIN_DIRECTIVE: Read after runtime TLS material preparation.
# Outputs:
#   Writes normalized source certificate material and ProFTPD runtime TLS files.
# Returns:
#   Exits with 1 when no usable certificate material exists; returns 0 otherwise.
ftps_prepare_runtime_certificate() {
    FTPS_CERTIFICATE_DIR="$(dirname "${FTPS_CERTIFICATE_PATH}")"
    FTPS_CERTIFICATE_MANAGED="false"

    if [[ ! -d "${FTPS_CERTIFICATE_DIR}" ]]; then
        install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "${FTPS_CERTIFICATE_DIR}"
    fi

    if [[ -n "${FTPS_CERTIFICATE_PEM}" && -n "${FTPS_CERTIFICATE_KEY_PEM}" && "${FTPS_CERTIFICATE_PEM}" != "${FTPS_CERTIFICATE_KEY_PEM}" ]]; then
        ftps_log "Using separate PEM certificate and private key environment variables"
        ftps_write_combined_pem_from_env
        FTPS_CERTIFICATE_MANAGED="true"
    elif [[ -n "${FTPS_CERTIFICATE_PEM}" ]]; then
        if [[ "${FTPS_CERTIFICATE_PEM}" == *"-----BEGIN "* ]]; then
            ftps_log "Using PEM certificate content from environment variable"
            ftps_write_single_pem_content
        else
            ftps_write_pkcs12_bundle "${FTPS_CERTIFICATE_PEM}"
        fi
        FTPS_CERTIFICATE_MANAGED="true"
    else
        ftps_log "No certificate content provided in environment; expecting mounted certificate file at ${FTPS_CERTIFICATE_PATH}"
    fi

    if [[ ! -f "${FTPS_CERTIFICATE_PATH}" ]]; then
        ftps_warn "FTPS certificate not found at ${FTPS_CERTIFICATE_PATH} and FTPS certificate environment variables were not provided"
        exit 1
    fi

    ftps_log "Certificate file ready at ${FTPS_CERTIFICATE_PATH}"

    if [[ "${FTPS_CERTIFICATE_MANAGED}" == "true" ]]; then
        chown root:"${FTPS_CERTIFICATE_GROUP}" "${FTPS_CERTIFICATE_PATH}"
        chmod 0640 "${FTPS_CERTIFICATE_PATH}"
    fi

    ftps_prepare_proftpd_tls_material \
        "${FTPS_CERTIFICATE_PATH}" \
        "${FTPS_PROFTPD_CERTIFICATE_PATH}" \
        "${FTPS_PROFTPD_CHAIN_PATH}"

    ftps_log "Prepared ProFTPD TLS material at ${FTPS_PROFTPD_CERTIFICATE_PATH}"
    if [[ -n "${FTPS_TLS_CHAIN_DIRECTIVE}" ]]; then
        ftps_log "Prepared ProFTPD certificate chain at ${FTPS_PROFTPD_CHAIN_PATH}"
    fi
}

# Enables TLS support and renders the ProFTPD container config.
#
# Globals:
#   FTPS_*: Read by envsubst after startup validation.
# Outputs:
#   Updates ProFTPD module/config files and logs completion.
# Returns:
#   0 when sed and envsubst succeed; non-zero otherwise.
ftps_render_proftpd_config() {
    sed -i 's/^#\?LoadModule mod_tls.c/LoadModule mod_tls.c/' /etc/proftpd/modules.conf
    envsubst </etc/proftpd/proftpd-ftps.conf.template >/etc/proftpd/conf.d/hmcts-ftps.conf
    ftps_log "ProFTPD configuration rendered"
}

# Starts the optional forwarding worker as a background retry loop.
#
# Globals:
#   FTPS_ENABLE_STORAGE_FORWARD: Read to decide whether to start the loop.
#   FTPS_FORWARD_INTERVAL_SECONDS: Read as the retry sleep interval.
# Outputs:
#   Logs loop startup, disabled state and failed iterations.
# Returns:
#   0 immediately when disabled or after the background loop is started.
ftps_start_storage_forward_loop() {
    if [[ "${FTPS_ENABLE_STORAGE_FORWARD}" != "true" ]]; then
        ftps_log "Storage forwarding loop disabled"
        return 0
    fi

    ftps_log "Starting background storage forwarding loop"
    (
        while true; do
            if ! /usr/local/bin/ftps-storage-forward.sh; then
                ftps_warn "Storage forwarding iteration failed; will retry in ${FTPS_FORWARD_INTERVAL_SECONDS} seconds"
            fi
            sleep "${FTPS_FORWARD_INTERVAL_SECONDS}"
        done
    ) &
}

# Waits on the foreground ProFTPD child and forwards SIGTERM.
#
# Arguments:
#   $1: PID of the ProFTPD process to wait for and terminate on SIGTERM.
# Outputs:
#   Logs graceful shutdown messages when SIGTERM is received.
# Returns:
#   The waited ProFTPD process status.
ftps_wait_for_proftpd() {
    local proftpd_pid="$1"

    trap 'ftps_log "Received SIGTERM - container is shutting down gracefully. Check Azure Container Apps system logs for details."; kill -TERM "${proftpd_pid}" 2>/dev/null' TERM
    wait "${proftpd_pid}"
}

# Starts the health listener and ProFTPD foreground process.
#
# Outputs:
#   Starts a background health listener and logs ProFTPD startup.
# Returns:
#   The ProFTPD wait status from ftps_wait_for_proftpd.
ftps_start_proftpd() {
    local proftpd_pid

    ftps_log "Launching ProFTPD"
    socat TCP4-LISTEN:8086,fork,reuseaddr /dev/null &

    /usr/sbin/proftpd -n -c /etc/proftpd/proftpd.conf &
    proftpd_pid=$!

    ftps_wait_for_proftpd "${proftpd_pid}"
}

main() {
    ftps_log "Starting FTPS container setup"
    ftps_validate_runtime_config
    ftps_resolve_shared_group
    ftps_configure_local_users
    ftps_prepare_local_directories
    ftps_detect_certificate_group
    ftps_prepare_auth_directory
    ftps_write_auth_files
    ftps_prepare_runtime_certificate
    ftps_render_proftpd_config
    ftps_start_storage_forward_loop
    ftps_start_proftpd
}

main "$@"
