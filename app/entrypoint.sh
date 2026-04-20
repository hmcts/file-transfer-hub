#!/usr/bin/env bash
set -euo pipefail

export FTPS_LOCAL_USER="${FTPS_LOCAL_USER:-ftpssvc}"
export FTPS_LOCAL_PASSWORD="${FTPS_LOCAL_PASSWORD:-}"
export FTPS_LOCAL_ROOT="${FTPS_LOCAL_ROOT:-/srv/ftps/${FTPS_LOCAL_USER}}"
export FTPS_LOCAL_UPLOAD_DIR="${FTPS_LOCAL_UPLOAD_DIR:-${FTPS_LOCAL_ROOT}/upload}"
export FTPS_LOCAL_DOWNLOAD_DIR="${FTPS_LOCAL_DOWNLOAD_DIR:-${FTPS_LOCAL_ROOT}/download}"
export FTPS_BANNER_PATH="${FTPS_BANNER_PATH:-${FTPS_LOCAL_ROOT}/.banner}"
export FTPS_WELCOME_MESSAGE="${FTPS_WELCOME_MESSAGE:-HMCTS FTPS service ready.}"
export FTPS_AUTH_USER_FILE="${FTPS_AUTH_USER_FILE:-/etc/proftpd/auth/ftpd.passwd}"
export FTPS_AUTH_GROUP_FILE="${FTPS_AUTH_GROUP_FILE:-/etc/proftpd/auth/ftpd.group}"
export FTPS_CERTIFICATE_PATH="${FTPS_CERTIFICATE_PATH:-/etc/proftpd/tls/ftps.pem}"
export FTPS_CERTIFICATE_PEM="${FTPS_CERTIFICATE_PEM:-}"
export FTPS_CERTIFICATE_KEY_PEM="${FTPS_CERTIFICATE_KEY_PEM:-}"
export FTPS_PUBLIC_IP="${FTPS_PUBLIC_IP:-localhost}"
export FTPS_LISTEN_PORT="${FTPS_LISTEN_PORT:-990}"
export FTPS_PASSIVE_MIN_PORT="${FTPS_PASSIVE_MIN_PORT:-1024}"
export FTPS_PASSIVE_MAX_PORT="${FTPS_PASSIVE_MAX_PORT:-1034}"
export FTPS_ENABLE_STORAGE_FORWARD="${FTPS_ENABLE_STORAGE_FORWARD:-true}"
export FTPS_FORWARD_INTERVAL_SECONDS="${FTPS_FORWARD_INTERVAL_SECONDS:-60}"
export FTPS_FORWARD_LOCAL_DIR="${FTPS_FORWARD_LOCAL_DIR:-${FTPS_LOCAL_UPLOAD_DIR}}"
export FTPS_FORWARD_DELETE_AFTER="${FTPS_FORWARD_DELETE_AFTER:-false}"

if [[ -z "${FTPS_LOCAL_PASSWORD}" ]]; then
    echo "FTPS_LOCAL_PASSWORD must be set" >&2
    exit 1
fi

groupadd -f "${FTPS_LOCAL_USER}"
if ! id -u "${FTPS_LOCAL_USER}" >/dev/null 2>&1; then
    useradd -g "${FTPS_LOCAL_USER}" -d "${FTPS_LOCAL_ROOT}" -M -s /bin/bash "${FTPS_LOCAL_USER}"
fi

FTPS_LOCAL_PASSWORD_HASH="$(openssl passwd -6 "${FTPS_LOCAL_PASSWORD}")"
usermod -p "${FTPS_LOCAL_PASSWORD_HASH}" "${FTPS_LOCAL_USER}"

