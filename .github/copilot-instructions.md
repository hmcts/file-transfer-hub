# Copilot Instructions

## Repository Scope

- This repository contains both the FTPS application image and the Terraform that deploys it to Azure Container Apps; keep application, infrastructure, and documentation changes in sync when a runtime contract changes.
- Treat `app/` as the FTPS image source of truth, `components/core` as the shared Azure infrastructure layer, `components/container-app` as the FTPS Azure Container Apps deployment layer, `environments/` as the per-environment override source, and `docs/` as the operational reference.
- Prefer putting environment-specific behavior in `environments/*.tfvars` or existing Terraform inputs rather than hardcoding nonprod or prod branches into scripts or app code.

## FTPS Image And Local Validation

- Treat `app/` as the FTPS image source of truth.
- Any change to the FTPS image runtime, startup, TLS handling, forwarding behavior, Dockerfile, or compose wiring must pass `app/test-local-ftps.sh` before the task is complete.
- Do not treat an image-only change as done based only on `docker build`; the FTPS startup and FTPS-to-SFTP forwarding smoke test must pass.
- Leave the local smoke environment clean when you are done. If you ran the test manually or interrupted it during debugging, bring `ftps-local-smoke` down before considering the task finished.
- Use `app/docker-compose.yaml` as the single local runtime for both manual FTPS-to-SFTP checks and the smoke test. Do not reintroduce a separate local test overlay unless there is a concrete need that cannot be handled in the base compose file.
- Keep the local compose stack disposable: the FTPS upload area and ProFTPD logs should remain on `tmpfs`, and the local SFTP sidecar should remain part of the default local stack.
- Keep `app/Makefile` aligned with the documented local workflows. When changing the local run or test flow, update the relevant `make` targets in the same change.
- Keep the manual local flow self-contained: `make up` should be able to bootstrap any minimal ignored local configuration it needs, while `app/test-local-ftps.sh` should remain deterministic and should not depend on user-specific local `.env` state.
- Preserve the current implicit FTPS model on port `990`. If you change the passive FTPS port range or ingress behavior, update compose, Terraform, tests, and docs together.

## Terraform And Environment Expectations

- Treat `components/core` and `components/container-app` as separate deployment units with a defined contract: core owns shared infrastructure and outputs, while container-app consumes those outputs and wires the FTPS runtime.
- Keep shared Terraform inputs aligned across `components/inputs-required.tf`, `components/inputs-optional.tf`, and the component-specific input files when changing the infrastructure contract.
- `components/container-app` owns the FTPS Key Vault secret reads, ACR pull identity, and the `azapi` patching used for registry auth and passive port exposure. Do not remove or bypass that behavior without verifying the resulting Azure Container Apps configuration.
- Prefer the existing `acr` inputs and environment tfvars for registry configuration rather than introducing new hardcoded registry identifiers or redundant discovery logic.
- Nonprod currently uses the project storage account as a temporary SFTP forwarding target when `ftps.storage_sftp_host` is unset. Preserve that fallback unless you are intentionally changing the nonprod integration model.
- Prod does not auto-create the FTPS runtime secrets. If you change secret names, secret requirements, or certificate inputs, keep the root README and deployment expectations accurate and do not assume Terraform will backfill prod secrets.
- Be careful when reasoning about Key Vault access policy drift in `components/core`: plans can differ between a local user and the Azure DevOps principal because the policy includes `data.azurerm_client_config.current.object_id`.

# Terraform Plan Validation

- Any change to Terraform files must be validated with `terraform plan` before the task is complete.

For init use:
```
-backend-config=storage_account_name=cfb084706949aac66ba5csa -backend-config=container_name=subscription-tfstate -backend-config='key=UK South/hub/file-transfer-hub/nonprod/core/terraform.tfstate' -backend-config=resource_group_name=azure-control-stg-rg -backend-config=subscription_id=04d27a32-7a07-48b3-95b8-3c8691e1a263
```

For validating plan use (change env or component if needed):
```
-var env=nonprod -var builtFrom=hmcts/file-transfer-hub -var product=hub -var-file /azp/_work/1/s/file-transfer-hub/environments/nonprod/nonprod.tfvars -lock=false -detailed-exitcode
```

## Pipeline And Image Promotion

- The Azure pipeline builds and publishes the FTPS image from `app/` with `az acr build` to `hmctsprod.azurecr.io/file-transfer-hub/ftps-server`.
- Preserve the current image tagging convention unless there is a deliberate rollout change: build ID, branch name, and branch-plus-build-ID tags are all published.
- Keep the nonprod container-app deployment dependency model intact: it depends on both the core Terraform outputs and the app image build.

## Documentation And Operational Notes

- If an image change alters the local test workflow or runtime expectations, update `app/README.md` in the same change.
- If a change affects Key Vault secret requirements, environment behavior, or the nonprod forwarding model, update the root `README.md` in the same change.
- If a change affects certificate names, DNS names, Key Vault ownership, or certificate renewal expectations, update `docs/certificates.md` in the same change.