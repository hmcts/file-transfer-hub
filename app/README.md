# FTPS Server with SFTP Forwarding

A containerised implicit FTPS server (vsftpd) that receives files over TLS ≥ 1.2 on port 990 and optionally forwards them to a configurable remote SFTP endpoint in real time.

Built to satisfy third-party integration requirements including mandatory passive data port ranges, TLS session reuse control, encrypted ZIP pass-through, and 30-day file retention.

---

## Features

| Capability | Detail |
|---|---|
| **Implicit FTPS** | Port 990, TLS ≥ 1.2 only, strong cipher suite |
| **Passive data ports** | Restricted range 1024–1034 |
| **TLS session reuse** | Disabled (`require_ssl_reuse=NO`) for client compatibility |
| **TLS certificates** | Let's Encrypt (auto-renew) or bring your own — always a dedicated keypair, never the host SSH key |
| **Development mode** | `DEV_MODE=true` disables TLS entirely — no certificates needed for local dev |
| **SFTP forwarding** | Watches uploads in real time via `inotifywait`, forwards to a configurable SFTP endpoint with retry and dead-letter queue |
| **Atomic remote writes** | Files uploaded as `.part` then renamed, so the receiver never sees partial data |
| **Encrypted ZIP pass-through** | No AV scanning or decryption — files transit byte-for-byte |
| **30-day retention** | Cron job purges uploaded `.zip` files older than 30 days |
| **Dead-letter retry** | Failed forwards are re-attempted every 6 hours; purged after 7 days |
| **Backlog recovery** | On restart, any files that arrived while the container was down are forwarded before entering the live watch loop |

---

## Architecture

```
 3rd Party
 uploads .zip ──→ port 990 (implicit FTPS, TLS ≥ 1.2)
                       │
                       ▼
 ┌─────────────────────────────────────────────────────────┐
 │  Container                                              │
 │                                                         │
 │  vsftpd ──→ /home/ftpuser/ftp/uploads/                 │
 │                       │                                 │
 │               inotifywait (CLOSE_WRITE)                 │
 │                       │                                 │
 │               sftp-forwarder.sh                         │
 │                 ├─ SFTP put (.part → rename) ──→ remote │
 │                 ├─ success → forwarded/manifest.log     │
 │                 └─ failure → retry 3× → failed/ (DLQ)  │
 │                                                         │
 │  cron: 30-day .zip cleanup                              │
 │  cron: 6-hourly DLQ retry                               │
 │  cron: 7-day DLQ purge                                  │
 │  cron: certbot renewal (twice daily)                    │
 └─────────────────────────────────────────────────────────┘
                       │
                       ▼
 Remote SFTP Endpoint
```

---

## Quick Start

### Prerequisites

- Docker ≥ 24.0 and Docker Compose ≥ 2.20
- A DNS A record pointing your lowercase FQDN to a static public IP
- (Optional) Port 80 open for Let's Encrypt HTTP-01 challenge

### 1. Clone and configure

```bash
git clone <repo-url> && cd ftps-server

# Create your .env file from the example
cp .env.example .env
# Edit .env with your values
```

### 2. Generate the SFTP forwarding keypair

Skip this step if you don't need SFTP forwarding.

```bash
mkdir -p sftp-forward

# Generate a dedicated Ed25519 key (NOT your server's SSH key)
ssh-keygen -t ed25519 -f sftp-forward/id_ed25519 -N "" -C "ftps-forwarder"

# Fetch the remote host's public key
ssh-keyscan -p 22 -H sftp.remote-endpoint.example.com > sftp-forward/known_hosts

# Send the PUBLIC key to the remote SFTP endpoint operator
cat sftp-forward/id_ed25519.pub
```

### 3. (Option A) Let's Encrypt certificate

Ensure port 80 is reachable and set `LE_DOMAIN` and `LE_EMAIL` in your `.env`. The container handles issuance and renewal automatically.

### 3. (Option B) Bring your own certificate

```bash
mkdir -p certs
cp your-fullchain.pem certs/fullchain.pem
cp your-privkey.pem   certs/privkey.pem
```

Mount the `certs/` directory to `/etc/vsftpd/certs` in your compose override and remove `LE_DOMAIN` from `.env`.

### 3. (Option C) Development mode — no certificates

