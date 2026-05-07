#!/usr/bin/env bash

# Creates and exports a per-test temporary directory.
#
# Globals:
#   TEST_TMPDIR: Set to the generated temporary directory path.
# Returns:
#   0 when mktemp succeeds; non-zero otherwise.
common_setup() {
	TEST_TMPDIR="$(mktemp -d)"
	export TEST_TMPDIR
}

# Removes the per-test temporary directory created by common_setup.
#
# Globals:
#   TEST_TMPDIR: Read to decide whether cleanup is safe.
# Returns:
#   0 when no cleanup is needed or removal succeeds; non-zero if rm fails.
common_teardown() {
	if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
		rm -rf "${TEST_TMPDIR}"
	fi
}

# Writes a short-lived self-signed key/certificate pair.
#
# Globals:
#   TEST_TMPDIR: Read as the output directory.
# Arguments:
#   $1: Certificate name used as the filename prefix and certificate CN.
# Outputs:
#   Writes ${TEST_TMPDIR}/${name}.key and ${TEST_TMPDIR}/${name}.crt.
# Returns:
#   0 when OpenSSL writes both files; non-zero otherwise.
create_self_signed_certificate() {
	local name="$1"

	openssl req -x509 -newkey rsa:2048 \
		-keyout "${TEST_TMPDIR}/${name}.key" \
		-out "${TEST_TMPDIR}/${name}.crt" \
		-sha256 -days 1 -nodes \
		-subj "/CN=${name}.local" >/dev/null 2>&1
}

# Creates an intentionally unordered combined PEM fixture.
#
# Globals:
#   TEST_TMPDIR: Read as the fixture directory.
# Outputs:
#   Writes generated leaf/other certificate files and ${TEST_TMPDIR}/combined.pem.
# Returns:
#   0 when fixture files are generated and combined; non-zero otherwise.
create_combined_pem_fixture() {
	create_self_signed_certificate "leaf"
	create_self_signed_certificate "other"

	cat \
		"${TEST_TMPDIR}/leaf.key" \
		"${TEST_TMPDIR}/other.crt" \
		"${TEST_TMPDIR}/leaf.crt" >"${TEST_TMPDIR}/combined.pem"
}

# Extracts a 1-based certificate block from a PEM file.
#
# Arguments:
#   $1: Source PEM file.
#   $2: 1-based certificate index to extract.
#   $3: Destination file for the extracted certificate block.
# Outputs:
#   Writes the requested certificate block to the destination file.
# Returns:
#   0 even when the requested index is missing, producing an empty file.
extract_nth_certificate() {
	local source_file="$1"
	local requested_index="$2"
	local destination_file="$3"

	awk -v requested_index="${requested_index}" '
        /-----BEGIN CERTIFICATE-----/ {
            certificate_index++
            capture=(certificate_index == requested_index)
        }
        capture {
            print
        }
        /-----END CERTIFICATE-----/ && capture {
            exit
        }
    ' "${source_file}" >"${destination_file}"
}

# Prints a certificate SHA-256 fingerprint.
#
# Arguments:
#   $1: Certificate file to inspect.
# Outputs:
#   Writes the OpenSSL SHA-256 fingerprint value to stdout.
# Returns:
#   0 when OpenSSL can read the certificate; non-zero otherwise.
certificate_fingerprint() {
	local certificate_file="$1"

	openssl x509 -in "${certificate_file}" -noout -fingerprint -sha256 | cut -d '=' -f 2
}

# Creates an executable stub command and makes it first on PATH.
#
# Globals:
#   TEST_TMPDIR: Read as the stub binary directory root.
#   PATH: Prepended with ${TEST_TMPDIR}/bin.
# Arguments:
#   $1: Stub command name.
#   $2: Bash body written after the shebang.
# Outputs:
#   Writes ${TEST_TMPDIR}/bin/${name}.
# Returns:
#   0 when the stub is written and made executable; non-zero otherwise.
create_stub_command() {
	local name="$1"
	local body="$2"

	mkdir -p "${TEST_TMPDIR}/bin"
	printf '%s\n' '#!/usr/bin/env bash' >"${TEST_TMPDIR}/bin/${name}"
	printf '%s\n' "${body}" >>"${TEST_TMPDIR}/bin/${name}"
	chmod 0755 "${TEST_TMPDIR}/bin/${name}"
	export PATH="${TEST_TMPDIR}/bin:${PATH}"
}
