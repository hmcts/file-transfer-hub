#!/usr/bin/env bash
set -euo pipefail

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

if [[ -z "${FTPS_LOCAL_PASSWORD}" ]]; then
    ftps_warn "FTPS_LOCAL_PASSWORD must be set"
    exit 1
fi

ftps_log "Starting FTPS container setup"

if [[ -n "${FTPS_ADDITIONAL_USER}" && -z "${FTPS_ADDITIONAL_PASSWORD}" ]]; then
    echo "FTPS_ADDITIONAL_PASSWORD must be set when FTPS_ADDITIONAL_USER is provided" >&2
    exit 1
fi

if [[ -z "${FTPS_ADDITIONAL_USER}" && -n "${FTPS_ADDITIONAL_PASSWORD}" ]]; then
    echo "FTPS_ADDITIONAL_USER must be set when FTPS_ADDITIONAL_PASSWORD is provided" >&2
    exit 1
fi

if [[ "${FTPS_ADDITIONAL_USER}" == "${FTPS_LOCAL_USER}" ]]; then
    echo "FTPS_ADDITIONAL_USER must be different from FTPS_LOCAL_USER" >&2
    exit 1
fi

FTPS_SHARED_GROUP="${FTPS_LOCAL_USER}"
FTPS_AUTH_GROUP_NAME="${FTPS_LOCAL_USER}"

if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
    FTPS_SHARED_GROUP="ftpsusers"
    FTPS_AUTH_GROUP_NAME="${FTPS_SHARED_GROUP}"
fi

groupadd -f "${FTPS_SHARED_GROUP}"
if ! id -u "${FTPS_LOCAL_USER}" >/dev/null 2>&1; then
    useradd -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" -M -s /bin/bash "${FTPS_LOCAL_USER}"
else
    usermod -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" "${FTPS_LOCAL_USER}"
fi

FTPS_LOCAL_PASSWORD_HASH="$(openssl passwd -6 "${FTPS_LOCAL_PASSWORD}")"
usermod -p "${FTPS_LOCAL_PASSWORD_HASH}" "${FTPS_LOCAL_USER}"

if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
    if ! id -u "${FTPS_ADDITIONAL_USER}" >/dev/null 2>&1; then
        useradd -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" -M -s /bin/bash "${FTPS_ADDITIONAL_USER}"
    else
        usermod -g "${FTPS_SHARED_GROUP}" -d "${FTPS_LOCAL_ROOT}" "${FTPS_ADDITIONAL_USER}"
    fi

    FTPS_ADDITIONAL_PASSWORD_HASH="$(openssl passwd -6 "${FTPS_ADDITIONAL_PASSWORD}")"
    usermod -p "${FTPS_ADDITIONAL_PASSWORD_HASH}" "${FTPS_ADDITIONAL_USER}"
fi

mkdir -p /srv/ftps "${FTPS_LOCAL_ROOT}" "${FTPS_LOCAL_UPLOAD_DIR}" "${FTPS_LOCAL_DOWNLOAD_DIR}" /var/log/proftpd
chown root:root /srv/ftps "${FTPS_LOCAL_ROOT}"
chmod 0755 /srv/ftps "${FTPS_LOCAL_ROOT}"
if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
    chmod 0770 "${FTPS_LOCAL_UPLOAD_DIR}"
else
    chmod 0750 "${FTPS_LOCAL_UPLOAD_DIR}"
fi
chown "${FTPS_LOCAL_USER}:${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_UPLOAD_DIR}"
chown root:"${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_DOWNLOAD_DIR}"
chmod 0550 "${FTPS_LOCAL_DOWNLOAD_DIR}"

cat > "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt" <<EOF
HMCTS FTPS service

Upload files into the upload directory.
Download-only content can be placed in the download directory by an administrator.
EOF
chown root:"${FTPS_SHARED_GROUP}" "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt"
chmod 0440 "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt"

printf '%s\n' "${FTPS_WELCOME_MESSAGE}" > "${FTPS_BANNER_PATH}"
chown root:root "${FTPS_BANNER_PATH}"
chmod 0644 "${FTPS_BANNER_PATH}"