```bash
cat > .env <<'EOF'
PASV_ADDRESS=127.0.0.1
FTP_USER_PASS=localdev
DEV_MODE=true
EOF
```

This starts a plain FTP server on port 990 with no TLS. See [Development Mode](#development-mode) for details.

### 4. Build and run

```bash
docker compose up -d --build
```

### 5. Verify

```bash
# Production: check FTPS is accepting TLS 1.2 connections
openssl s_client -connect ftps.example.co.uk:990 -tls1_2

# Dev mode: check plain FTP is responding
echo QUIT | nc 127.0.0.1 990

# Tail the logs
docker compose logs -f

# Check the forwarder log
docker compose exec ftps cat /var/log/sftp-forward/forwarder.log
```

---

## Development Mode

Setting `DEV_MODE=true` disables all TLS configuration, allowing you to run the server without any certificates. This is useful for:

- Local development and integration testing
- CI/CD pipelines where certificate provisioning is impractical
- Testing the SFTP forwarding pipeline in isolation

### What changes in dev mode

| Aspect | Production (`DEV_MODE=false`) | Development (`DEV_MODE=true`) |
|---|---|---|
| **Protocol** | Implicit FTPS (encrypted) | Plain FTP (unencrypted) |
| **TLS certificates** | Required (Let's Encrypt or mounted) | Not needed |
| **Port** | 990 | 990 (same port, no TLS) |
| **Healthcheck** | `openssl s_client` TLS handshake | `nc` TCP banner check |
| **Startup banner** | Standard | ⚠ Warning banner logged to stdout |
| **SFTP forwarding** | Works normally | Works normally |
| **File retention / cron** | Works normally | Works normally |

### Quick dev start

```bash
# Minimal .env for development
cat > .env <<'EOF'
PASV_ADDRESS=127.0.0.1
FTP_USER_PASS=localdev
DEV_MODE=true
EOF

docker compose up -d --build

# Connect with any FTP client (no TLS)
ftp 127.0.0.1 990
```

> **⚠ WARNING:** Never enable `DEV_MODE` in production. All traffic — including credentials — is transmitted in plaintext. The entrypoint logs a prominent warning banner when dev mode is active.

---

## Configuration Reference

All configuration is via environment variables, set in `.env` or passed directly.

### FTPS Server

| Variable | Required | Default | Description |
|---|---|---|---|
| `PASV_ADDRESS` | **Yes** | — | Lowercase FQDN or static public IP for passive mode |
| `FTP_USER_PASS` | **Yes** | — | Password for the `ftpuser` FTP account |
| `DEV_MODE` | No | `false` | Set to `true` to disable TLS entirely (plain FTP). **Do not use in production.** |
| `LE_DOMAIN` | No | — | Domain for Let's Encrypt certificate. Omit to use a pre-mounted cert. Ignored when `DEV_MODE=true`. |
| `LE_EMAIL` | No | `admin@{LE_DOMAIN}` | Email for Let's Encrypt registration |

### SFTP Forwarding

Forwarding is **disabled** unless `SFTP_FWD_HOST` is set.

| Variable | Required | Default | Description |
|---|---|---|---|
| `SFTP_FWD_HOST` | Yes (to enable) | — | Remote SFTP hostname |
| `SFTP_FWD_PORT` | No | `22` | Remote SFTP port |
| `SFTP_FWD_USER` | Yes | — | Remote SFTP username |
| `SFTP_FWD_KEY` | Yes | — | Path to the private key inside the container |
| `SFTP_FWD_REMOTE_DIR` | Yes | — | Destination directory on the remote server |
| `SFTP_FWD_KNOWN_HOSTS` | Yes | — | Path to `known_hosts` file inside the container |
| `SFTP_FWD_RETRIES` | No | `3` | Max upload attempts before dead-lettering |
| `SFTP_FWD_RETRY_DELAY` | No | `10` | Seconds between retries |
| `SFTP_FWD_DELETE_AFTER` | No | `false` | Delete local file after successful forward |

---

## Volumes

| Mount Point | Purpose |
|---|---|
| `/home/ftpuser/ftp/uploads` | Received files (30-day retention) |
| `/etc/vsftpd/certs` | TLS certificate and private key |
| `/etc/letsencrypt` | Let's Encrypt state |
| `/var/lib/sftp-forward/ssh` | SFTP forwarding keypair and `known_hosts` (read-only) |
| `/var/lib/sftp-forward` | Forwarding state: `forwarded/`, `failed/` manifests |
| `/var/log/vsftpd` | vsftpd and cleanup logs |
| `/var/log/sftp-forward` | Forwarder and retry logs |

---

## IP Whitelisting

IP allow-listing is enforced at the **network layer**, not inside the container. Configure it on your platform:

| Platform | Mechanism |
|---|---|
| Azure ACI / AKS | Network Security Group (NSG) on subnet |
| AWS ECS / Fargate | Security Group on the ENI |
| Kubernetes (any) | `NetworkPolicy` or cloud firewall |

Restrict inbound traffic on ports **990** and **1024–1034** to the approved source IP ranges only.

---

## Maintenance

### Logs

```bash
# vsftpd transfer log
docker compose exec ftps tail -f /var/log/vsftpd/vsftpd.log

# SFTP forwarder log
docker compose exec ftps tail -f /var/log/sftp-forward/forwarder.log

# Cleanup log
docker compose exec ftps cat /var/log/vsftpd/cleanup.log
```

### Dead-Letter Queue

Failed forwards land in `/var/lib/sftp-forward/failed/`. They are retried automatically every 6 hours and purged after 7 days.

```bash
# List failed files
docker compose exec ftps ls -la /var/lib/sftp-forward/failed/

# Manually re-trigger a retry by copying back to uploads
docker compose exec ftps cp /var/lib/sftp-forward/failed/somefile.zip.1234567890 /home/ftpuser/ftp/uploads/somefile.zip
```

### Certificate Renewal

Let's Encrypt certificates are checked for renewal automatically twice daily via cron. No manual intervention is needed. To force a renewal:

```bash
docker compose exec ftps certbot renew --force-renewal
```

---

## Security Considerations

- **Separate TLS keypair** — the FTPS certificate is completely independent from any SSH host key or the SFTP forwarding key.
- **Separate SFTP forwarding keypair** — a dedicated Ed25519 key is generated solely for outbound forwarding.
- **Strict host key checking** — `StrictHostKeyChecking=yes` is enforced; the remote host must be in `known_hosts` before the first transfer.
- **No AV scanning** — encrypted ZIPs are not inspected or decrypted, as required.
- **No password auth for SFTP** — `PasswordAuthentication=no` is passed to the SFTP client; only key-based auth is used.
- **Capability-dropped container** — all Linux capabilities are dropped except the minimum required set.
- **Dev mode isolation** — `DEV_MODE=true` disables TLS entirely; a prominent warning is logged at startup to prevent accidental production use.

---

## Contributing

Contributions are welcome. Please follow the guidelines below to keep the project consistent and the review process smooth.

### Getting Started

1. **Fork** the repository and clone your fork locally.
2. Create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-change main
   ```
3. Make your changes — see the code style and commit guidelines below.
4. Build, run, and test locally (see below).
5. Push your branch and open a **pull request** against `main`.

### Building the Image

#### With Docker Compose (recommended)

Docker Compose builds the image from the `Dockerfile` in the project root, tagged automatically.

```bash
# Build the image
docker compose build

# Build with no cache (useful after Dockerfile or base image changes)
docker compose build --no-cache

# Build and start in one step
docker compose up -d --build
```

#### With Docker directly

If you prefer to build and tag the image without Compose:

```bash
# Build and tag
docker build -t ftps-server:latest .

# Build with no cache
docker build --no-cache -t ftps-server:latest .

# Verify the image was created
docker images ftps-server
```

#### What goes into the image

The `.dockerignore` file ensures that only files required at runtime are included in the build context. The following are **excluded** from the image:

- `docker-compose.yml` / `compose.yml` and overrides
- `.env` and all `.env.*` files
- `README.md`, `LICENSE`, and all other Markdown documentation
- `sftp-forward/` directory (SSH keys and `known_hosts` — mounted at runtime instead)
- TLS certificate and key files (`*.pem`, `*.key`, `*.crt`)
- `.git/`, editor configs, and OS metadata

If you add new files to the project, consider whether they belong in the image or should be added to `.dockerignore`.

### Running Locally for Development

#### Minimal setup (dev mode — no certs, no forwarding)

The fastest way to get a running instance for development:

```bash
# 1. Create a minimal .env
cat > .env <<'EOF'
PASV_ADDRESS=127.0.0.1
FTP_USER_PASS=localdev
DEV_MODE=true
EOF

# 2. Build and start
docker compose up -d --build

# 3. Connect with any FTP client (plain FTP, no TLS)
ftp 127.0.0.1 990
```

#### With a self-signed certificate (test TLS without Let's Encrypt)

```bash
# 1. Generate a self-signed certificate
mkdir -p certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/privkey.pem \
  -out certs/fullchain.pem \
  -subj "/CN=localhost"

# 2. Create .env (DEV_MODE=false, no LE_DOMAIN)
cat > .env <<'EOF'
PASV_ADDRESS=127.0.0.1
FTP_USER_PASS=localdev
DEV_MODE=false
EOF

# 3. Start the container (mount certs)
docker compose up -d --build
```

#### Full setup (FTPS + SFTP forwarding)

Follow the [Quick Start](#quick-start) steps, pointing `SFTP_FWD_HOST` at a local or test SFTP server.

#### Inspecting the running container

```bash
# Shell into the container
docker compose exec ftps bash

# Check running processes (vsftpd, crond, sftp-forwarder.sh)
docker compose exec ftps ps aux

# Check the forwarder is watching the uploads directory
docker compose exec ftps pgrep -af inotifywait

# Test a file upload end-to-end (from inside the container)
docker compose exec ftps touch /home/ftpuser/ftp/uploads/test.zip
docker compose exec ftps cat /var/log/sftp-forward/forwarder.log
```

### Testing

There is no formal test suite yet — testing is manual. Before opening a PR, verify:

1. **Image builds cleanly:**
   ```bash
   docker compose build
   ```

2. **Container starts and stays healthy:**
   ```bash
   docker compose up -d
   docker compose ps   # status should be "healthy"
   ```

3. **Dev mode works without certificates:**
   ```bash
   DEV_MODE=true docker compose up -d --build
   echo QUIT | nc 127.0.0.1 990   # should receive FTP banner
   ```

4. **FTPS accepts TLS 1.2 connections (production mode):**
   ```bash
   openssl s_client -connect 127.0.0.1:990 -tls1_2
   ```

5. **TLS 1.1 and below are rejected (production mode):**
   ```bash
   # This should fail
   openssl s_client -connect 127.0.0.1:990 -tls1_1
   ```

6. **SFTP forwarding works (if configured):**
   ```bash
   docker compose exec ftps \
     bash -c 'echo "test" > /home/ftpuser/ftp/uploads/test.zip'
   docker compose exec ftps tail -f /var/log/sftp-forward/forwarder.log
   ```

7. **Shell scripts pass linting:**
   ```bash
   shellcheck entrypoint.sh sftp-forwarder.sh
   ```

### Code Style

- **Shell scripts** — use `bash` with `set -euo pipefail`. Quote all variable expansions. Use `shellcheck` before committing:
  ```bash
  shellcheck entrypoint.sh sftp-forwarder.sh
  ```
- **Dockerfile** — one `RUN` layer per logical concern. Pin base image tags. Prefer `apk add --no-cache` on Alpine.
- **Configuration files** — comment every non-obvious directive. Group related settings under a header comment.

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add configurable upload concurrency limit
fix: handle spaces in filenames during SFTP forward
docs: add troubleshooting section to README
chore: bump Alpine base image to 3.21
```

### Pull Request Checklist

- [ ] `docker compose build` succeeds with no errors
- [ ] `shellcheck` passes on all `.sh` files
- [ ] New environment variables are documented in `README.md` and `.env.example`
- [ ] No secrets, keys, or credentials are committed
- [ ] Tested in both `DEV_MODE=true` and `DEV_MODE=false`
- [ ] Tested with both Let's Encrypt and pre-mounted certificate flows (if applicable)
- [ ] SFTP forwarding tested (if changes affect the forwarder)

### Reporting Issues

Open an issue with:
- A clear description of the problem or feature request
- Steps to reproduce (for bugs)
- Docker and OS version
- Relevant log output (redact any secrets or IPs)

---

## License

See [LICENSE](LICENSE) for details.