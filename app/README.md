# FTPS Container

This app uses ProFTPD for implicit FTPS and `lftp` for periodic forwarding to an SFTP target.

## Runtime

- Control port: `990`
- Passive FTPS ports: `1024-1028` by default for Azure Container Apps deployments
- FTPS user credentials: provided at runtime
- TLS certificate: provided at runtime as separate PEM secrets, a single combined PEM secret, or as a mounted combined PEM file
- Forwarding target: SFTP username/password over `lftp mirror --reverse`

The container image is built from:

- `Dockerfile`
- `entrypoint.sh`
- `proftpd-ftps.conf.template`
- `ftps-storage-forward.sh`
- `Makefile`

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

You can override the FTPS password if you want to exercise a specific value:

```bash
FTPS_LOCAL_PASSWORD='localpass123!' ./test-local-ftps.sh
```

What the test does:

- builds the FTPS image locally
- generates a throwaway self-signed certificate in a repo-local temporary directory for that run
- starts the FTPS service and local SFTP sidecar from `docker-compose.yaml`
- uploads a file over implicit FTPS on port `990`
- waits for the background forwarder to copy that file to the SFTP target
- verifies the forwarded file contents match the uploaded payload

The script cleans up the test containers, volumes, temporary certificates, and uploaded test payload automatically on exit.

## Local Run

The default local compose stack is disposable and includes both the FTPS container and a local SFTP sidecar. Uploaded files and ProFTPD logs live on `tmpfs`, so they disappear when the stack stops.

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
- `make up`: generate certs if needed and start the local FTPS-plus-SFTP stack
- `make down`: stop and remove the local FTPS-plus-SFTP stack
- `make test`: run the automated FTPS-to-SFTP smoke test with temporary certs and automatic cleanup

The compose file mounts `./certs/ftps.pem` into the container and exposes the full FTPS passive range. The smoke test does not reuse this directory; it creates a temporary cert directory under `app/`, mounts that for the test run, and removes it on exit so manual cert files are left alone.

Use `make up` when you want to inspect the local FTPS-to-SFTP forwarding stack interactively. Use `make test` when you want a repeatable pass/fail check after image changes.

For manual local runs, the default login is:

- username: `ftpssvc`
- password: `localpass123!` unless you changed `app/.env`

The automated smoke test does not read the manual password from `app/.env`; it forces its own fixed test password internally so it stays deterministic.

## Environment Variables

- `FTPS_PUBLIC_IP`: Hostname or IP returned to FTPS clients for passive connections
- `FTPS_LOCAL_USER`: FTPS login username
- `FTPS_LOCAL_PASSWORD`: FTPS login password
- `FTPS_CERTIFICATE_PATH`: Path to a combined PEM file containing private key and certificate
- `FTPS_CERTIFICATE_PEM`: Certificate PEM content or a combined PEM bundle when injecting via secrets
- `FTPS_CERTIFICATE_KEY_PEM`: Private key PEM content when injecting via secrets; optional when `FTPS_CERTIFICATE_PEM` already contains a combined PEM bundle
- `FTPS_PASSIVE_MIN_PORT`: First passive FTPS data port
- `FTPS_PASSIVE_MAX_PORT`: Last passive FTPS data port
- `FTPS_ENABLE_STORAGE_FORWARD`: Enables the background SFTP forwarding loop
- `FTPS_FORWARD_INTERVAL_SECONDS`: Poll interval for forwarding uploads
- `FTPS_FORWARD_DELETE_AFTER`: Removes local files after a successful forward when `true`
- `FTPS_STORAGE_SFTP_HOST`: Destination SFTP host
- `FTPS_STORAGE_SFTP_PORT`: Destination SFTP port
- `FTPS_STORAGE_SFTP_USERNAME`: Destination SFTP username
- `FTPS_STORAGE_SFTP_PASSWORD`: Destination SFTP password
- `FTPS_STORAGE_SFTP_REMOTE_DIR`: Destination directory on the SFTP server

## Azure Notes

- Container Apps must expose TCP ingress on `990`.
- Azure Container Apps in this target environment allow at most `5` additional TCP port mappings per app, so the default passive FTPS range is `1024-1028`.
- `FTPS_PUBLIC_IP` must be set to the address that FTPS clients can actually reach.
- Nonprod forwarding is designed to target the project storage account over Azure Storage SFTP until the real downstream SFTP endpoint exists.