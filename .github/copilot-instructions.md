# Copilot Instructions

## Repository Context

### Repository Scope

- This repository contains both the FTPS application image and the Terraform that deploys it to Azure Container Apps; the FTPS service accepts uploads over FTPS and forwards them to one or more SFTP targets, so keep application, infrastructure, and documentation changes in sync when that runtime contract changes.
- At a high level, `app/` contains the FTPS application image, `components/core` owns shared infrastructure, `components/container-app` owns FTPS runtime wiring, and `environments/` provides per-environment overrides.

### FTPS Runtime And Testing

- Any change to the FTPS application in `app/` that can affect runtime behavior must pass `make test` before the task is complete. Do not treat an image-only change as done based only on `docker build`.
- Leave the local smoke environment clean when you are done. If you ran the test manually or interrupted it during debugging, bring `ftps-local-smoke` down before considering the task finished.
- Keep the manual local flow self-contained: `make up` should be able to bootstrap any minimal ignored local configuration it needs, while `app/test-local-ftps.sh` should remain deterministic and should not depend on user-specific local `.env` state.
- `test-local-ftps.sh` sets its own `FTPS_LOCAL_PASSWORD` per test case internally; any value the caller exports is intentionally overridden. Do not debug password mismatches by changing the caller's environment.

### Terraform And Environment Expectations

- Treat `components/core` and `components/container-app` as separate deployment units with a defined contract: core owns shared infrastructure and outputs, while container-app consumes those outputs and wires the FTPS runtime.
- Prod does not auto-create the FTPS runtime secrets but nonprod does.
- Be careful when reasoning about Key Vault access policy drift in `components/core`: plans can differ between a local user and the Azure DevOps principal because the policy includes `data.azurerm_client_config.current.object_id`.

### Pipeline And Image Promotion

- The Azure pipeline builds and publishes the FTPS image from `app/` with `az acr build` to `hmctsprod.azurecr.io/file-transfer-hub/ftps-server`.
- Keep the nonprod container-app deployment dependency model intact: it depends on both the core Terraform outputs and the app image build.

## Engineering Workflow

### Maintainability

- Write code that is maintainable, human-readable, and easy to reason about.
- Apply practical Clean Code principles where they fit the language: clear naming, small focused functions or units, straightforward control flow, and explicit error handling and intent.
- Prefer single-purpose scripts, modules, and functions. Keep responsibilities narrow and avoid combining unrelated behavior in one unit when a smaller focused abstraction would be clearer.
- Avoid hidden side effects, and unnecessary indirection.
- Write comments for future maintainers — human or AI — who need to understand intent, constraints, side effects, invariants, and safe usage. Do not comment obvious implementation steps.
- Follow the format and structure of existing comments in the repository; when adding new comments or docstrings, match the local style used by the surrounding code.
- Enforce critical assumptions at system or trust boundaries using types, tests, schemas, validation, or runtime checks.
- When changing code, keep comments, docstrings, examples, and related documentation in sync with the implementation. If an existing comment is stale, misleading, redundant, or contradicted by the code, update it or remove it.

### Tooling And Validation Preconditions

- Use the repository's chosen tools and workflows when they exist; do not silently substitute different tools.
- If a required local tool is missing, the available version does not satisfy the repository requirements, or a validation command cannot run because of a local environment issue, stop at the narrowest failed validation and report the exact blocker instead of working around it by changing tracked files or switching tools.

### Documentation And Operational Notes

- After any change, verify that the relevant README files, documentation, and workflow-facing Makefiles do not contain claims that are now stale; update them in the same change if they do.
- If a change introduces a new language, propose formatter, lint, and syntax-check tools for user approval, then update the relevant Make targets and instructions once approved.
- Supported repeatable local workflows should be accessible via Make targets. Keep the repository Makefiles as the canonical entry points for local quality checks, local runtime workflows and tests.
- Keep `.github/copilot-instructions.md` aligned with the current codebase. If a change renames files, targets, variables, commands, or workflows referenced there, update the instructions in the same change so repo-specific guidance stays accurate.
- If a change introduces new generated files, local runtime artifacts, or secrets that should not be committed, update the relevant `.gitignore` in the same change and keep local workflows self-contained.

