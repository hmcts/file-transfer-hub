#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${FTPS_LIB_DIR:-${SCRIPT_DIR}/lib}"

# The wrapper is used both from the local checkout and inside the container
# image. Resolve both library locations and fail clearly if the image packaging
# contract is broken.
if [[ ! -d "${LIB_DIR}" && -d "/usr/local/lib/file-transfer-hub" ]]; then
    LIB_DIR="/usr/local/lib/file-transfer-hub"
fi

if [[ ! -r "${LIB_DIR}/ftps-storage-forward.sh" ]]; then
    printf '[ftps-forward] Storage forward helper library not found at %s\n' "${LIB_DIR}/ftps-storage-forward.sh" >&2
    exit 1
fi

# shellcheck source=lib/ftps-storage-forward.sh
source "${LIB_DIR}/ftps-storage-forward.sh"

ftps_storage_forward_main "$@"
