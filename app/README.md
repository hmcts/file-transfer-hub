# FTPS Container

[← Back to root README](../README.md)

This app uses ProFTPD for implicit FTPS and `lftp` for periodic forwarding to one or more SFTP targets.

## Runtime

- Control port: `990`
- Passive FTPS ports: `1024-1034` by default for Azure Container Apps deployments
- FTPS user credentials: provided at runtime
- TLS certificate: provided at runtime as separate PEM secrets, a single combined PEM secret, a base64-encoded PKCS#12 bundle, or as a mounted combined PEM file
- Forwarding targets: SFTP username/password over `lftp mirror --reverse`, with duplicate fan-out copies when multiple targets are configured
- Forwarding host trust: the SFTP client currently uses `StrictHostKeyChecking=accept-new` so the first seen host key is accepted and then pinned for the life of that container filesystem

The container image is built from:

- `Dockerfile`
- `entrypoint.sh`
- `proftpd-ftps.conf.template`
- `ftps-storage-forward.sh`

## Local Build

Build the container image locally:

```bash
docker build -t file-transfer-hub-ftps:local .
```

## Local Smoke Test

Run the disposable local smoke test from the `app` directory:

```bash
make test
```

Run a specific smoke case through the same make target:

```bash
make test TEST_ARGS="pem"
make test TEST_ARGS="pkcs12-chain"
```

You can override the FTPS password if you want to exercise a specific value:

```bash
FTPS_LOCAL_PASSWORD='localpass123!' make test
```

What the test does:

- builds the FTPS image locally
- runs the FTPS startup and forwarder smoke flow against two certificate inputs for the same image
- covers a mounted combined PEM file and a base64 PKCS#12 bundle with key plus server certificate plus signing certificate
- uploads a file over implicit FTPS on port `990` for each case
- waits for the background forwarder to copy that file to both local SFTP targets
- verifies the forwarded file contents match the uploaded payload on both targets for each case
- asserts that the PKCS#12 case logs conversion and produces the expected PEM block markers inside the container

The default PKCS#12 case is synthetic. If you want to reproduce a specific real-world bundle instead, point the chain case at your own local `.p12` file:

```bash
FTPS_TEST_PKCS12_CHAIN_BUNDLE_FILE="path/tp/real-world-cert-bundle.p12" make test TEST_ARGS="pkcs12-chain"
```

That override bypasses the generated synthetic chain bundle and copies the provided file into the test case.

The script cleans up the test containers, volumes, temporary certificates, and uploaded test payload automatically on exit.

If you need to inspect the smoke environment after the script finishes, preserve it explicitly for that run:

```bash
FTPS_TEST_PRESERVE_STACK=true make test
```

When preserved, the script prints the compose project name and temporary directory instead of tearing them down. You can then inspect the sidecar and FTPS logs, for example:

```bash
docker compose -p ftps-local-smoke-pem -f docker-compose.yaml exec -T sftp-target ls -la /home/sftpuser/dropoff
docker compose -p ftps-local-smoke-pkcs12-chain -f docker-compose.yaml logs ftps
```

Clean up afterward with:

```bash
docker compose -p ftps-local-smoke-pem -f docker-compose.yaml down -v --remove-orphans
docker compose -p ftps-local-smoke-pkcs12-chain -f docker-compose.yaml down -v --remove-orphans
```

## Local Run

The default local compose stack is disposable and includes the FTPS container plus two local SFTP sidecars so duplicate forwarding can be exercised. Uploaded files and ProFTPD logs live on `tmpfs`, so they disappear when the stack stops.

Generate local certs once and start the stack:

```bash
make up
```

That target depends on `make certs`, which creates `certs/server.key`, `certs/server.crt`, and `certs/ftps.pem` only if they are not already present.

If `app/.env` does not exist, `make up` also copies `app/.env.local.example` to `app/.env`. The tracked local template currently contains:

```bash
FTPS_LOCAL_PASSWORD=localpass123!
```

That gives the manual local stack a known FTPS login without requiring any extra setup. You can edit `app/.env` afterward if you want a different password for manual runs.

Useful local targets:

- `make certs`: generate an idempotent self-signed cert set for local manual runs
- `make ensure-env`: create `app/.env` from `app/.env.local.example` when it is missing
- `make up`: generate certs if needed and start the local FTPS-plus-SFTP-targets stack
- `make connect`: open an interactive shell in the running local FTPS container created by `make up`
- `make down`: stop and remove the local FTPS-plus-SFTP-targets stack
- `make test`: run the automated FTPS-to-SFTP smoke test with temporary certs and automatic cleanup

The compose file mounts `./certs/ftps.pem` into the container and exposes the full FTPS passive range. The smoke test does not reuse this directory; it creates a temporary cert directory under `app/`, mounts that for the test run, and removes it on exit so manual cert files are left alone.

