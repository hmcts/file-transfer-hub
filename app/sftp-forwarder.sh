#!/usr/bin/env bash
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════
#  SFTP Forwarder
#  Watches the uploads directory for completed file writes and
#  forwards them to a configurable remote SFTP endpoint.
#
#  Environment variables (all prefixed SFTP_FWD_):
#    SFTP_FWD_HOST        – remote SFTP hostname (required)
#    SFTP_FWD_PORT        – remote SFTP port (default: 22)
#    SFTP_FWD_USER        – remote SFTP username (required)
#    SFTP_FWD_KEY         – path to private key (required)
#    SFTP_FWD_REMOTE_DIR  – remote destination directory (required)
#    SFTP_FWD_KNOWN_HOSTS – path to known_hosts file (required)
#    SFTP_FWD_RETRIES     – max retry attempts (default: 3)
#    SFTP_FWD_RETRY_DELAY – seconds between retries (default: 10)
#    SFTP_FWD_DELETE_AFTER– delete local file after forward (default: false)
# ═══════════════════════════════════════════════════════════════════

WATCH_DIR="/home/ftpuser/ftp/uploads"
FORWARDED_DIR="/var/lib/sftp-forward/forwarded"
FAILED_DIR="/var/lib/sftp-forward/failed"
LOG_FILE="/var/log/sftp-forward/forwarder.log"

HOST="${SFTP_FWD_HOST:?SFTP_FWD_HOST is required}"
PORT="${SFTP_FWD_PORT:-22}"
USER="${SFTP_FWD_USER:?SFTP_FWD_USER is required}"
KEY="${SFTP_FWD_KEY:?SFTP_FWD_KEY is required}"
REMOTE_DIR="${SFTP_FWD_REMOTE_DIR:?SFTP_FWD_REMOTE_DIR is required}"
KNOWN_HOSTS="${SFTP_FWD_KNOWN_HOSTS:?SFTP_FWD_KNOWN_HOSTS is required}"
MAX_RETRIES="${SFTP_FWD_RETRIES:-3}"
RETRY_DELAY="${SFTP_FWD_RETRY_DELAY:-10}"
DELETE_AFTER="${SFTP_FWD_DELETE_AFTER:-false}"

# ── Logging helper ─────────────────────────────────────────────────
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [${level}] $*" | tee -a "${LOG_FILE}"
}

# ── Validate prerequisites ─────────────────────────────────────────
if [[ ! -f "${KEY}" ]]; then
    log "FATAL" "Private key not found at ${KEY}"
    exit 1
fi
chmod 600 "${KEY}"

if [[ ! -f "${KNOWN_HOSTS}" ]]; then
    log "FATAL" "known_hosts file not found at ${KNOWN_HOSTS}"
    exit 1
fi

log "INFO" "SFTP Forwarder started"
log "INFO" "  Target:  ${USER}@${HOST}:${PORT}${REMOTE_DIR}"
log "INFO" "  Watching: ${WATCH_DIR}"
log "INFO" "  Retries: ${MAX_RETRIES}, delay: ${RETRY_DELAY}s"

# ── Upload function with retry ─────────────────────────────────────
upload_file() {
    local filepath="$1"
    local filename
    filename="$(basename "${filepath}")"
    local attempt=1

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log "INFO" "Uploading ${filename} → ${HOST}:${REMOTE_DIR} (attempt ${attempt}/${MAX_RETRIES})"

        # Build SFTP batch command
        local batch_file
        batch_file="$(mktemp /tmp/sftp-batch.XXXXXX)"
        cat > "${batch_file}" <<BATCH
cd ${REMOTE_DIR}
put "${filepath}" "${filename}.part"
rename "${filename}.part" "${filename}"
BATCH

        # Execute SFTP transfer
        sftp -i "${KEY}" \
             -P "${PORT}" \
             -o UserKnownHostsFile="${KNOWN_HOSTS}" \
             -o StrictHostKeyChecking=yes \
             -o ConnectTimeout=30 \
             -o ServerAliveInterval=15 \
             -o ServerAliveCountMax=3 \
             -o PasswordAuthentication=no \
             -b "${batch_file}" \
             "${USER}@${HOST}" >> "${LOG_FILE}" 2>&1
        local rc=$?

        rm -f "${batch_file}"

        if [[ ${rc} -eq 0 ]]; then
            log "INFO" "Successfully forwarded: ${filename}"

            # Record successful transfer
            echo "$(date -Iseconds) ${filename}" >> "${FORWARDED_DIR}/manifest.log"

            if [[ "${DELETE_AFTER}" == "true" ]]; then
                rm -f "${filepath}"
                log "INFO" "Deleted local file: ${filename}"
            fi
            return 0
        fi

        log "WARN" "Upload failed for ${filename} (rc=${rc}), retrying in ${RETRY_DELAY}s..."
        sleep "${RETRY_DELAY}"
        attempt=$((attempt + 1))
    done

    # All retries exhausted – move to dead-letter queue
    log "ERROR" "All ${MAX_RETRIES} attempts failed for ${filename} – moving to failed/"
    cp "${filepath}" "${FAILED_DIR}/${filename}.$(date +%s)"
    echo "$(date -Iseconds) ${filename}" >> "${FAILED_DIR}/manifest.log"
    return 1
}

# ── Forward any files that arrived while we were offline ───────────
log "INFO" "Checking for backlog files..."
find "${WATCH_DIR}" -type f -name '*.zip' | while read -r backlog_file; do
    upload_file "${backlog_file}"
done

# ── Watch for new files using inotifywait ──────────────────────────
#    CLOSE_WRITE fires when a file is fully written and closed,
#    ensuring we don't upload partial files.
log "INFO" "Entering inotifywait loop..."
inotifywait -m -e close_write --format '%w%f' "${WATCH_DIR}" 2>>"${LOG_FILE}" | \
while read -r new_file; do
    # Skip non-regular files and temp files
    [[ ! -f "${new_file}" ]] && continue
    [[ "${new_file}" == *.part ]] && continue
    [[ "${new_file}" == *.tmp ]]  && continue

    log "INFO" "New file detected: $(basename "${new_file}")"
    upload_file "${new_file}" &
    # Limit concurrent uploads – wait if > 4 background jobs
    while [[ $(jobs -rp | wc -l) -ge 4 ]]; do
        sleep 1
    done
done