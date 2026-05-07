#!/usr/bin/env bash

# Sourced by the storage-forward wrapper and unit tests. The executable wrapper
# owns strict Bash options; this library owns target discovery and lftp command
# construction so those behaviours can be tested without starting containers.

declare -a target_names=()
declare -a target_hosts=()
declare -a target_ports=()
declare -a target_usernames=()
declare -a target_passwords=()
declare -a target_remote_dirs=()

# Clears all discovered forwarding targets.
#
# Globals:
#   target_names: Reset to an empty array.
#   target_hosts: Reset to an empty array.
#   target_ports: Reset to an empty array.
#   target_usernames: Reset to an empty array.
#   target_passwords: Reset to an empty array.
#   target_remote_dirs: Reset to an empty array.
ftps_forward_reset_targets() {
    target_names=()
    target_hosts=()
    target_ports=()
    target_usernames=()
    target_passwords=()
    target_remote_dirs=()
}

ftps_forward_log() {
    printf '[ftps-forward] %s\n' "$*" >&2
}

ftps_is_port_number() {
    local value="$1"

    [[ "${value}" =~ ^[0-9]{1,5}$ ]] && ((10#${value} >= 1 && 10#${value} <= 65535))
}

# Checks whether a path is safe to interpolate into lftp command language.
#
# Arguments:
#   $1: Path value to validate.
# Returns:
#   0 when the path contains no double quotes, backslashes or newlines;
#   non-zero otherwise.
ftps_lftp_path_is_safe() {
    local value="$1"
    local double_quote='"'
    local backslash=$'\\'

    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* && "${value}" != *"${double_quote}"* && "${value}" != *"${backslash}"* ]]
}

# Validates an lftp path and logs a contextual error.
#
# Arguments:
#   $1: Human-readable path description for error messages.
#   $2: Path value to validate.
# Outputs:
#   Writes validation failures to stderr via ftps_forward_log.
# Returns:
#   0 when the path is safe; non-zero so callers can skip or fail safely.
ftps_validate_lftp_path() {
    local description="$1"
    local value="$2"

    if ! ftps_lftp_path_is_safe "${value}"; then
        ftps_forward_log "${description} cannot contain double quotes, backslashes, or newlines because it is rendered into an lftp command"
        return 1
    fi
}

# Percent-encodes a value for inclusion in an lftp SFTP URL.
#
# Arguments:
#   $1: Raw value to percent-encode; may contain credentials.
# Outputs:
#   Writes the encoded value to stdout.
# Returns:
#   0 when encoding succeeds.
urlencode() {
    local value="$1"
    local length="${#value}"
    local index character encoded=""

    for ((index = 0; index < length; index++)); do
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

# Validates and appends one forwarding target to the shared arrays.
#
# Globals:
#   target_names: Appended with the target name when valid.
#   target_hosts: Appended with the target host when valid.
#   target_ports: Appended with the target port when valid.
#   target_usernames: Appended with the target username when valid.
#   target_passwords: Appended with the target password when valid.
#   target_remote_dirs: Appended with the target remote directory when valid.
# Arguments:
#   $1: Target display name.
#   $2: SFTP host.
#   $3: SFTP port.
#   $4: SFTP username.
#   $5: SFTP password.
#   $6: SFTP remote directory.
# Outputs:
#   Writes skip reasons to stderr via ftps_forward_log.
# Returns:
#   0 after appending a valid target or skipping an invalid/incomplete target.
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

    if ! ftps_is_port_number "${port}"; then
        ftps_forward_log "Skipping forward target ${name}: port must be an integer between 1 and 65535"
        return 0
    fi

    if ! ftps_validate_lftp_path "Skipping forward target ${name}: remote directory" "${remote_dir}"; then
        return 0
    fi

    target_names+=("${name}")
    target_hosts+=("${host}")
    target_ports+=("${port}")
    target_usernames+=("${username}")
    target_passwords+=("${password}")
    target_remote_dirs+=("${remote_dir}")
}

