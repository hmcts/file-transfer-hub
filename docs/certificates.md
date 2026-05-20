* last_reviewed_on: 2026-04-17
* review_in: 12 months

# Certificates

[← Back to root README](../README.md)

Transport Layer Security is enabled with Let's Encrypt certificates, which renew every 90 days.

[Let's Encrypt instructions](https://hmcts.github.io/ops-runbooks/Certificates/letsencrypt.html)

## Environments

Certificates are managed per environment as follows:

| Environment | Certificate | DNS | Key Vault (Acmebot) |
| --- | --- | --- | --- |
| PROD | dtsft-prod-apps-hmcts-net | dtsft.prod.apps.hmcts.net | acmehmctshubprodintsvc |
| DEMO | dtsft-demo-apps-hmcts-net | dtsft.demo.apps.hmcts.net | acmedcdcftappsdemo |

## Renewal

Certificates are renewed automatically by the Acmebot Function App every 90 days. If a certificate is approaching expiry and has not been renewed automatically, or you need to force an immediate renewal, follow the steps below.

### Check expiry

1. Open the [Azure portal](https://portal.azure.com) and navigate to the Acmebot Key Vault for the relevant environment (see table above).
2. Select **Certificates** from the left-hand menu.
3. Find the certificate by its name (e.g. `dtsft-demo-apps-hmcts-net`) and check the expiry date in the **Expiration date** column.

### Manual renewal via Acmebot

1. In the Azure portal, search for **Function Apps** and open the Acmebot function app for the relevant environment (e.g. `acmedcdcftappsdemo`).
2. On the **Overview** page, click the **Default domain** URL. This opens the Key Vault Acmebot web interface.
3. Locate the certificate in the list and click **Renew**.
4. Acmebot will request a new certificate from Let's Encrypt and update the secret in Key Vault automatically.

> If the web interface is unavailable, you can trigger renewal by appending `/renew-certificate` to the Function App URL (e.g. `https://acmedcdcftappsdemo.azurewebsites.net/renew-certificate`) and selecting the certificate from the dropdown.

### Restart the Container App after renewal

The FTPS Container App reads the certificate secret **at startup only**. After Acmebot has written the renewed certificate to Key Vault, you must restart the Container App for it to pick up the new certificate:

1. In the Azure portal, navigate to the resource group `file-transfer-hub-<env>-rg`.
2. Open the Container App `hub-fth`.
3. On the **Overview** page, click **Restart**.
4. Monitor the startup logs to confirm the certificate loaded successfully. See [Troubleshooting](Troubleshooting.md) for the relevant KQL query.

### Verify renewal

After the restart, confirm the new certificate is in use by connecting to the FTPS endpoint with an FTPS client and inspecting the presented certificate's expiry date, or by checking the startup logs for:

```
[ftps-entrypoint] Certificate file ready at /etc/proftpd/tls/ftps.pem
[ftps-entrypoint] Prepared ProFTPD TLS material at /etc/proftpd/tls/runtime/server.pem
```