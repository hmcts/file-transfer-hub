# Troubleshooting

[← Back to root README](../README.md)

This guide is aimed at BAU engineers who need to investigate issues with the FTPS file transfer service running on Azure Container Apps.

---

## Resource naming reference

All resources follow a consistent naming convention based on the environment. Replace `<env>` with `nonprod` or `prod` as appropriate.

| Resource | Azure name |
|---|---|
| Resource group | `file-transfer-hub-<env>-rg` |
| Container App | `hub-fth` |
| Log Analytics Workspace | `file-transfer-hub-<env>-law` |
| Application Insights | `file-transfer-hub-<env>-ai` |
| Key Vault | `file-tran-hub-<env>-kv` |

---

## Accessing logs via the Azure portal

### Option 1 — Live log stream (real-time)

Use this when you need to watch what is happening right now (for example, during an active upload or while testing forwarding).

1. Open the [Azure portal](https://portal.azure.com) and navigate to the resource group `file-transfer-hub-<env>-rg`.
2. Select the **Container App** named `hub-fth`.
3. In the left-hand menu under **Monitoring**, select **Log stream**.
4. Select the **ftps-server** container from the replica dropdown.
5. Logs appear in real time. The two log sources to look for are:
   - `[ftps-entrypoint]` — startup, certificate loading, and ProFTPD initialisation
   - `[ftps-forward]` — periodic SFTP forwarding activity

> Note: the log stream requires the container to be in a running state. If the container has crashed or is in a restart loop you will not see output here — use Log Analytics instead (see below).

---

### Option 2 — Log Analytics (historical queries)

Use this for investigating past events, checking forwarding history, or correlating errors with a specific time window.

1. Open the [Azure portal](https://portal.azure.com) and navigate to the resource group `file-transfer-hub-<env>-rg`.
2. Select the **Log Analytics workspace** named `file-transfer-hub-<env>-law`.
3. Select **Logs** from the left-hand menu.
4. Use the KQL queries below in the query editor.

#### All container logs (last hour)

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "hub-fth"
| project TimeGenerated, ContainerName_s, Log_s
| order by TimeGenerated desc
```

#### Forwarding activity only

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "hub-fth"
| where Log_s has "[ftps-forward]"
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

#### Forwarding errors only

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(6h)
| where ContainerAppName_s == "hub-fth"
| where Log_s has "[ftps-forward]" and (Log_s has "error" or Log_s has "failed" or Log_s has "Fatal")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

#### Container startup logs (useful after a restart)

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(2h)
| where ContainerAppName_s == "hub-fth"
| where Log_s has "[ftps-entrypoint]"
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

#### Container restart / system events

```kql
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(6h)
| where ContainerAppName_s == "hub-fth"
| project TimeGenerated, Reason_s, Log_s
| order by TimeGenerated desc
```

---

### Option 3 — Container App console (direct container access)

Use this only if you need to inspect the container filesystem or run diagnostic commands interactively. This requires appropriate Azure RBAC permissions.

1. Navigate to the Container App `hub-fth` in the Azure portal.
2. In the left-hand menu under **Monitoring**, select **Console**.
3. Select the **ftps-server** container.
4. You will get an interactive shell. Useful commands:

```bash
# Check what files are currently in the upload directory
ls -lh /srv/ftps/ftpssvc/upload/

# Check if ProFTPD is running
pgrep -a proftpd

# Check forwarding environment variables (target count, hosts, etc.)
env | grep FTPS_FORWARD

# Manually trigger a forwarding run to test connectivity
/usr/local/bin/ftps-storage-forward.sh
```

---

## Common issues

### Files not reaching the SFTP target

1. Check the forwarding logs using the **Forwarding errors** KQL query above.
2. Look for `lftp` connection errors such as `Connection refused`, `Network unreachable`, or `Login failed`. These indicate a network or credential issue with the SFTP target.
3. Verify the SFTP target credentials in Key Vault `file-tran-hub-<env>-kv`. The relevant secrets are named according to `username_secret_name` and `password_secret_name` in `environments/<env>/<env>.tfvars`.
4. Check that the Container App environment has network line-of-sight to the SFTP target. This is a private network so routing must be in place via the hub.

### Files stuck in the upload directory

If `FTPS_FORWARD_DELETE_AFTER` is `false` (the default), files accumulate in the upload directory and are re-evaluated on every poll cycle. This is expected.

If you suspect a file should have been forwarded but was not:

1. Check forwarding logs for the time the file was expected to be transferred.
2. Confirm the forwarding loop is running — you should see `[ftps-forward] Forwarding files to <target>` in the logs approximately every 60 seconds.
3. If the forwarding loop has stopped or the container has crashed, check the **Container restart / system events** KQL query.

### Container not starting (startup failure)

Check the startup logs using the **Container startup logs** KQL query. Common causes:

| Log message | Cause |
|---|---|
| `FTPS_LOCAL_PASSWORD must be set` | The `ftps-local-password` Key Vault secret is missing or the Container App secret mapping is broken |
| `FTPS certificate not found` | The `ftps-certificate-pem` secret is missing or empty |
| `FTPS certificate content did not contain a private key PEM block` | The certificate secret exists but is malformed — verify the PEM content in Key Vault |
| `FTPS certificate PKCS12 bundle could not be converted to PEM` | A PKCS#12 certificate is being used but the password (`FTPS_CERTIFICATE_PKCS12_PASSWORD`) is wrong or the bundle is corrupt |
| `FTPS certificate content did not contain a certificate matching the supplied private key` | The certificate and private key are from different pairs — check `ftps-certificate-pem` and `ftps-certificate-key-pem` |

### Certificate issues

See [docs/certificates.md](certificates.md) for the full certificate reference. Common checks:

- Confirm the certificate secret exists in the correct Key Vault (for nonprod this is the Acmebot vault, not the service vault).
- Confirm the certificate has not expired: open Key Vault → **Certificates** and check the expiry date. If expired, follow the Let's Encrypt renewal process in [docs/certificates.md](certificates.md).
- After rotating a certificate secret in Key Vault, the Container App must be restarted to pick up the new value (secrets are injected at startup). Trigger a restart from the Container App overview page → **Restart**.

### FTPS client cannot connect

1. Confirm the client is targeting the correct hostname and port:
   - Nonprod: `dtsft.demo.apps.hmcts.net` port `990`
   - Prod: `dtsft.prod.apps.hmcts.net` port `990`
2. The passive data port range is `1024–1034`. Ensure firewall rules on the client side allow inbound TCP on these ports from the Azure public IP.
3. Check that the Container App is running: navigate to `hub-fth` → **Overview** → confirm **Running** status and replica count is 1.
4. Check ProFTPD startup logs for TLS configuration errors if the client reports a handshake failure.

---

## Useful portal shortcuts

| Task | Path in portal |
|---|---|
| View running container status | Container Apps → `hub-fth` → Overview |
| View live logs | Container Apps → `hub-fth` → Monitoring → Log stream |
| Query historical logs | Log Analytics workspaces → `file-transfer-hub-<env>-law` → Logs |
| Restart the container | Container Apps → `hub-fth` → Overview → Restart |
| Check / rotate secrets | Key Vaults → `file-tran-hub-<env>-kv` → Secrets |
| View certificate status | Key Vaults → `file-tran-hub-<env>-kv` → Certificates |
| View container environment variables | Container Apps → `hub-fth` → Containers → Environment variables |
