#!/usr/bin/env bash

# Sourced by entrypoint.sh and Bats tests. Keep this file side-effect-light:
# callers provide ftps_log/ftps_warn and the certificate destination variables,
# while these helpers own parsing, matching and cleanup of transient PEM parts.

# Extracts the first PEM private-key block from a source bundle.
#
# Arguments:
#   $1: Source PEM bundle path.
#   $2: Destination file for the extracted private-key block.
# Outputs:
#   Writes the private-key PEM block to the destination file.
# Returns:
#   0 when a private key is found; non-zero when no private key is present.
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
    ' "${source_file}" >"${destination_file}"
}

# Splits PEM certificate blocks into numbered files.
#
# Arguments:
#   $1: Source PEM bundle path.
#   $2: Destination file prefix for numbered certificate blocks.
# Outputs:
#   Writes certificate files as ${prefix}.1, ${prefix}.2, and so on.
#   Writes the number of certificate blocks to stdout.
# Returns:
#   0 even when no certificates are present, reporting count 0.
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

# Compares the public key in a certificate with a private key.
#
# Arguments:
#   $1: Certificate PEM file to inspect.
#   $2: Private-key PEM file to compare against.
# Returns:
#   0 when the public keys match; non-zero on mismatch or OpenSSL failure.
ftps_certificate_matches_private_key() {
    local certificate_file="$1"
    local private_key_file="$2"
    local certificate_public_key_file private_key_public_key_file result

    certificate_public_key_file="$(mktemp)"
    private_key_public_key_file="$(mktemp)"

    result=1
    if openssl x509 -in "${certificate_file}" -pubkey -noout >"${certificate_public_key_file}" 2>/dev/null &&
        openssl pkey -in "${private_key_file}" -pubout >"${private_key_public_key_file}" 2>/dev/null &&
        cmp -s "${certificate_public_key_file}" "${private_key_public_key_file}"; then
        result=0
    fi

    rm -f "${certificate_public_key_file}" "${private_key_public_key_file}"
    return "${result}"
}

# Removes temporary certificate parsing files.
#
# Arguments:
#   $1: Temporary private-key file path.
#   $2: Temporary certificate file prefix.
# Returns:
#   0 even when files are already absent.
ftps_cleanup_certificate_temp_files() {
    local private_key_file="$1"
    local certificate_prefix="$2"

    rm -f "${private_key_file}" "${certificate_prefix}".*
}

# Parses PEM source material into prepared temporary parts.
#
# Globals:
#   FTPS_CERTIFICATE_PRIVATE_KEY_FILE: Set to the extracted private-key temp file.
#   FTPS_CERTIFICATE_PREFIX: Set to the numbered certificate temp file prefix.
#   FTPS_CERTIFICATE_COUNT: Set to the number of certificate blocks found.
#   FTPS_MATCHING_CERTIFICATE_INDEX: Set to the 1-based matching leaf index.
# Arguments:
#   $1: Source PEM bundle path.
# Outputs:
#   Writes validation failures to stderr via ftps_warn.
# Returns:
#   Exits with 1 when key, certificates or key match are invalid; returns 0 otherwise.
ftps_prepare_certificate_parts() {
    local source_file="$1"

    FTPS_CERTIFICATE_PRIVATE_KEY_FILE="$(mktemp)"
    FTPS_CERTIFICATE_PREFIX="$(mktemp)"

    if ! ftps_extract_private_key_block "${source_file}" "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}"; then
        ftps_cleanup_certificate_temp_files "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" "${FTPS_CERTIFICATE_PREFIX}"
        ftps_warn "FTPS certificate content did not contain a private key PEM block"
        exit 1
    fi

    FTPS_CERTIFICATE_COUNT="$(ftps_extract_certificate_blocks "${source_file}" "${FTPS_CERTIFICATE_PREFIX}")"
    if [[ "${FTPS_CERTIFICATE_COUNT}" -eq 0 ]]; then
        ftps_cleanup_certificate_temp_files "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" "${FTPS_CERTIFICATE_PREFIX}"
        ftps_warn "FTPS certificate content did not contain any certificate PEM blocks"
        exit 1
    fi

    # Secrets and PKCS#12 exports can contain certificates in any order. Find the
    # certificate that matches the private key and make it the first certificate
    # so ProFTPD receives a key-plus-leaf bundle followed by any chain certs.
    if ! FTPS_MATCHING_CERTIFICATE_INDEX="$(ftps_find_matching_certificate_index "${FTPS_CERTIFICATE_COUNT}" "${FTPS_CERTIFICATE_PREFIX}" "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}")"; then
        ftps_cleanup_certificate_temp_files "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" "${FTPS_CERTIFICATE_PREFIX}"
        ftps_warn "FTPS certificate content did not contain a certificate matching the supplied private key"
        exit 1
    fi
}

