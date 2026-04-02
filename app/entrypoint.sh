#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
#  Entrypoint – configures runtime values, starts vsftpd,
#               cron, and the SFTP forwarder
# ═══════════════════════════════════════════════════════════════════

# ── Required environment variables ─────────────────────────────────
#   PASV_ADDRESS     – lowercase FQDN or static public IP
#   FTP_USER_PASS    – password for the ftpuser account
#
# ── Development mode (optional) ───────────────────────────────────
#   DEV_MODE=true    – disables TLS entirely (plain FTP on port 990)
#                      DO NOT USE IN PRODUCTION
#
# ── SFTP forwarding (all optional – forwarder only starts if set) ──
#   SFTP_FWD_HOST, SFTP_FWD_USER, SFTP_FWD_KEY,
#   SFTP_FWD_REMOTE_DIR, SFTP_FWD_KNOWN_HOSTS
#   (see sftp-forwarder.sh for full list)
#
# ── Let's Encrypt (optional) ──────────────────────────────────────
#   LE_DOMAIN        – domain for certbot
#   LE_EMAIL         – registration email
# ───────────────────────────────────────────────────────────────────

: "${PASV_ADDRESS:?Environment variable PASV_ADDRESS is required (lowercase FQDN or static IP)}"
: "${FTP_USER_PASS:?Environment variable FTP_USER_PASS is required}"

DEV_MODE="${DEV_MODE:-false}"

# ── 0. Dev mode guard ─────────────────────────────────────────────
if [[ "${DEV_MODE}" == "true" ]]; then
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ⚠  DEV_MODE=true — TLS IS DISABLED                     ║"
    echo "║  Plain unencrypted FTP on port 990.                      ║"
    echo "║  DO NOT RUN THIS IN PRODUCTION.                          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
fi

# ── 1. Set passive address (must be lowercase FQDN) ───────────────
PASV_LOWER=$(echo "${PASV_ADDRESS}" | tr '[:upper:]' '[:lower:]')
sed -i "s|PLACEHOLDER_PASV_ADDRESS|${PASV_LOWER}|g" /etc/vsftpd/vsftpd.conf
echo ">> Passive address set to: ${PASV_LOWER}"

# ── 2. Set FTP user password ──────────────────────────────────────
echo "ftpuser:${FTP_USER_PASS}" | chpasswd
echo ">> FTP user password configured"

# ── 3. TLS certificate handling ───────────────────────────────────
if [[ "${DEV_MODE}" == "true" ]]; then
    # Strip all TLS/SSL directives from the config
    sed -i '/^ssl_enable=/c\ssl_enable=NO'             /etc/vsftpd/vsftpd.conf
    sed -i '/^implicit_ssl=/d'                         /etc/vsftpd/vsftpd.conf
    sed -i '/^allow_anon_ssl=/d'                       /etc/vsftpd/vsftpd.conf
    sed -i '/^force_local_data_ssl=/d'                 /etc/vsftpd/vsftpd.conf
    sed -i '/^force_local_logins_ssl=/d'               /etc/vsftpd/vsftpd.conf
    sed -i '/^ssl_tlsv1=/d'                            /etc/vsftpd/vsftpd.conf
    sed -i '/^ssl_tlsv1_1=/d'                          /etc/vsftpd/vsftpd.conf
    sed -i '/^ssl_tlsv1_2=/d'                          /etc/vsftpd/vsftpd.conf
    sed -i '/^ssl_ciphers=/d'                          /etc/vsftpd/vsftpd.conf
    sed -i '/^require_ssl_reuse=/d'                    /etc/vsftpd/vsftpd.conf
    sed -i '/^rsa_cert_file=/d'                        /etc/vsftpd/vsftpd.conf
    sed -i '/^rsa_private_key_file=/d'                 /etc/vsftpd/vsftpd.conf
    echo ">> TLS disabled (DEV_MODE)"
else
    # ── Production: obtain or validate certificates ────────────────
    if [[ -n "${LE_DOMAIN:-}" ]]; then
        LE_EMAIL="${LE_EMAIL:-admin@${LE_DOMAIN}}"
        echo ">> Requesting Let's Encrypt certificate for ${LE_DOMAIN} ..."
        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "${LE_EMAIL}" \
            --preferred-challenges http \
            -d "${LE_DOMAIN}" \
            --cert-path   /etc/vsftpd/certs/fullchain.pem \
            --key-path    /etc/vsftpd/certs/privkey.pem \
            || true

        if [[ -d "/etc/letsencrypt/live/${LE_DOMAIN}" ]]; then
            ln -sf "/etc/letsencrypt/live/${LE_DOMAIN}/fullchain.pem" /etc/vsftpd/certs/fullchain.pem
            ln -sf "/etc/letsencrypt/live/${LE_DOMAIN}/privkey.pem"   /etc/vsftpd/certs/privkey.pem
            echo ">> Let's Encrypt certificate linked"
        fi
    fi

    if [[ ! -f /etc/vsftpd/certs/fullchain.pem ]] || [[ ! -f /etc/vsftpd/certs/privkey.pem ]]; then
        echo "!! ERROR: TLS certificate not found at /etc/vsftpd/certs/{fullchain,privkey}.pem"
        echo "!! Mount your certificate, set LE_DOMAIN for Let's Encrypt, or set DEV_MODE=true."
        exit 1
    fi

    chmod 600 /etc/vsftpd/certs/privkey.pem
    chmod 644 /etc/vsftpd/certs/fullchain.pem
    echo ">> TLS certificates verified"
fi

# ── 4. Ensure upload directory permissions ─────────────────────────
chown ftpuser:ftpusers /home/ftpuser/ftp/uploads
chmod 775 /home/ftpuser/ftp/uploads

# ── 5. Start cron (30-day file cleanup) ───────────────────────────
crond -b -l 8
echo ">> Cron started (30-day retention cleanup)"

# ── 6. Start SFTP forwarder (if configured) ───────────────────────
if [[ -n "${SFTP_FWD_HOST:-}" ]]; then
    echo ">> Starting SFTP forwarder → ${SFTP_FWD_USER:-?}@${SFTP_FWD_HOST}:${SFTP_FWD_PORT:-22}"

    if [[ -n "${SFTP_FWD_KEY:-}" ]] && [[ -f "${SFTP_FWD_KEY}" ]]; then
        chmod 600 "${SFTP_FWD_KEY}"
    fi

    /usr/local/bin/sftp-forwarder.sh &
    FORWARDER_PID=$!
    echo ">> SFTP forwarder running (PID ${FORWARDER_PID})"

    trap "kill ${FORWARDER_PID} 2>/dev/null; wait ${FORWARDER_PID} 2>/dev/null" EXIT
else
    echo ">> SFTP forwarding disabled (SFTP_FWD_HOST not set)"
fi

# ── 7. Launch vsftpd in foreground ────────────────────────────────
if [[ "${DEV_MODE}" == "true" ]]; then
    echo ">> Starting vsftpd on port 990 (plain FTP — DEV_MODE) ..."
else
    echo ">> Starting vsftpd on port 990 (implicit FTPS) ..."
fi
exec vsftpd /etc/vsftpd/vsftpd.conf