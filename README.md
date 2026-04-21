# File Transfer Hub

This repository contains the Terraform and application code for the FTPS-based file transfer service deployed on Azure Container Apps.

## Deployment Notes

- `components/core` manages the shared Azure infrastructure, including networking, Log Analytics, Key Vault, and the temporary nonprod SFTP test target.
- `components/container-app` manages the Azure Container Apps runtime for the FTPS service.
- `app` contains the ProFTPD-based FTPS container and the `lftp` forwarding logic.

## Key Vault Secrets

The FTPS runtime expects these Key Vault secrets to exist:

- `ftps-local-username`: username used by the external FTPS client to log in
- `ftps-local-password`: password used by the external FTPS client to log in
- `ftps-storage-sftp-username`: username used by the service to forward files to the downstream SFTP target
- `ftps-storage-sftp-password`: password used by the service to forward files to the downstream SFTP target
- `ftps-certificate-pem`: FTPS server certificate in PEM format
- `ftps-certificate-key-pem`: FTPS server private key in PEM format

## Environment Behavior

- Nonprod: Terraform generates these secrets and stores them in Key Vault.
- Prod: Terraform does not generate these secrets. They must be created in Key Vault before the container-app deployment is planned or applied.

## Current Nonprod Test Approach

Until the real downstream SFTP server is available, nonprod uses the project storage account as a temporary SFTP forwarding target.
