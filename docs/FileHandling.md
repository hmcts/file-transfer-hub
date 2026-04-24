# File Handling Walkthrough

[← Back to root README](../README.md)

This document describes how files are handled from the moment a client uploads them via FTPS through to delivery at the SFTP target(s).

## Overview

```
FTPS client → ProFTPD (port 990) → local upload dir → lftp (poll loop) → SFTP target(s)
```

---

## Step-by-step flow

### 1. FTPS upload

A client connects to ProFTPD on port 990 (implicit FTPS) and uploads a file. ProFTPD writes the file to the local upload directory:

- Default path: `/srv/ftps/ftpssvc/upload`
- Configurable via: `FTPS_LOCAL_UPLOAD_DIR`

This directory lives on the **ephemeral container filesystem** — it is not persisted across container restarts unless a volume or Azure File Share is mounted at that path.

### 2. Background forwarding loop

`entrypoint.sh` starts a background subshell before launching ProFTPD. This subshell runs `ftps-storage-forward.sh` in an infinite loop, sleeping between iterations:

```
while true; do
    ftps-storage-forward.sh
    sleep ${FTPS_FORWARD_INTERVAL_SECONDS}   # default: 60 seconds
done
```

Files are **not forwarded immediately on upload**. They wait until the next poll cycle fires.

Forwarding can be disabled entirely with `FTPS_ENABLE_STORAGE_FORWARD=false`.

### 3. Target discovery

`ftps-storage-forward.sh` builds its list of SFTP targets from environment variables at the start of each run.

**Numbered multi-target mode** — used when `FTPS_FORWARD_TARGET_COUNT` is set to a positive integer:

| Variable | Purpose |
|---|---|
| `FTPS_FORWARD_TARGET_COUNT` | Number of targets (0-indexed) |
| `FTPS_FORWARD_TARGET_N_HOST` | Hostname or IP of target N |
| `FTPS_FORWARD_TARGET_N_PORT` | Port of target N (default: 22) |
| `FTPS_FORWARD_TARGET_N_USERNAME` | SFTP username for target N |
| `FTPS_FORWARD_TARGET_N_PASSWORD` | SFTP password for target N |
| `FTPS_FORWARD_TARGET_N_REMOTE_DIR` | Remote directory on target N (default: `.`) |
| `FTPS_FORWARD_TARGET_N_NAME` | Human-readable label for logs (default: `target-N+1`) |

**Single-target fallback** — used when `FTPS_FORWARD_TARGET_COUNT` is unset or zero. Reads from the legacy `FTPS_STORAGE_SFTP_*` variables:

| Variable | Purpose |
|---|---|
| `FTPS_STORAGE_SFTP_HOST` | SFTP hostname |
| `FTPS_STORAGE_SFTP_PORT` | SFTP port (default: 22) |
| `FTPS_STORAGE_SFTP_USERNAME` | SFTP username |
| `FTPS_STORAGE_SFTP_PASSWORD` | SFTP password |
| `FTPS_STORAGE_SFTP_REMOTE_DIR` | Remote directory (default: `.`) |

Any target with a missing host, username, or password is skipped with a warning. If no valid targets remain the script exits without error.

### 4. File transfer

For each target, `lftp` is invoked with:

```
mirror --reverse --continue --only-newer --parallel=1 [--Remove-source-files] <local-dir> <remote-dir>
```

| Flag | Effect |
|---|---|
| `--reverse` | Push local directory contents to the remote |
| `--continue` | Resume interrupted transfers where possible |
| `--only-newer` | Skip files whose mtime is not newer than the remote copy |
| `--parallel=1` | Transfer one file at a time per target |
| `--Remove-source-files` | Delete source file after successful transfer (conditional — see below) |

The SFTP connection is made over SSH with `StrictHostKeyChecking=accept-new` (trust-on-first-use), a 20-second timeout, and up to 2 retries.

Usernames and passwords containing special characters are percent-encoded before being embedded in the SFTP URI.

All `lftp` output (including per-file transfer lines from `xfer:log` and any error messages) is captured and emitted to stderr via the `[ftps-forward]` log prefix, so it appears in the Container App log stream and Log Analytics alongside the other forwarding activity.

### 5. Source file deletion

Source file deletion is controlled by `FTPS_FORWARD_DELETE_AFTER` (default: `false`).

- **`false`** — files are never deleted from the local upload directory after forwarding.
- **`true`** — `--Remove-source-files` is added to the `lftp` call, **but only for the last target in the list**. Files are retained locally while being forwarded to all earlier targets and are removed only once the final target has received them successfully.

If the `lftp` call for the last target fails, `--Remove-source-files` is never executed and the file remains locally for retry on the next poll cycle.

---

## Deduplication and idempotency

The primary mechanism preventing a file from being sent more than once is `FTPS_FORWARD_DELETE_AFTER=true`: once `lftp` confirms the last target has received the file it passes `--Remove-source-files`, which deletes the local copy immediately. The file cannot be re-sent because it no longer exists locally.

When `FTPS_FORWARD_DELETE_AFTER=false`, the only guard is `lftp`'s `--only-newer` flag, which compares file modification timestamps against whatever the destination currently holds. This is unreliable if the receiving system moves or deletes files from its SFTP inbox after processing — as soon as the file disappears from the destination the next poll cycle will re-upload it.

| Scenario | Outcome |
|---|---|
| Normal (`delete_after=true`): transfer succeeds | Local file deleted immediately — no re-send possible |
| `delete_after=true`, last target fails | Source file kept; full retry on next cycle including all targets |
| `delete_after=false`: destination file exists with same or newer mtime | Skipped — not retransferred |
| `delete_after=false`: destination moves/deletes the file after processing | **File will be re-uploaded on next poll** |
| Container restarted with `delete_after=false` | Local files gone; no re-send risk but unforwarded uploads are **lost** |
| Forward loop fails mid-run (multiple targets) | Targets after the failure are skipped that cycle; retried from the beginning next interval |

There is no content-hash tracking, no persistent sent ledger, and no distributed lock on source files during transfer.

---

## Ephemeral storage risk

The local upload directory is on the container's ephemeral filesystem by default. If the container is restarted or replaced (e.g. by a Container Apps revision update or crash recovery) before `ftps-storage-forward.sh` has forwarded a file, that file is **permanently lost**.

To mitigate this, mount a persistent Azure File Share at `FTPS_LOCAL_UPLOAD_DIR` so that uploaded files survive container restarts.

---

## Key configuration reference

| Variable | Default | Description |
|---|---|---|
| `FTPS_ENABLE_STORAGE_FORWARD` | `true` | Enable/disable the forwarding loop |
| `FTPS_FORWARD_INTERVAL_SECONDS` | `60` | Seconds to sleep between forwarding runs |
| `FTPS_FORWARD_LOCAL_DIR` | `${FTPS_LOCAL_UPLOAD_DIR}` | Local directory scanned for files to forward |
| `FTPS_FORWARD_DELETE_AFTER` | `false` | Delete source files after successful transfer to the last target. Set to `true` in all environments to prevent duplicate uploads. |
| `FTPS_FORWARD_TARGET_COUNT` | _(unset)_ | Number of numbered SFTP targets; falls back to single-target mode if unset or 0 |