mkdir -p /srv/ftps "${FTPS_LOCAL_ROOT}" "${FTPS_LOCAL_UPLOAD_DIR}" "${FTPS_LOCAL_DOWNLOAD_DIR}" /var/log/proftpd
chown root:root /srv/ftps "${FTPS_LOCAL_ROOT}"
chmod 0755 /srv/ftps "${FTPS_LOCAL_ROOT}"
chmod 0750 "${FTPS_LOCAL_UPLOAD_DIR}"
chown "${FTPS_LOCAL_USER}:${FTPS_LOCAL_USER}" "${FTPS_LOCAL_UPLOAD_DIR}"
chown root:"${FTPS_LOCAL_USER}" "${FTPS_LOCAL_DOWNLOAD_DIR}"
chmod 0550 "${FTPS_LOCAL_DOWNLOAD_DIR}"

cat > "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt" <<EOF
HMCTS FTPS service

Upload files into the upload directory.
Download-only content can be placed in the download directory by an administrator.
EOF
chown root:"${FTPS_LOCAL_USER}" "${FTPS_LOCAL_DOWNLOAD_DIR}/README.txt"
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

cat > "${FTPS_AUTH_USER_FILE}" <<EOF
${FTPS_LOCAL_USER}:${FTPS_LOCAL_PASSWORD_HASH}:$(id -u "${FTPS_LOCAL_USER}"):$(id -g "${FTPS_LOCAL_USER}")::${FTPS_LOCAL_ROOT}:/bin/bash
EOF

cat > "${FTPS_AUTH_GROUP_FILE}" <<EOF
${FTPS_LOCAL_USER}:x:$(id -g "${FTPS_LOCAL_USER}"):${FTPS_LOCAL_USER}
EOF

chown root:"${FTPS_RUNTIME_GROUP}" "${FTPS_AUTH_DIR}" "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"
chmod 0750 "${FTPS_AUTH_DIR}"
chmod 0640 "${FTPS_AUTH_USER_FILE}" "${FTPS_AUTH_GROUP_FILE}"

FTPS_CERTIFICATE_DIR="$(dirname "${FTPS_CERTIFICATE_PATH}")"
FTPS_CERTIFICATE_MANAGED="false"

if [[ ! -d "${FTPS_CERTIFICATE_DIR}" ]]; then
    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "${FTPS_CERTIFICATE_DIR}"
fi

if [[ -n "${FTPS_CERTIFICATE_PEM}" && -n "${FTPS_CERTIFICATE_KEY_PEM}" && "${FTPS_CERTIFICATE_PEM}" != "${FTPS_CERTIFICATE_KEY_PEM}" ]]; then
    cat > "${FTPS_CERTIFICATE_PATH}" <<EOF
${FTPS_CERTIFICATE_KEY_PEM}
${FTPS_CERTIFICATE_PEM}
EOF
    FTPS_CERTIFICATE_MANAGED="true"
elif [[ -n "${FTPS_CERTIFICATE_PEM}" ]]; then
    printf '%s\n' "${FTPS_CERTIFICATE_PEM}" > "${FTPS_CERTIFICATE_PATH}"
    FTPS_CERTIFICATE_MANAGED="true"
fi

if [[ ! -f "${FTPS_CERTIFICATE_PATH}" ]]; then
    echo "FTPS certificate not found at ${FTPS_CERTIFICATE_PATH} and FTPS certificate environment variables were not provided" >&2
    exit 1
fi

if [[ "${FTPS_CERTIFICATE_MANAGED}" == "true" ]]; then
    chown root:"${FTPS_CERTIFICATE_GROUP}" "${FTPS_CERTIFICATE_PATH}"
    chmod 0640 "${FTPS_CERTIFICATE_PATH}"
fi

sed -i 's/^#\?LoadModule mod_tls.c/LoadModule mod_tls.c/' /etc/proftpd/modules.conf
envsubst < /etc/proftpd/proftpd-ftps.conf.template > /etc/proftpd/conf.d/hmcts-ftps.conf

if [[ "${FTPS_ENABLE_STORAGE_FORWARD}" == "true" ]]; then
    (
        while true; do
            /usr/local/bin/ftps-storage-forward.sh || true
            sleep "${FTPS_FORWARD_INTERVAL_SECONDS}"
        done
    ) &
fi

exec /usr/sbin/proftpd -n -c /etc/proftpd/proftpd.conf