# Discovers indexed forwarding targets from environment variables.
#
# Globals:
#   FTPS_FORWARD_TARGET_<n>_NAME: Read as the optional target name.
#   FTPS_FORWARD_TARGET_<n>_HOST: Read as the target host.
#   FTPS_FORWARD_TARGET_<n>_PORT: Read as the target port, defaulting to 22.
#   FTPS_FORWARD_TARGET_<n>_USERNAME: Read as the target username.
#   FTPS_FORWARD_TARGET_<n>_PASSWORD: Read as the target password.
#   FTPS_FORWARD_TARGET_<n>_REMOTE_DIR: Read as the remote directory, defaulting to '.'.
#   target_*: Mutated through append_target for each valid target.
# Arguments:
#   $1: Number of indexed target slots to inspect, starting at 0.
# Outputs:
#   Writes skip reasons to stderr via append_target.
ftps_discover_indexed_targets() {
    local count="$1"
    local index

    for ((index = 0; index < count; index++)); do
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
}

# Discovers the legacy single SFTP forwarding target.
#
# Globals:
#   FTPS_STORAGE_SFTP_HOST: Read as the target host.
#   FTPS_STORAGE_SFTP_PORT: Read as the target port, defaulting to 22.
#   FTPS_STORAGE_SFTP_USERNAME: Read as the target username.
#   FTPS_STORAGE_SFTP_PASSWORD: Read as the target password.
#   FTPS_STORAGE_SFTP_REMOTE_DIR: Read as the remote directory, defaulting to '.'.
#   target_*: Mutated through append_target when the target is valid.
# Outputs:
#   Writes skip reasons to stderr via append_target.
ftps_discover_legacy_target() {
    append_target \
        "storage" \
        "${FTPS_STORAGE_SFTP_HOST:-}" \
        "${FTPS_STORAGE_SFTP_PORT:-22}" \
        "${FTPS_STORAGE_SFTP_USERNAME:-}" \
        "${FTPS_STORAGE_SFTP_PASSWORD:-}" \
        "${FTPS_STORAGE_SFTP_REMOTE_DIR:-.}"
}

# Discovers forwarding targets using indexed configuration before legacy config.
#
# Globals:
#   FTPS_FORWARD_TARGET_COUNT: Read to choose indexed discovery when positive.
#   FTPS_FORWARD_TARGET_<n>_*: Read when indexed discovery is selected.
#   FTPS_STORAGE_SFTP_*: Read when falling back to legacy discovery.
#   target_*: Mutated by the selected discovery path.
# Outputs:
#   Writes invalid-count and target skip messages to stderr.
discover_targets() {
    local count="${FTPS_FORWARD_TARGET_COUNT:-}"

    if [[ -n "${count}" ]]; then
        if ! [[ "${count}" =~ ^[0-9]+$ ]]; then
            ftps_forward_log "Ignoring invalid FTPS_FORWARD_TARGET_COUNT=${count}"
        elif ((count > 0)); then
            ftps_discover_indexed_targets "${count}"
            return 0
        fi
    fi

    ftps_discover_legacy_target
}

# Checks whether there is local work to forward.
#
# Globals:
#   FTPS_FORWARD_LOCAL_DIR: Read as the local upload directory.
# Returns:
#   0 when the directory exists and contains a regular file; non-zero otherwise.
ftps_forward_has_local_files() {
    if [[ -z "${FTPS_FORWARD_LOCAL_DIR:-}" ]]; then
        return 1
    fi

    if [[ ! -d "${FTPS_FORWARD_LOCAL_DIR}" ]]; then
        return 1
    fi

    if [[ -z "$(find "${FTPS_FORWARD_LOCAL_DIR}" -mindepth 1 -type f -print -quit)" ]]; then
        return 1
    fi

    return 0
}

ftps_log_lftp_output() {
    local name="$1"
    local lftp_output="$2"
    local line

    if [[ -z "${lftp_output}" ]]; then
        return 0
    fi

    while IFS= read -r line; do
        ftps_forward_log "${name}: ${line}"
    done <<<"${lftp_output}"
}