# Writes a normalized PEM bundle from prepared certificate parts.
#
# Globals:
#   FTPS_CERTIFICATE_PRIVATE_KEY_FILE: Read as the private-key source file.
#   FTPS_CERTIFICATE_PREFIX: Read as the numbered certificate file prefix.
#   FTPS_CERTIFICATE_COUNT: Read as the number of certificate blocks.
#   FTPS_MATCHING_CERTIFICATE_INDEX: Read as the leaf certificate index.
# Arguments:
#   $1: Destination normalized PEM bundle path.
# Outputs:
#   Writes private key, matching leaf certificate and remaining chain certs.
# Returns:
#   0 when all file writes succeed; non-zero otherwise.
ftps_write_normalized_certificate_chain() {
    local destination_file="$1"
    local certificate_index

    cat "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" >"${destination_file}"
    cat "${FTPS_CERTIFICATE_PREFIX}.${FTPS_MATCHING_CERTIFICATE_INDEX}" >>"${destination_file}"

    for certificate_index in $(seq 1 "${FTPS_CERTIFICATE_COUNT}"); do
        if [[ "${certificate_index}" == "${FTPS_MATCHING_CERTIFICATE_INDEX}" ]]; then
            continue
        fi

        cat "${FTPS_CERTIFICATE_PREFIX}.${certificate_index}" >>"${destination_file}"
    done
}

# Cleans prepared certificate parts and clears their globals.
#
# Globals:
#   FTPS_CERTIFICATE_PRIVATE_KEY_FILE: Read then unset.
#   FTPS_CERTIFICATE_PREFIX: Read then unset.
#   FTPS_CERTIFICATE_COUNT: Unset.
#   FTPS_MATCHING_CERTIFICATE_INDEX: Unset.
# Returns:
#   0 even when temporary files are already absent.
ftps_cleanup_prepared_certificate_parts() {
    ftps_cleanup_certificate_temp_files "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" "${FTPS_CERTIFICATE_PREFIX}"
    unset FTPS_CERTIFICATE_PRIVATE_KEY_FILE
    unset FTPS_CERTIFICATE_PREFIX
    unset FTPS_CERTIFICATE_COUNT
    unset FTPS_MATCHING_CERTIFICATE_INDEX
}

# Finds the numbered certificate that matches a private key.
#
# Arguments:
#   $1: Number of certificate files to inspect.
#   $2: Certificate file prefix used with 1-based numeric suffixes.
#   $3: Private-key PEM file to compare against.
# Outputs:
#   Writes the matching 1-based certificate index to stdout.
# Returns:
#   0 when a matching certificate is found; non-zero otherwise.
ftps_find_matching_certificate_index() {
    local certificate_count="$1"
    local certificate_prefix="$2"
    local private_key_file="$3"
    local certificate_index

    for certificate_index in $(seq 1 "${certificate_count}"); do
        if ftps_certificate_matches_private_key "${certificate_prefix}.${certificate_index}" "${private_key_file}"; then
            printf '%s' "${certificate_index}"
            return 0
        fi
    done

    return 1
}

# Normalizes a PEM source into a destination bundle.
#
# Arguments:
#   $1: Source PEM bundle path.
#   $2: Destination normalized PEM bundle path.
# Outputs:
#   Writes the normalized PEM bundle to the destination path.
# Returns:
#   The normalized bundle write status; exits on invalid certificate material.
ftps_normalize_pem_bundle() {
    local source_file="$1"
    local destination_file="$2"
    local status

    ftps_prepare_certificate_parts "${source_file}"
    status=0
    ftps_write_normalized_certificate_chain "${destination_file}" || status=$?
    ftps_cleanup_prepared_certificate_parts
    return "${status}"
}