Use `make up` when you want to inspect the local FTPS-to-SFTP forwarding stack interactively. Use `make connect` to open a shell in the running FTPS container from that stack. Use `make test` when you want a repeatable pass/fail check after image changes, including fan-out copies to both local targets.

If no local FTPS container is running, `make connect` exits with:

```text
No container running, please run make up first.
```

For manual local runs, the default login is:

- username: `ftpssvc`
- password: `localpass123!` unless you changed `app/.env`

The automated smoke test does not read the manual password from `app/.env`; it forces its own fixed test password internally so it stays deterministic.

## Environment Variables

- `FTPS_LISTEN_PORT`: FTPS control port the server listens on
- `FTPS_PUBLIC_IP`: Hostname or IP returned to FTPS clients for passive connections
- `FTPS_LOCAL_USER`: FTPS login username
- `FTPS_LOCAL_PASSWORD`: FTPS login password
- `FTPS_ADDITIONAL_USER`: Optional second FTPS login username
- `FTPS_ADDITIONAL_PASSWORD`: Optional second FTPS login password
- `FTPS_CERTIFICATE_PATH`: Path to the source combined PEM bundle containing the private key, the leaf certificate, and any optional chain certificates
- `FTPS_CERTIFICATE_PEM`: Certificate PEM content or a combined PEM bundle when injecting via secrets
- `FTPS_CERTIFICATE_KEY_PEM`: Private key PEM content when injecting via secrets; optional when `FTPS_CERTIFICATE_PEM` already contains a combined PEM bundle
- `FTPS_CERTIFICATE_PKCS12_PASSWORD`: Optional password for PKCS#12 bundles passed via `FTPS_CERTIFICATE_PEM`; defaults to empty

When `FTPS_CERTIFICATE_PEM` does not contain PEM markers, the container treats it as a base64-encoded PKCS#12 bundle, converts it to PEM at startup, and rebuilds the bundle so the private key is paired with the matching leaf certificate before any chain certificates.

When PEM content is injected directly, startup applies the same normalization and now fails early if the secret content does not include both a private key and a certificate that matches that key.

After startup has a normalized PEM bundle, it derives a dedicated ProFTPD server certificate file and, when additional certificates are present, a certificate-chain file so FTPS clients receive the intermediate chain.
- `FTPS_PASSIVE_MIN_PORT`: First passive FTPS data port
- `FTPS_PASSIVE_MAX_PORT`: Last passive FTPS data port
- `FTPS_ENABLE_STORAGE_FORWARD`: Enables the background SFTP forwarding loop
- `FTPS_FORWARD_INTERVAL_SECONDS`: Seconds to sleep between forwarding runs (image default: `60`). In deployed environments this is driven by the Terraform input `ftps.forward_interval_seconds`; set it in `environments/<env>/<env>.tfvars` to change the interval without rebuilding the image.
- `FTPS_FORWARD_DELETE_AFTER`: Removes local files after a successful forward when `true`
- `FTPS_FORWARD_TARGET_COUNT`: Number of indexed forwarding targets to process
- `FTPS_FORWARD_TARGET_<n>_NAME`: Optional label for target `n`
- `FTPS_FORWARD_TARGET_<n>_HOST`: Destination SFTP host for target `n`
- `FTPS_FORWARD_TARGET_<n>_PORT`: Destination SFTP port for target `n`
- `FTPS_FORWARD_TARGET_<n>_USERNAME`: Destination SFTP username for target `n`
- `FTPS_FORWARD_TARGET_<n>_PASSWORD`: Destination SFTP password for target `n`
- `FTPS_FORWARD_TARGET_<n>_REMOTE_DIR`: Destination directory on the SFTP server for target `n`

If `FTPS_FORWARD_TARGET_COUNT` is unset, the container falls back to the legacy single-target variables `FTPS_STORAGE_SFTP_HOST`, `FTPS_STORAGE_SFTP_PORT`, `FTPS_STORAGE_SFTP_USERNAME`, `FTPS_STORAGE_SFTP_PASSWORD`, and `FTPS_STORAGE_SFTP_REMOTE_DIR`.

Current temporary SFTP trust behavior:

- the forwarding client uses `ssh -o StrictHostKeyChecking=accept-new` underneath `lftp`
- this allows first-connect host key bootstrap for each configured SFTP target
- later connections still verify the previously accepted key while the container filesystem persists
- this is a temporary runtime compromise; explicit host-key pinning is the intended long-term behavior

## Azure Notes

- Container Apps must expose TCP ingress on `990`.
- Azure Container Apps in this target environment allow at most `5` additional TCP port mappings per app, but the current default passive FTPS range is `1024-1034` (11 ports).
- `FTPS_PUBLIC_IP` must be set to the address that FTPS clients can actually reach.
- Nonprod forwarding is designed to target the project storage account over Azure Storage SFTP as the first forward target until the real downstream SFTP endpoints exist.