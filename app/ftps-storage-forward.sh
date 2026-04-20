#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FTPS_FORWARD_LOCAL_DIR:-}" || -z "${FTPS_STORAGE_SFTP_HOST:-}" || -z "${FTPS_STORAGE_SFTP_USERNAME:-}" || -z "${FTPS_STORAGE_SFTP_PASSWORD:-}" ]]; then
  exit 0
fi

if [[ ! -d "${FTPS_FORWARD_LOCAL_DIR}" ]]; then
  exit 0
fi

if [[ -z "$(find "${FTPS_FORWARD_LOCAL_DIR}" -mindepth 1 -type f -print -quit)" ]]; then
  exit 0
fi

remove_source_flag=""
if [[ "${FTPS_FORWARD_DELETE_AFTER:-false}" == "true" ]]; then
  remove_source_flag="--Remove-source-files"
fi

lftp -u "${FTPS_STORAGE_SFTP_USERNAME},${FTPS_STORAGE_SFTP_PASSWORD}" "sftp://${FTPS_STORAGE_SFTP_HOST}:${FTPS_STORAGE_SFTP_PORT:-22}" <<EOF
set cmd:fail-exit yes
set net:max-retries 2
set net:reconnect-interval-base 5
set net:timeout 20
set sftp:auto-confirm yes
set sftp:connect-program "ssh -a -x -o StrictHostKeyChecking=accept-new"
mirror --reverse --continue --only-newer --parallel=1 ${remove_source_flag} "${FTPS_FORWARD_LOCAL_DIR}" "${FTPS_STORAGE_SFTP_REMOTE_DIR:-.}"
bye
EOF