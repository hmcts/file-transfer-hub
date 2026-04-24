#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FTPS_FORWARD_LOCAL_DIR:-}" ]]; then
  exit 0
fi

if [[ ! -d "${FTPS_FORWARD_LOCAL_DIR}" ]]; then
  exit 0
fi

if [[ -z "$(find "${FTPS_FORWARD_LOCAL_DIR}" -mindepth 1 -type f -print -quit)" ]]; then
  exit 0
fi

ftps_forward_log() {
  printf '[ftps-forward] %s\n' "$*" >&2
}

urlencode() {
  local value="$1"
  local length="${#value}"
  local index character encoded=""

  for (( index = 0; index < length; index++ )); do
    character="${value:index:1}"
    case "${character}" in
      [a-zA-Z0-9.~_-])
        encoded+="${character}"
        ;;
      *)
        printf -v encoded '%s%%%02X' "${encoded}" "'${character}"
        ;;
    esac
  done

  printf '%s' "${encoded}"
}

declare -a target_names=()
declare -a target_hosts=()
declare -a target_ports=()
declare -a target_usernames=()
declare -a target_passwords=()
declare -a target_remote_dirs=()

append_target() {
  local name="$1"
  local host="$2"
  local port="$3"
  local username="$4"
  local password="$5"
  local remote_dir="$6"

  if [[ -z "${host}" || -z "${username}" || -z "${password}" ]]; then
    ftps_forward_log "Skipping incomplete forward target ${name}"
    return 0
  fi

  target_names+=("${name}")
  target_hosts+=("${host}")
  target_ports+=("${port}")
  target_usernames+=("${username}")
  target_passwords+=("${password}")
  target_remote_dirs+=("${remote_dir}")
}

discover_targets() {
  local count="${FTPS_FORWARD_TARGET_COUNT:-}"

  if [[ -n "${count}" ]]; then
    if ! [[ "${count}" =~ ^[0-9]+$ ]]; then
      ftps_forward_log "Ignoring invalid FTPS_FORWARD_TARGET_COUNT=${count}"
    elif (( count > 0 )); then
      local index
      for (( index = 0; index < count; index++ )); do
        local prefix="FTPS_FORWARD_TARGET_${index}"
        local name_var="${prefix}_NAME"
        local host_var="${prefix}_HOST"
        local port_var="${prefix}_PORT"
        local username_var="${prefix}_USERNAME"
        local password_var="${prefix}_PASSWORD"
        local remote_dir_var="${prefix}_REMOTE_DIR"

        append_target \
          "${!name_var:-target-$((index + 1))}" \
          "${!host_var:-}" \
          "${!port_var:-22}" \
          "${!username_var:-}" \
          "${!password_var:-}" \
          "${!remote_dir_var:-.}"
      done

      return 0
    fi
  fi

  append_target \
    "storage" \
    "${FTPS_STORAGE_SFTP_HOST:-}" \
    "${FTPS_STORAGE_SFTP_PORT:-22}" \
    "${FTPS_STORAGE_SFTP_USERNAME:-}" \
    "${FTPS_STORAGE_SFTP_PASSWORD:-}" \
    "${FTPS_STORAGE_SFTP_REMOTE_DIR:-.}"
}

forward_to_target() {
  local name="$1"
  local host="$2"
  local port="$3"
  local username="$4"
  local password="$5"
  local remote_dir="$6"
  local remove_source_flag="$7"
  local encoded_username encoded_password

  ftps_forward_log "Forwarding files to ${name} (${host}:${port})"

  encoded_username="$(urlencode "${username}")"
  encoded_password="$(urlencode "${password}")"

  lftp "sftp://${encoded_username}:${encoded_password}@${host}:${port}" <<EOF
set cmd:fail-exit yes
set net:max-retries 2
set net:reconnect-interval-base 5
set net:timeout 20
set sftp:auto-confirm yes
set sftp:connect-program "ssh -a -x -o StrictHostKeyChecking=accept-new -o HostKeyAlgorithms=+ssh-rsa"
mirror --reverse --continue --only-newer --parallel=1 ${remove_source_flag} "${FTPS_FORWARD_LOCAL_DIR}" "${remote_dir}"
bye
EOF
}

discover_targets

if (( ${#target_hosts[@]} == 0 )); then
  exit 0
fi

for index in "${!target_hosts[@]}"; do
  remove_source_flag=""
  if [[ "${FTPS_FORWARD_DELETE_AFTER:-false}" == "true" && "${index}" -eq $((${#target_hosts[@]} - 1)) ]]; then
    remove_source_flag="--Remove-source-files"
  fi

  forward_to_target \
    "${target_names[index]}" \
    "${target_hosts[index]}" \
    "${target_ports[index]}" \
    "${target_usernames[index]}" \
    "${target_passwords[index]}" \
    "${target_remote_dirs[index]}" \
    "${remove_source_flag}"
done