# Writes ProFTPD runtime TLS material from a PEM source.
#
# Globals:
#   FTPS_CERTIFICATE_GROUP: Read as the file ownership group.
#   FTPS_TLS_CHAIN_DIRECTIVE: Set to the ProFTPD chain directive, or empty.
# Arguments:
#   $1: Source PEM bundle path.
#   $2: Destination server PEM path for private key plus leaf certificate.
#   $3: Destination chain PEM path for remaining certificates.
# Outputs:
#   Writes server PEM and optional chain PEM files.
# Returns:
#   0 when runtime files are written; exits on invalid certificate material.
ftps_prepare_proftpd_tls_material() {
    local source_file="$1"
    local certificate_file="$2"
    local chain_file="$3"
    local certificate_index

    ftps_prepare_certificate_parts "${source_file}"

    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "$(dirname "${certificate_file}")"
    install -d -m 0750 -o root -g "${FTPS_CERTIFICATE_GROUP}" "$(dirname "${chain_file}")"

    cat "${FTPS_CERTIFICATE_PRIVATE_KEY_FILE}" >"${certificate_file}"
    cat "${FTPS_CERTIFICATE_PREFIX}.${FTPS_MATCHING_CERTIFICATE_INDEX}" >>"${certificate_file}"

    if [[ "${FTPS_CERTIFICATE_COUNT}" -gt 1 ]]; then
        : >"${chain_file}"

        for certificate_index in $(seq 1 "${FTPS_CERTIFICATE_COUNT}"); do
            if [[ "${certificate_index}" == "${FTPS_MATCHING_CERTIFICATE_INDEX}" ]]; then
                continue
            fi

            cat "${FTPS_CERTIFICATE_PREFIX}.${certificate_index}" >>"${chain_file}"
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

    ftps_cleanup_prepared_certificate_parts
}

# Decodes and converts a base64 PKCS#12 bundle into normalized PEM.
#
# Globals:
#   FTPS_CERTIFICATE_PKCS12_PASSWORD: Read as the PKCS#12 input password.
#   FTPS_CERTIFICATE_PATH: Read as the normalized PEM destination path.
# Arguments:
#   $1: Base64-encoded PKCS#12 bundle content.
# Outputs:
#   Writes status messages to stderr/stdout via ftps_log or ftps_warn.
#   Writes the normalized PEM bundle to FTPS_CERTIFICATE_PATH.
# Returns:
#   Exits with 1 on decode or OpenSSL conversion failure; returns 0 otherwise.
ftps_write_pkcs12_bundle() {
    local encoded_bundle="$1"
    local bundle_file raw_pem_file

    ftps_log "Certificate content does not look like PEM; attempting PKCS12 conversion"

    bundle_file="$(mktemp)"
    raw_pem_file="$(mktemp)"

    if ! printf '%s' "${encoded_bundle}" | base64 -d >"${bundle_file}" 2>/dev/null; then
        rm -f "${bundle_file}" "${raw_pem_file}"
        ftps_warn "FTPS certificate value is not PEM and could not be base64-decoded as PKCS12"
        exit 1
    fi

    if ! openssl pkcs12 -in "${bundle_file}" -noenc -passin "pass:${FTPS_CERTIFICATE_PKCS12_PASSWORD}" -out "${raw_pem_file}" 2>/dev/null &&
        ! openssl pkcs12 -in "${bundle_file}" -nodes -passin "pass:${FTPS_CERTIFICATE_PKCS12_PASSWORD}" -out "${raw_pem_file}" 2>/dev/null; then
        rm -f "${bundle_file}" "${raw_pem_file}"
        ftps_warn "FTPS certificate PKCS12 bundle could not be converted to PEM"
        exit 1
    fi

    ftps_normalize_pem_bundle "${raw_pem_file}" "${FTPS_CERTIFICATE_PATH}"
    rm -f "${bundle_file}" "${raw_pem_file}"

    ftps_log "PKCS12 conversion completed and PEM bundle normalized"
}
