# Copilot Instructions

## Repository Scope

- This repository contains both the FTPS application image and the Terraform that deploys it to Azure Container Apps; keep application, infrastructure, and documentation changes in sync when a runtime contract changes.
- Treat `app/` as the FTPS image source of truth, `components/core` as the shared Azure infrastructure layer, `components/container-app` as the FTPS Azure Container Apps deployment layer, `environments/` as the per-environment override source, and `docs/` as the operational reference.
- Prefer putting environment-specific behavior in `environments/*.tfvars` or existing Terraform inputs rather than hardcoding nonprod or prod branches into scripts or app code.

## Maintainability

- Write code that is maintainable, human-readable, and easy to reason about.
- Apply practical Clean Code principles where they fit the language: clear naming, small focused functions or units, straightforward control flow, and explicit error handling and intent.
- Prefer single-purpose scripts, modules, and functions. Keep responsibilities narrow and avoid combining unrelated behavior in one unit when a smaller focused abstraction would be clearer.
- Avoid dense one-liners, hidden side effects, and unnecessary indirection.

## Shell Script Standards

- Write shell scripts so they are `shfmt`-clean and `shellcheck`-clean.
- Keep shell formatting aligned with the repository `.editorconfig` configuration.
- Shell scripts in this repository use `bash` with `set -euo pipefail`. Use that standard consistently in new or modified scripts.

## Terraform Standards

- Write Terraform so it is `terraform fmt`-clean and `terraform validate`-clean.
- Keep Terraform module contracts aligned when changing inputs, outputs, or shared variables.
- Prefer input variables and environment configuration files over hardcoded environment-specific logic.
- Follow the existing Terraform module, variable, and environment configuration patterns already used in the repository.
- Do not modify tracked Terraform files solely to work around local validation or backend issues.

## Local Quality Gates

- For every change that modifies tracked repository files, run `make check` from the repository root before considering the task complete. `make check` is the default repository-wide local quality gate: it runs the repository formatting, linting, and validation targets and should cover the tracked shell and Terraform code in the repository.
- Keep the local quality gate aligned with the repository structure. If you add new scripts, Terraform modules, or move validated code to new locations, update the relevant Makefile targets in the same change so `make check` continues to cover them.
- Do not report a task as complete while any of these root quality targets are failing. If one is blocked by a missing local dependency or environment issue, report the exact blocker and stop at the narrowest successful validation.

## Documentation And Operational Notes

- After any change, verify that the relevant README files, documentation, and workflow-facing Makefiles do not contain claims that are now stale; update them in the same change if they do.
- Supported repeatable local workflows should be accessible via Make targets. Keep the repository Makefiles as the canonical entry points for local quality checks, local runtime workflows, and smoke tests.
- Keep `.github/copilot-instructions.md` aligned with the current codebase. If a change renames files, targets, variables, commands, or workflows referenced there, update the instructions in the same change so repo-specific guidance stays accurate.
- If a change affects secrets, environment behavior, certificates, DNS, deployment inputs, or operational workflows, update the relevant documentation in the same change.

## Git Safety

- Before any commit, push, rebase, cherry-pick, merge, or branch-management step, check `git status` for in-progress operations. If a cherry-pick, rebase, or merge is already active and the user did not explicitly ask to continue or abort it, stop and ask rather than guessing.
- Do not leave behind Git sequencer state, temporary backup files, or validation artifacts when finishing a task.

## FTPS Runtime And Testing

- Any change to the FTPS application in `app/` that can affect runtime behavior must pass `make test` before the task is complete. Do not treat an image-only change as done based only on `docker build`.
- Leave the local smoke environment clean when you are done. If you ran the test manually or interrupted it during debugging, bring `ftps-local-smoke` down before considering the task finished.

- Use `app/docker-compose.yaml` as the single local runtime for both manual FTPS-to-SFTP checks and the smoke test. Do not reintroduce a separate local test overlay unless there is a concrete need that cannot be handled in the base compose file.
- Keep the local compose stack disposable: the FTPS upload area and ProFTPD logs should remain on `tmpfs`, and the local SFTP sidecar should remain part of the default local stack.
- Keep the manual local flow self-contained: `make up` should be able to bootstrap any minimal ignored local configuration it needs, while `app/test-local-ftps.sh` should remain deterministic and should not depend on user-specific local `.env` state.
- `test-local-ftps.sh` sets its own `FTPS_LOCAL_PASSWORD` per test case internally; any value the caller exports is intentionally overridden. Do not debug password mismatches by changing the caller's environment.
- When adding a new runtime feature, configuration path, or entrypoint behavior, add test coverage to `test-local-ftps.sh` — either by extending an existing case with additional assertions or by adding a new named case when the feature requires distinct compose configuration. Do not rely solely on existing cases passing to validate new behavior.

## Terraform And Environment Expectations

- Treat `components/core` and `components/container-app` as separate deployment units with a defined contract: core owns shared infrastructure and outputs, while container-app consumes those outputs and wires the FTPS runtime.
- `components/container-app` owns the FTPS Key Vault secret reads, ACR pull identity, and the `azapi` patching used for registry auth and passive port exposure. Do not remove or bypass that behavior without verifying the resulting Azure Container Apps configuration.
- Prod does not auto-create the FTPS runtime secrets.
- Be careful when reasoning about Key Vault access policy drift in `components/core`: plans can differ between a local user and the Azure DevOps principal because the policy includes `data.azurerm_client_config.current.object_id`.

# Terraform Plan Validation

- Do not run `terraform plan` by default for Terraform changes. Run `terraform plan` only when the user explicitly asks for it, because these commands target real Azure infrastructure.
- When the user explicitly asks for `terraform plan`, use the repo-approved parameters below for the target environment or component instead of inventing alternatives.
- If a fully representative local `terraform plan` is not possible because required Azure credentials or target resources are unavailable, capture the closest successful local validation, state the blocker clearly, prefer pipeline validation over risky local workarounds, and do not keep mutating tracked repo files in an attempt to force the plan to run.

Use these parameters for `terraform init`:
```
-backend-config=storage_account_name=cfb084706949aac66ba5csa -backend-config=container_name=subscription-tfstate -backend-config='key=UK South/hub/file-transfer-hub/nonprod/core/terraform.tfstate' -backend-config=resource_group_name=azure-control-stg-rg -backend-config=subscription_id=04d27a32-7a07-48b3-95b8-3c8691e1a263
```

Use these parameters for `terraform plan` (adjust env if needed):
```
-var env=nonprod -var builtFrom=hmcts/file-transfer-hub -var product=hub -var-file file-transfer-hub/environments/nonprod/nonprod.tfvars -lock=false -detailed-exitcode
```

## Pipeline And Image Promotion

- The Azure pipeline builds and publishes the FTPS image from `app/` with `az acr build` to `hmctsprod.azurecr.io/file-transfer-hub/ftps-server`.
- Preserve the current image tagging convention unless there is a deliberate rollout change: build ID, branch name, and branch-plus-build-ID tags are all published.
- Keep the nonprod container-app deployment dependency model intact: it depends on both the core Terraform outputs and the app image build.
