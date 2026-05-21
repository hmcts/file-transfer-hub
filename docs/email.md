# LEDS Change Notification Email

[← Back to root README](../README.md)

When a certificate or credential refresh is run via the pipeline, an optional notification email can be sent to the LEDS External Service Team before the change is applied. This gives LEDS advance notice to prepare their systems before the new certificate or password takes effect.

## When the email is sent

The `NotifyLEDS` pipeline stage runs when **all** of the following are true:

- The `sendLEDSNotificationEmail` parameter is set to `true`
- The environment being notified matches either `refreshCertificateEnvironment` or `refreshSecretsEnvironment` (or both)

The stage runs **before** `RefreshCertificate` and `RefreshSecrets`. If the notification fails, neither refresh stage will run.

## Pipeline parameters

| Parameter | Default | Description |
|---|---|---|
| `sendLEDSNotificationEmail` | `false` | Enable the notification email |
| `ledsNotificationRecipientSecretName` | `ftps-leds-notification-to-email` | Key Vault secret name holding the recipient address |
| `ledsNotificationSenderSecretName` | `ftps-leds-notification-from-email` | Key Vault secret name holding the sender / reply-to address |
| `ledsNotificationMailRelaySecretName` | `ftps-leds-notification-mail-relay` | Key Vault secret name holding the SMTP relay FQDN |

## Required Key Vault secrets

These secrets must exist in the Key Vault for the environment being refreshed before the notification stage will succeed.

| Secret name | Value |
|---|---|
| `ftps-leds-notification-to-email` | LEDS External Service Team contact email address |
| `ftps-leds-notification-from-email` | Sender address shown in `From:` and `Reply-To:` on the email |
| `ftps-leds-notification-mail-relay` | SMTP relay FQDN — `hostname` or `hostname:port` (plain SMTP, no authentication) |

The same secret names apply to both `file-tran-hub-nonprod-kv` and `file-tran-hub-prod-kv`. Nonprod and prod can hold different values if you want to use a test inbox or a different relay for nonprod.

## Email templates

Two templates are stored in `docs/` and selected automatically based on which refresh switch is active:

| Template file | Used when |
|---|---|
| `docs/leds-notification-certificate-change.txt` | Only `refreshCertificateEnvironment` is set |
| `docs/leds-notification-credential-change.txt` | `refreshSecretsEnvironment` is set, or both switches are set |

Both templates are plain-text and contain the following substitution placeholders, which are filled in at pipeline runtime:

| Placeholder | Value |
|---|---|
| `{{ENVIRONMENT}}` | `nonprod` or `prod` |
| `{{PUBLIC_ENDPOINT}}` | FTPS public hostname read from the environment tfvars (e.g. `dtsft.prod.apps.hmcts.net`) |
| `{{CHANGE_TYPE}}` | Human-readable description of the change (e.g. `FTPS certificate update`) |
| `{{REQUESTED_BY}}` | Azure DevOps identity that queued the pipeline run |
| `{{BUILD_NUMBER}}` | Pipeline build number |
| `{{PIPELINE_URL}}` | Direct link to the pipeline run in Azure DevOps |

## Delivery

Email is delivered via `curl` SMTP to the configured relay. No authentication is used. The sender address appears in both the `From:` and `Reply-To:` headers so that LEDS can reply directly.

No Microsoft Graph API permissions are required on the Azure DevOps service principal.

## Troubleshooting

- **Stage skipped** — check that `sendLEDSNotificationEmail` is `true` and that the environment value in `refreshCertificateEnvironment` or `refreshSecretsEnvironment` matches the environment you expect (`nonprod` or `prod`).
- **Secret empty error** — one or more of the three KV secrets is missing or empty in the target vault. Verify with `az keyvault secret show --vault-name <vault> --name <secret>`.
- **curl SMTP error** — confirm the relay FQDN is reachable from the Azure DevOps agent and that port 25 (or whichever port is in the secret) is open. Check the pipeline log for the `curl` exit code and error message.
- **Email not received** — confirm the recipient address is correct in KV and check the relay's delivery logs for bounce or rejection details.