## Technology And Validation Standards

### Shell Script Standards

- Shell scripts are formatted with `shfmt`, linted with `shellcheck`, and syntax-checked with `bash -n`.
- For shell scripts use `bash` with `set -euo pipefail`.

### Shell Script Standards (Goes into shell script writing skill)

- For shell scripts, add concise function-level contract comments for non-trivial functions that:
  - read environment variables
  - mutate globals or shared arrays
  - depend on external commands
  - construct command strings or heredocs for another tool
  - rely on specific return-code semantics
  - enforce ordering, cleanup, security, or safety invariants
- Comments should describe the contract, side effects, and failure behaviour, not repeat the implementation.

### Terraform Standards

- Terraform code is checked with `terraform fmt` and `terraform validate`.
- Prefer input variables and environment configuration files over hardcoded environment-specific logic.
- Follow the existing Terraform module, variable, and environment configuration patterns already used in the repository.

### Terraform Standards (goes into Terraform writing skill)

- For Terraform, document non-obvious resource relationships, lifecycle settings, provider constraints, and cross-module contracts.
- Prefer variable validation blocks for critical input assumptions.
- Avoid comments that restate resource names or obvious arguments.

### Makefile Standards

- Makefiles are linted with `checkmake` using the repo-level `checkmake.ini`.
- Keep the root Makefile focused on repo-level orchestration. For new non-Terraform apps or components, add workflow targets in a local Makefile and delegate from the root only when needed.

## Other Standards

- Markdown documentation is formatted and linted with `rumdl`, with the line-length rule disabled in the repo-level `.rumdl.toml`.

### Local Quality Gates

- Use the repository's existing conventions and Make targets as the source of truth for formatting, linting, validation, and tests.
- For documentation-only changes, run `make fmt-docs` and `make check-docs` from the repository root before considering the task complete.
- For changes that modify tracked non-documentation files covered by the repository quality gates, run `make verify` from the repository root before considering the task complete. This includes mixed code-and-documentation changes.
- Keep the local quality gates aligned with the repository structure. If you add new validated code, infrastructure, workflow, or documentation surfaces, update the relevant Makefile targets in the same change so the appropriate check targets continue to cover them.
- Do not report a task as complete while the relevant required quality targets are failing. If a required check is blocked by a missing local dependency or environment issue, report the exact blocker and stop at the narrowest successful validation.

### Full Verification

- When the repository exposes a root `make verify` target, treat it as the full local verification flow that combines formatting, the required quality gates, and test entry points.
- When the repository exposes a root `make ci_verify` target, treat it as the CI-safe non-mutating verification flow that should run in pipelines.

### Terraform Plan Validation

- Do not run `terraform plan` by default for Terraform changes. Run `terraform plan` only when the user explicitly asks for it, because these commands target real Azure infrastructure.
- When the user explicitly asks for `terraform plan`, use the repo-approved parameters below for the target environment or component instead of inventing alternatives.
- If a fully representative local `terraform plan` is not possible because required Azure credentials or target resources are unavailable, capture the closest successful local validation, state the blocker clearly, prefer pipeline validation over risky local workarounds, and do not keep mutating tracked repo files in an attempt to force the plan to run.

Use these parameters for `terraform init`:

```text
-backend-config=storage_account_name=cfb084706949aac66ba5csa -backend-config=container_name=subscription-tfstate -backend-config='key=UK South/hub/file-transfer-hub/nonprod/core/terraform.tfstate' -backend-config=resource_group_name=azure-control-stg-rg -backend-config=subscription_id=04d27a32-7a07-48b3-95b8-3c8691e1a263
```

Use these parameters for `terraform plan` (adjust env if needed):

```text
-var env=nonprod -var builtFrom=hmcts/file-transfer-hub -var product=hub -var-file file-transfer-hub/environments/nonprod/nonprod.tfvars -lock=false -detailed-exitcode
```
