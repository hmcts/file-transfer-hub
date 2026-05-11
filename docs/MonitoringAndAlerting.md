# Monitoring and Alerting

[← Back to README](../README.md)

> **Maintenance mode:** If an environment is being actively developed or undergoing planned work, set `maintenance_mode = true` in its tfvars file and run the pipeline with `apply`. All alerts are silenced until the flag is removed. See [Maintenance mode](#maintenance-mode) for the full process.

## What is monitored

The FTPS container app runs as a single replica (min = 1, max = 1). The primary alert watches for that replica disappearing — for example if the container crashes and fails to restart, or if a failed deployment leaves the app with zero running instances.

Azure Container Apps does not expose a "ready replica" metric directly. The alert uses the closest available signal: the `Replicas` metric in the `Microsoft.App/containerapps` namespace. The alert fires when the **maximum** replica count over the evaluation window is **less than 1**.

| Setting | Default | Variable |
|---------|---------|----------|
| Metric namespace | `Microsoft.App/containerapps` | — |
| Metric name | `Replicas` | — |
| Aggregation | Maximum | — |
| Operator | LessThan | — |
| Threshold | 1 | — |
| Evaluation frequency | Every 5 minutes | `monitoring.no_replica_alert_frequency` |
| Evaluation window | Last 5 minutes | `monitoring.no_replica_alert_window_size` |
| Severity | 1 (Critical) | `monitoring.no_replica_alert_severity` |

The alert resource is named `file-transfer-hub-<env>-ftps-no-replicas` and the action group is named `file-tran-hub-<env>-alerts`.

---

## Adjusting sensitivity

If the alert fires too often (for example during a planned deployment that causes a brief replica gap), you can widen the evaluation window or increase the frequency so that short transient dips do not trigger it.

All three tuning inputs live in the `monitoring` variable block. They can be overridden per environment in the relevant `environments/<env>/<env>.tfvars` file:

```hcl
monitoring = {
  no_replica_alert_frequency   = "PT5M"   # How often Azure evaluates the metric
  no_replica_alert_window_size = "PT15M"  # How far back each evaluation looks
  no_replica_alert_severity    = 2        # 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose
}
```

**Common adjustments:**

- Reduce noise during deployments — set `no_replica_alert_window_size = "PT15M"` so the alert only fires if the replica is absent for the full 15-minute window rather than a single 5-minute snapshot.
- Downgrade urgency — change `no_replica_alert_severity = 2` (Warning) if the Sev 1 emails are causing on-call fatigue.
- Disable entirely — set `monitoring = { enabled = false }` in the tfvars for an environment where alerting is not required.
- **Maintenance mode** — set `maintenance_mode = true` at the top level of the environment tfvars to silence all alerts while the environment is under active development or planned work (see [Maintenance mode](#maintenance-mode) below).

After changing the tfvars, run the pipeline with `overrideAction = apply` against the affected environment. Only `container-app` needs to be applied; `core` does not own the alert resources.

---

## How email alerting works with Key Vault

Email addresses are never stored in source code. The flow is:

1. **`core` Terraform** creates up to three Key Vault secrets on first deployment, each seeded with the placeholder value `unset@example.invalid`:

   | Secret name | Purpose |
   |-------------|---------|
   | `ftps-alert-email-1` | First recipient |
   | `ftps-alert-email-2` | Second recipient |
   | `ftps-alert-email-3` | Third recipient (optional) |

   The `core` Terraform uses `lifecycle { ignore_changes = [value] }` on these secrets, so subsequent `core` applies never overwrite a real address you have set.

2. **An operator sets the real addresses** in Key Vault (see process below). The secrets are in the Key Vault named `file-tran-hub-<env>-kv` in resource group `file-transfer-hub-<env>-rg`.

3. **`container-app` Terraform** reads each secret value at plan time via a `data "azurerm_key_vault_secret"` data source. Any secret whose value is empty or ends in `.invalid` is filtered out. The remaining values become `email_receiver` blocks on the `azurerm_monitor_action_group` resource.

4. **Azure Monitor** calls the action group when the metric alert fires. Azure sends a formatted alert email (using the Common Alert Schema) to every receiver in the action group.

The alerting is only active when `monitoring.enabled = true` (the default) **and** at least one secret holds a real email address. If all secrets still hold the placeholder value the action group and metric alert are not created.

---

## Adding or changing email addresses

### Step 1 — Update the secret in Key Vault

Navigate to the Key Vault for the target environment (`file-tran-hub-<env>-kv`) and set the value of the relevant secret to the new email address. This can be done via the Azure Portal or the CLI:

```bash
az keyvault secret set \
  --vault-name "file-tran-hub-nonprod-kv" \
  --name "ftps-alert-email-1" \
  --value "engineer@justice.gov.uk"
```

- To add a second address, update `ftps-alert-email-2` in the same way.
- To remove a recipient, set the secret value back to `unset@example.invalid` (or any value ending in `.invalid`). The next Terraform apply will drop that receiver from the action group.
- To add a third recipient, update `ftps-alert-email-3`.

You do not need to touch any Terraform files or raise a PR to change email addresses.

### Step 2 — Apply the change to the action group

The action group is managed by `container-app` Terraform. Terraform re-reads the Key Vault secrets on every plan, so the new address is picked up automatically on the next apply.

**Option A — Trigger the pipeline manually (recommended)**

Run the pipeline from the Azure DevOps UI:

1. Go to the pipeline for this repo.
2. Click **Run pipeline**.
3. Set `overrideAction` to **apply**.
4. Tick **Refresh alert email addresses only (skip image build)**.
5. Run.

With that flag set, the image build stage is skipped, the `core` stage runs as a no-op, and the `container-app` apply updates the action group without touching the running container.

**Option B — Wait for the next merge to main**

If a code change is already in progress, the next normal pipeline apply to that environment will pick up the updated Key Vault secret as part of its regular run.

### Verifying the change

After the pipeline apply completes, confirm the action group was updated:

```bash
az monitor action-group show \
  --name "file-tran-hub-nonprod-alerts" \
  --resource-group "file-transfer-hub-nonprod-rg" \
  --query "emailReceivers[].emailAddress"
```

The output should list only the live addresses — no `unset@example.invalid` entries.

---

## Maintenance mode

Setting `maintenance_mode = true` in an environment's tfvars file disables all monitoring and alerting resources for that environment. The action group and metric alert are not created (or are destroyed if they already exist), so no emails are sent while maintenance is in progress.

**To enter maintenance mode:**

Add the flag to the relevant tfvars file — for example `environments/nonprod/nonprod.tfvars`:

```hcl
maintenance_mode = true
```

Then run the pipeline with `overrideAction = apply` against that environment. The `container-app` apply will destroy the action group and metric alert. `core` does not own these resources so it does not need to be applied.

**To leave maintenance mode:**

Remove the line (or set it to `false`) and run the pipeline with `overrideAction = apply` again. The alert and action group are recreated from the Key Vault email secrets.

`maintenance_mode` is independent of `monitoring.enabled`. If you later want alerting permanently off for an environment, use `monitoring = { enabled = false }` instead and leave `maintenance_mode = false`.
