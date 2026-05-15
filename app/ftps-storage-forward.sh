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
  local encoded_username encoded_password
  local remote_dir_escaped
  local lftp_script_file

  ftps_forward_log "Forwarding files to ${name} (${host}:${port})"

  encoded_username="$(urlencode "${username}")"
  encoded_password="$(urlencode "${password}")"
  remote_dir_escaped="${remote_dir//\\/\\\\}"
  remote_dir_escaped="${remote_dir_escaped//\"/\\\"}"

  lftp_script_file="$(mktemp)"
  {
    printf '%s\n' 'set cmd:fail-exit yes'
    printf '%s\n' 'set net:max-retries 2'
    printf '%s\n' 'set net:reconnect-interval-base 5'
    printf '%s\n' 'set net:timeout 20'
    printf '%s\n' 'set sftp:auto-confirm yes'
    printf '%s\n' 'set xfer:log yes'
    printf 'open "%s"\n' "sftp://${encoded_username}:${encoded_password}@${host}:${port}"
    printf 'lcd "%s"\n' "${FTPS_FORWARD_LOCAL_DIR}"
    if [[ "${remote_dir}" != "." ]]; then
      printf 'cd "%s"\n' "${remote_dir_escaped}"
    fi
    while IFS= read -r -d '' local_file; do
      local basename
      basename="$(basename "${local_file}")"
      printf 'put "%s"\n' "${basename//\"/\\\"}"
    done < <(find "${FTPS_FORWARD_LOCAL_DIR}" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
    printf '%s\n' 'bye'
  } > "${lftp_script_file}"

  local lftp_output
  if lftp_output="$(lftp -f "${lftp_script_file}" 2>&1)"; then
    if [[ -n "${lftp_output}" ]]; then
      while IFS= read -r line; do
        ftps_forward_log "${name}: ${line}"
      done <<< "${lftp_output}"
    fi
    ftps_forward_log "Forwarding to ${name} completed successfully"
    rm -f "${lftp_script_file}"
  else
    if [[ -n "${lftp_output}" ]]; then
      while IFS= read -r line; do
        ftps_forward_log "${name}: ${line}"
      done <<< "${lftp_output}"
    fi
    ftps_forward_log "Forwarding to ${name} failed"
    rm -f "${lftp_script_file}"
    return 1
  fi
}

delete_forwarded_files() {
  ftps_forward_log "Deleting local files after successful forwarding to all targets"
  find "${FTPS_FORWARD_LOCAL_DIR}" -type f -delete
}

discover_targets

if (( ${#target_hosts[@]} == 0 )); then
  exit 0
fi

for index in "${!target_hosts[@]}"; do
  forward_to_target \
    "${target_names[index]}" \
    "${target_hosts[index]}" \
    "${target_ports[index]}" \
    "${target_usernames[index]}" \
    "${target_passwords[index]}" \
    "${target_remote_dirs[index]}"
done

if [[ "${FTPS_FORWARD_DELETE_AFTER:-false}" == "true" ]]; then
  delete_forwarded_files
fi