# Emits the lftp command script for a reverse mirror.
#
# Globals:
#   FTPS_FORWARD_LOCAL_DIR: Read as the local source directory.
# Arguments:
#   $1: Remote SFTP directory; must already have passed ftps_validate_lftp_path.
#   $2: Optional lftp source-removal flag.
# Outputs:
#   Writes lftp command language to stdout.
# Returns:
#   0 when the command script is written.
ftps_lftp_mirror_command() {
    local remote_dir="$1"
    local remove_source_flag="$2"

    # lftp reads this as its own command language, not as shell. Paths are
    # validated before interpolation to avoid command injection or ambiguous
    # quoting while still allowing ordinary POSIX-style SFTP directories.
    cat <<EOF
set cmd:fail-exit yes
set net:max-retries 2
set net:reconnect-interval-base 5
set net:timeout 20
set sftp:auto-confirm yes
set xfer:log yes
set sftp:connect-program "ssh -a -x -o StrictHostKeyChecking=accept-new -o HostKeyAlgorithms=+ssh-rsa"
mirror --reverse --continue --only-newer --parallel=1 ${remove_source_flag} "${FTPS_FORWARD_LOCAL_DIR}" "${remote_dir}"
bye
EOF
}

# Forwards local files to one configured target using lftp.
#
# Arguments:
#   $1: Target display name.
#   $2: SFTP host.
#   $3: SFTP port.
#   $4: SFTP username.
#   $5: SFTP password; must not be logged by callers.
#   $6: SFTP remote directory.
#   $7: Optional lftp source-removal flag.
# Outputs:
#   Writes forwarding status and lftp output to stderr via ftps_forward_log.
# Returns:
#   0 when lftp succeeds; non-zero when the transfer command fails.
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

    local lftp_output
    if lftp_output="$(
        lftp "sftp://${encoded_username}:${encoded_password}@${host}:${port}" 2>&1 <<EOF
$(ftps_lftp_mirror_command "${remote_dir}" "${remove_source_flag}")
EOF
    )"; then
        ftps_log_lftp_output "${name}" "${lftp_output}"
        ftps_forward_log "Forwarding to ${name} completed successfully"
    else
        ftps_log_lftp_output "${name}" "${lftp_output}"
        ftps_forward_log "Forwarding to ${name} failed"
        return 1
    fi
}

# Computes the lftp source-removal flag for a fan-out target.
#
# Globals:
#   target_hosts: Read to determine the last configured target index.
#   FTPS_FORWARD_DELETE_AFTER: Read to decide whether source deletion is enabled.
# Arguments:
#   $1: Current target array index.
# Outputs:
#   Writes '--Remove-source-files' to stdout only for the final target when enabled;
#   otherwise writes an empty string.
# Returns:
#   0 after writing the flag value.
ftps_remove_source_flag_for_target() {
    local index="$1"
    local last_index="$((${#target_hosts[@]} - 1))"

    # Fan-out requires every target to see the uploaded files. Only the final
    # target may remove local sources after its successful mirror completes.
    if [[ "${FTPS_FORWARD_DELETE_AFTER:-false}" == "true" && "${index}" -eq "${last_index}" ]]; then
        printf '%s' '--Remove-source-files'
        return 0
    fi

    printf '%s' ''
}

# Runs one storage-forwarding iteration.
#
# Globals:
#   FTPS_FORWARD_LOCAL_DIR: Read and validated as the local source directory.
#   FTPS_FORWARD_DELETE_AFTER: Read when computing per-target delete behaviour.
#   FTPS_FORWARD_TARGET_COUNT: Read during target discovery.
#   FTPS_FORWARD_TARGET_<n>_*: Read during indexed target discovery.
#   FTPS_STORAGE_SFTP_*: Read during legacy target discovery.
#   target_*: Reset and populated during target discovery.
# Outputs:
#   Writes validation, discovery and transfer status messages to stderr.
# Returns:
#   0 for empty directories, no valid targets or successful transfers;
#   non-zero for unsafe local paths or failed transfers.
ftps_storage_forward_main() {
    local index remove_source_flag

    if ! ftps_forward_has_local_files; then
        return 0
    fi

    ftps_validate_lftp_path "FTPS_FORWARD_LOCAL_DIR" "${FTPS_FORWARD_LOCAL_DIR}" || return 1

    ftps_forward_reset_targets
    discover_targets

    if ((${#target_hosts[@]} == 0)); then
        return 0
    fi

    for index in "${!target_hosts[@]}"; do
        remove_source_flag="$(ftps_remove_source_flag_for_target "${index}")"

        forward_to_target \
            "${target_names[index]}" \
            "${target_hosts[index]}" \
            "${target_ports[index]}" \
            "${target_usernames[index]}" \
            "${target_passwords[index]}" \
            "${target_remote_dirs[index]}" \
            "${remove_source_flag}"
    done
}
