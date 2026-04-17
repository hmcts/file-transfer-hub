* last_reviewed_on: 2026-04-17
* review_in: 12 months

# Certificates

Transport Layer Security is enabled with Let's Encrypt certificates, which renew every 90 days.

[Let's Encrypt instructions](https://hmcts.github.io/ops-runbooks/Certificates/letsencrypt.html)

## Environments

Certificates are managed per environment as follows:

| Environment | Certificate | DNS | Key Vault (Acmebot) |
| --- | --- | --- | --- |
| PROD | dtsft-prod-apps-hmcts-net | dtsft.prod.apps.hmcts.net | acmehmctshubprodintsvc |
| DEMO | dtsft-demo-apps-hmcts-net | dtsft.demo.apps.hmcts.net | acmedcdcftappsdemo |