FTPS_CERTIFICATE_GROUP="root"
if id -u proftpd >/dev/null 2>&1; then
    FTPS_CERTIFICATE_GROUP="$(id -gn proftpd)"
fi

FTPS_AUTH_DIR="$(dirname "${FTPS_AUTH_USER_FILE}")"
mkdir -p "${FTPS_AUTH_DIR}"
if [[ "$(dirname "${FTPS_AUTH_GROUP_FILE}")" != "${FTPS_AUTH_DIR}" ]]; then
    mkdir -p "$(dirname "${FTPS_AUTH_GROUP_FILE}")"
fi

FTPS_RUNTIME_GROUP="${FTPS_CERTIFICATE_GROUP}"
FTPS_AUTH_GROUP_ID="$(id -g "${FTPS_LOCAL_USER}")"
export FTPS_TLS_CHAIN_DIRECTIVE=""

cat > "${FTPS_AUTH_USER_FILE}" <<EOF
${FTPS_LOCAL_USER}:${FTPS_LOCAL_PASSWORD_HASH}:$(id -u "${FTPS_LOCAL_USER}"):${FTPS_AUTH_GROUP_ID}::${FTPS_LOCAL_ROOT}:/bin/bash
EOF

if [[ -n "${FTPS_ADDITIONAL_USER}" ]]; then
    cat >> "${FTPS_AUTH_USER_FILE}" <<EOF
${FTPS_ADDITIONAL_USER}:${FTPS_ADDITIONAL_PASSWORD_HASH}:$(id -u "${FTPS_ADDITIONAL_USER}"):${FTPS_AUTH_GROUP_ID}::${FTPS_LOCAL_ROOT}:/bin/bash
EOF
fi

cat > "${FTPS_AUTH_GROUP_FILE}" <<EOF
${FTPS_AUTH_GROUP_NAME}:x:${FTPS_AUTH_GROUP_ID}:${FTPS_LOCAL_USER}${FTPS_ADDITIONAL_USER:+,${FTPS_ADDITIONAL_USER}}
EOF

chown root:"${FTPS_RUNTIME_GROUP}" "${FTPS_AUTH_DIR}" "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"
chmod 0750 "${FTPS_AUTH_DIR}"
chmod 0640 "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"

FTPS_CERTIFICATE_DIR="$(dirname "${FTPS_CERTIFICATE_PATH}")"
FTPS_CERTIFICATE_MANAGED="false"

