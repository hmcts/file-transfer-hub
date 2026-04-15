# FTPS Container

This app uses ProFTPD for implicit FTPS and `lftp` for periodic forwarding to an SFTP target.

## Runtime

- Control port: `990`
- Passive FTPS ports: `1024-1034`
- FTPS user credentials: provided at runtime
- TLS certificate: provided at runtime as PEM secrets or as a mounted combined PEM file
- Forwarding target: SFTP username/password over `lftp mirror --reverse`

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

## Local Run

Create a combined PEM file for local testing:

```bash
mkdir -p certs
cat server.key server.crt > certs/ftps.pem
cp .env.example .env
docker compose up --build
```

The compose file mounts `./certs/ftps.pem` into the container and exposes the full FTPS passive range.

## Environment Variables

- `FTPS_PUBLIC_IP`: Hostname or IP returned to FTPS clients for passive connections
- `FTPS_LOCAL_USER`: FTPS login username
- `FTPS_LOCAL_PASSWORD`: FTPS login password
- `FTPS_CERTIFICATE_PATH`: Path to a combined PEM file containing private key and certificate
- `FTPS_CERTIFICATE_PEM`: Certificate PEM content when injecting via secrets
- `FTPS_CERTIFICATE_KEY_PEM`: Private key PEM content when injecting via secrets
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
- Passive FTPS requires explicit TCP mappings for every port in `1024-1034`.
- `FTPS_PUBLIC_IP` must be set to the address that FTPS clients can actually reach.
- Nonprod forwarding is designed to target the project storage account over Azure Storage SFTP until the real downstream SFTP endpoint exists.