ftps_extract_private_key_block() {
    local source_file="$1"
    local destination_file="$2"

    awk '
        /-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----/ { capture=1 }
        capture { print }
        /-----END ([A-Z0-9]+ )?PRIVATE KEY-----/ {
            capture=0
            found=1
            exit
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "${source_file}" > "${destination_file}"
}

ftps_extract_certificate_blocks() {
    local source_file="$1"
    local destination_prefix="$2"

    awk -v prefix="${destination_prefix}" '
        /-----BEGIN CERTIFICATE-----/ {
            capture=1
            count++
            current_file=sprintf("%s.%d", prefix, count)
        }
        capture {
            print >> current_file
        }
        /-----END CERTIFICATE-----/ {
            capture=0
            close(current_file)
        }
        END {
            print count + 0
        }
    ' "${source_file}"
}

ftps_certificate_matches_private_key() {
    local certificate_file="$1"
    local private_key_file="$2"
    local certificate_public_key_file private_key_public_key_file result

    certificate_public_key_file="$(mktemp)"
    private_key_public_key_file="$(mktemp)"

    result=1
    if openssl x509 -in "${certificate_file}" -pubkey -noout > "${certificate_public_key_file}" 2>/dev/null &&
       openssl pkey -in "${private_key_file}" -pubout > "${private_key_public_key_file}" 2>/dev/null &&
       cmp -s "${certificate_public_key_file}" "${private_key_public_key_file}"; then
        result=0
    fi

    rm -f "${certificate_public_key_file}" "${private_key_public_key_file}"
    return "${result}"
}

ftps_normalize_pem_bundle() {
    local source_file="$1"
    local destination_file="$2"
    local private_key_file certificate_prefix certificate_count matching_certificate_index certificate_index

    private_key_file="$(mktemp)"
    certificate_prefix="$(mktemp)"

    if ! ftps_extract_private_key_block "${source_file}" "${private_key_file}"; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain a private key PEM block"
        exit 1
    fi

    certificate_count="$(ftps_extract_certificate_blocks "${source_file}" "${certificate_prefix}")"
    if [[ "${certificate_count}" -eq 0 ]]; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain any certificate PEM blocks"
        exit 1
    fi

    matching_certificate_index=""
    for certificate_index in $(seq 1 "${certificate_count}"); do
        if ftps_certificate_matches_private_key "${certificate_prefix}.${certificate_index}" "${private_key_file}"; then
            matching_certificate_index="${certificate_index}"
            break
        fi
    done

    if [[ -z "${matching_certificate_index}" ]]; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain a certificate matching the supplied private key"
        exit 1
    fi

    cat "${private_key_file}" > "${destination_file}"
    cat "${certificate_prefix}.${matching_certificate_index}" >> "${destination_file}"

    for certificate_index in $(seq 1 "${certificate_count}"); do
        if [[ "${certificate_index}" == "${matching_certificate_index}" ]]; then
            continue
        fi

        cat "${certificate_prefix}.${certificate_index}" >> "${destination_file}"
    done

    rm -f "${private_key_file}" "${certificate_prefix}".*
}

ftps_prepare_proftpd_tls_material() {
    local source_file="$1"
    local certificate_file="$2"
    local chain_file="$3"
    local private_key_file certificate_prefix certificate_count matching_certificate_index certificate_index

    private_key_file="$(mktemp)"
    certificate_prefix="$(mktemp)"

    if ! ftps_extract_private_key_block "${source_file}" "${private_key_file}"; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain a private key PEM block"
        exit 1
    fi

    certificate_count="$(ftps_extract_certificate_blocks "${source_file}" "${certificate_prefix}")"
    if [[ "${certificate_count}" -eq 0 ]]; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain any certificate PEM blocks"
        exit 1
    fi

    matching_certificate_index=""
    for certificate_index in $(seq 1 "${certificate_count}"); do
        if ftps_certificate_matches_private_key "${certificate_prefix}.${certificate_index}" "${private_key_file}"; then
            matching_certificate_index="${certificate_index}"
            break
        fi
    done

    if [[ -z "${matching_certificate_index}" ]]; then
        rm -f "${private_key_file}" "${certificate_prefix}".*
        ftps_warn "FTPS certificate content did not contain a certificate matching the supplied private key"
        exit 1
    fi

    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "$(dirname "${certificate_file}")"
    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "$(dirname "${chain_file}")"

    cat "${private_key_file}" > "${certificate_file}"
    cat "${certificate_prefix}.${matching_certificate_index}" >> "${certificate_file}"

    if [[ "${certificate_count}" -gt 1 ]]; then
        : > "${chain_file}"

        for certificate_index in $(seq 1 "${certificate_count}"); do
            if [[ "${certificate_index}" == "${matching_certificate_index}" ]]; then
                continue
            fi

            cat "${certificate_prefix}.${certificate_index}" >> "${chain_file}"
        done

        FTPS_TLS_CHAIN_DIRECTIVE="  TLSCertificateChainFile       ${chain_file}"
    else
        rm -f "${chain_file}"
        FTPS_TLS_CHAIN_DIRECTIVE=""
    fi

    chown root:"${FTPS_CERTIFICATE_GROUP}" "${certificate_file}"
    chmod 0640 "${certificate_file}"

    if [[ -n "${FTPS_TLS_CHAIN_DIRECTIVE}" ]]; then
        chown root:"${FTPS_CERTIFICATE_GROUP}" "${chain_file}"
        chmod 0640 "${chain_file}"
    fi

    rm -f "${private_key_file}" "${certificate_prefix}".*
}

ftps_write_pkcs12_bundle() {
    local encoded_bundle="$1"
    local bundle_file raw_pem_file

    ftps_log "Certificate content does not look like PEM; attempting PKCS12 conversion"

    bundle_file="$(mktemp)"
    raw_pem_file="$(mktemp)"

    if ! printf '%s' "${encoded_bundle}" | base64 -d > "${bundle_file}" 2>/dev/null; then
        rm -f "${bundle_file}" "${raw_pem_file}"
        ftps_warn "FTPS certificate value is not PEM and could not be base64-decoded as PKCS12"
        exit 1
    fi

    if ! openssl pkcs12 -in "${bundle_file}" -noenc -passin "pass:${FTPS_CERTIFICATE_PKCS12_PASSWORD}" -out "${raw_pem_file}" 2>/dev/null && \
       ! openssl pkcs12 -in "${bundle_file}" -nodes -passin "pass:${FTPS_CERTIFICATE_PKCS12_PASSWORD}" -out "${raw_pem_file}" 2>/dev/null; then
        rm -f "${bundle_file}" "${raw_pem_file}"
        ftps_warn "FTPS certificate PKCS12 bundle could not be converted to PEM"
        exit 1
    fi

    ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
    rm -f "${bundle_file}" "${raw_pem_file}"

    ftps_log "PKCS12 conversion completed and PEM bundle normalized"
}

if [[ ! -d "${FTPS_CERTIFICATE_DIR}" ]]; then
    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "${FTPS_CERTIFICATE_DIR}"
fi

if [[ -n "${FTPS_CERTIFICATE_PEM}" && -n "${FTPS_CERTIFICATE_KEY_PEM}" && "${FTPS_CERTIFICATE_PEM}" != "${FTPS_CERTIFICATE_KEY_PEM}" ]]; then
    raw_pem_file="$(mktemp)"
    trap 'rm -f "${raw_pem_file}"' RETURN

    ftps_log "Using separate PEM certificate and private key environment variables"
    cat > "${raw_pem_file}" <<EOF
${FTPS_CERTIFICATE_KEY_PEM}
${FTPS_CERTIFICATE_PEM}
EOF
    ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
    FTPS_CERTIFICATE_MANAGED="true"
elif [[ -n "${FTPS_CERTIFICATE_PEM}" ]]; then
    raw_pem_file="$(mktemp)"
    trap 'rm -f "${raw_pem_file}"' RETURN

    if [[ "${FTPS_CERTIFICATE_PEM}" == *"-----BEGIN "* ]]; then
        ftps_log "Using PEM certificate content from environment variable"
        printf '%s\n' "${FTPS_CERTIFICATE_PEM}" > "${raw_pem_file}"
        ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
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

sed -i 's/^#\?LoadModule mod_tls.c/LoadModule mod_tls.c/' /etc/proftpd/modules.conf
envsubst < /etc/proftpd/proftpd-ftps.conf.template > /etc/proftpd/conf.d/hmcts-ftps.conf

ftps_log "ProFTPD configuration rendered"

if [[ "${FTPS_ENABLE_STORAGE_FORWARD}" == "true" ]]; then
    ftps_log "Starting background storage forwarding loop"
    (
        while true; do
            if ! /usr/local/bin/ftps-storage-forward.sh; then
                ftps_warn "Storage forwarding iteration failed; will retry in ${FTPS_FORWARD_INTERVAL_SECONDS} seconds"
            fi
            sleep "${FTPS_FORWARD_INTERVAL_SECONDS}"
        done
    ) &
else
    ftps_log "Storage forwarding loop disabled"
fi

ftps_log "Launching ProFTPD"
socat TCP4-LISTEN:8086,fork,reuseaddr /dev/null &

/usr/sbin/proftpd -n -c /etc/proftpd/proftpd.conf &
PROFTPD_PID=$!

trap 'ftps_log "Received SIGTERM - container is shutting down gracefully. Check Azure Container Apps system logs for details."; kill -TERM "${PROFTPD_PID}" 2>/dev/null' TERM

wait "${PROFTPD_PID}"