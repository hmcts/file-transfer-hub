data "azurerm_key_vault" "this" {
  name                = "${local.name_short}-kv"
  resource_group_name = "${local.name}-rg"
}

data "azurerm_key_vault_secret" "ftps" {
  for_each = {
    for secret in local.ftps_key_vault_secrets : "${secret.key_vault_id}|${secret.key_vault_secret_name}" => secret
  }

  key_vault_id = each.value.key_vault_id
  name         = each.value.key_vault_secret_name
}

# Email alert secrets are read separately so that they are never injected into
# the container app as runtime secrets, and so that plans succeed when the
# secrets have not yet been created by a core apply (e.g. during PR checks).
# Setting maintenance_mode = true or monitoring.enabled = false skips the
# lookup entirely, allowing plans to pass before core has been applied.
data "azurerm_key_vault_secret" "ftps_alert_emails" {
  for_each = (!var.maintenance_mode && var.monitoring.enabled) ? toset(var.monitoring.alert_email_secret_names) : toset([])

  key_vault_id = data.azurerm_key_vault.this.id
  name         = each.key
}

resource "azurerm_user_assigned_identity" "ftps_acr_pull" {
  name                = "${local.name_short}-acr-pull"
  location            = var.location
  resource_group_name = "${local.name}-rg"
  tags                = module.ctags.common_tags
}

resource "azurerm_role_assignment" "ftps_acr_pull" {
  provider             = azurerm.acr
  scope                = local.acr_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ftps_acr_pull.principal_id
}

resource "azurerm_monitor_action_group" "ftps_container_health" {
  count               = local.ftps_no_replica_alert_enabled ? 1 : 0
  name                = "${local.name_short}-alerts"
  resource_group_name = "${local.name}-rg"
  short_name          = "fthalerts"
  tags                = module.ctags.common_tags

  dynamic "email_receiver" {
    for_each = local.ftps_monitoring_email_receivers

    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }
}

locals {
  acr_registry_id               = "/subscriptions/${var.acr.subscription_id}/resourceGroups/${var.acr.resource_group_name}/providers/Microsoft.ContainerRegistry/registries/${var.acr.name}"
  ftps_certificate_key_vault_id = coalesce(var.ftps.certificate_key_vault_id, data.azurerm_key_vault.this.id)
  ftps_additional_user_secret_name = coalesce(
    try(var.ftps.additional_user_secret_name, null),
    var.env == "nonprod" ? "ho-moj-ftps-demo-username" : null
  )
  ftps_additional_password_secret_name = coalesce(
    try(var.ftps.additional_password_secret_name, null),
    var.env == "nonprod" ? "ho-moj-ftps-demo-password" : null
  )
  ftps_monitoring_email_receivers = [
    for index, secret_name in var.monitoring.alert_email_secret_names : {
      name          = "email-${index + 1}"
      email_address = data.azurerm_key_vault_secret.ftps_alert_emails[secret_name].value
    }
    if contains(keys(data.azurerm_key_vault_secret.ftps_alert_emails), secret_name)
    && trimspace(data.azurerm_key_vault_secret.ftps_alert_emails[secret_name].value) != ""
    && !endswith(lower(trimspace(data.azurerm_key_vault_secret.ftps_alert_emails[secret_name].value)), ".invalid")
  ]
  ftps_no_replica_alert_enabled = !var.maintenance_mode && var.monitoring.enabled && length(local.ftps_monitoring_email_receivers) > 0
  ftps_additional_user_secrets = local.ftps_additional_user_secret_name != null && local.ftps_additional_password_secret_name != null ? [
    {
      name                  = local.ftps_additional_user_secret_name
      key_vault_id          = data.azurerm_key_vault.this.id
      key_vault_secret_name = local.ftps_additional_user_secret_name
    },
    {
      name                  = local.ftps_additional_password_secret_name
      key_vault_id          = data.azurerm_key_vault.this.id
      key_vault_secret_name = local.ftps_additional_password_secret_name
    }
  ] : []
  ftps_legacy_forward_target = {
    name                 = "storage"
    host                 = var.ftps.storage_sftp_host
    host_secret_name     = null
    port                 = var.ftps.storage_sftp_port
    remote_dir           = var.ftps.storage_sftp_remote_dir
    username_secret_name = var.ftps.storage_sftp_user_secret_name
    password_secret_name = var.ftps.storage_sftp_password_secret_name
    key_vault_id         = null
  }
  ftps_forward_targets = [
    for index, target in(length(var.ftps.forward_targets) > 0 ? var.ftps.forward_targets : [local.ftps_legacy_forward_target]) : {
      name                 = coalesce(try(target.name, null), "target-${index + 1}")
      host                 = try(target.host, null) != null ? target.host : (index == 0 && var.env != "prod" ? "${replace(local.name_short, "-", "")}stor.blob.core.windows.net" : null)
      host_secret_name     = try(target.host_secret_name, null)
      port                 = coalesce(try(target.port, null), 22)
      remote_dir           = coalesce(try(target.remote_dir, null), ".")
      username_secret_name = coalesce(try(target.username_secret_name, null), var.ftps.storage_sftp_user_secret_name)
      password_secret_name = coalesce(try(target.password_secret_name, null), var.ftps.storage_sftp_password_secret_name)
      key_vault_id         = coalesce(try(target.key_vault_id, null), data.azurerm_key_vault.this.id)
    }
    if try(target.host, null) != null || try(target.host_secret_name, null) != null || (index == 0 && var.env != "prod")
  ]
  ftps_effective_forward_targets = var.maintenance_mode ? [] : local.ftps_forward_targets
  ftps_key_vault_secret_refs = distinct(concat(
    [
      {
        name                  = var.ftps.local_user_secret_name
        key_vault_id          = data.azurerm_key_vault.this.id
        key_vault_secret_name = var.ftps.local_user_secret_name
      },
      {
        name                  = var.ftps.local_password_secret_name
        key_vault_id          = data.azurerm_key_vault.this.id
        key_vault_secret_name = var.ftps.local_password_secret_name
      },
      {
        name                  = var.ftps.certificate_secret_name
        key_vault_id          = local.ftps_certificate_key_vault_id
        key_vault_secret_name = var.ftps.certificate_secret_name
      }
    ],
    [
      for target in local.ftps_effective_forward_targets : {
        name                  = target.host_secret_name
        key_vault_id          = target.key_vault_id
        key_vault_secret_name = target.host_secret_name
      }
      if target.host_secret_name != null
    ],
    [
      for target in local.ftps_effective_forward_targets : {
        name                  = target.username_secret_name
        key_vault_id          = target.key_vault_id
        key_vault_secret_name = target.username_secret_name
      }
    ],
    [
      for target in local.ftps_effective_forward_targets : {
        name                  = target.password_secret_name
        key_vault_id          = target.key_vault_id
        key_vault_secret_name = target.password_secret_name
      }
    ],
    local.ftps_additional_user_secrets,
    var.ftps.certificate_key_secret_name == var.ftps.certificate_secret_name ? [] : [
      {
        name                  = var.ftps.certificate_key_secret_name
        key_vault_id          = local.ftps_certificate_key_vault_id
        key_vault_secret_name = var.ftps.certificate_key_secret_name
      }
    ]
  ))
  ftps_key_vault_secrets = [
    for index, secret in local.ftps_key_vault_secret_refs : merge(secret, {
      name = "ftps-secret-${index}"
    })
  ]
  ftps_container_app_secret_name_by_key = {
    for secret in local.ftps_key_vault_secrets : "${secret.key_vault_id}|${secret.key_vault_secret_name}" => secret.name
  }
  ftps_container_app_secrets = [
    for secret in local.ftps_key_vault_secrets : {
      name  = secret.name
      value = data.azurerm_key_vault_secret.ftps["${secret.key_vault_id}|${secret.key_vault_secret_name}"].value
    }
  ]
  ftps_container_env = concat(
    [
      {
        name        = "FTPS_LOCAL_USER"
        secret_name = local.ftps_container_app_secret_name_by_key["${data.azurerm_key_vault.this.id}|${var.ftps.local_user_secret_name}"]
      },
      {
        name        = "FTPS_LOCAL_PASSWORD"
        secret_name = local.ftps_container_app_secret_name_by_key["${data.azurerm_key_vault.this.id}|${var.ftps.local_password_secret_name}"]
      },
      {
        name  = "FTPS_PUBLIC_IP"
        value = var.ftps.public_endpoint
      },
      {
        name  = "FTPS_LISTEN_PORT"
        value = tostring(var.ftps.listen_port)
      },
      {
        name  = "FTPS_PASSIVE_MIN_PORT"
        value = tostring(var.ftps.passive_port_min)
      },
      {
        name  = "FTPS_PASSIVE_MAX_PORT"
        value = tostring(var.ftps.passive_port_max)
      },
      {
        name        = "FTPS_CERTIFICATE_PEM"
        secret_name = local.ftps_container_app_secret_name_by_key["${local.ftps_certificate_key_vault_id}|${var.ftps.certificate_secret_name}"]
      },
      {
        name        = "FTPS_CERTIFICATE_KEY_PEM"
        secret_name = local.ftps_container_app_secret_name_by_key["${local.ftps_certificate_key_vault_id}|${var.ftps.certificate_key_secret_name}"]
      },
      {
        name  = "FTPS_ENABLE_STORAGE_FORWARD"
        value = tostring(!var.maintenance_mode && var.ftps.forward_enabled)
      },
      {
        name  = "FTPS_FORWARD_INTERVAL_SECONDS"
        value = tostring(var.ftps.forward_interval_seconds)
      },
      {
        name  = "FTPS_FORWARD_DELETE_AFTER"
        value = tostring(var.ftps.forward_delete_after)
      },
      {
        name  = "FTPS_FORWARD_TARGET_COUNT"
        value = tostring(length(local.ftps_effective_forward_targets))
      },
      {
        name  = "FTPS_FAILURE_TEST_RUNTIME_EXIT"
        value = tostring(var.container_app.failure_test_runtime_exit)
      },
    ],
    flatten([
      for index, target in local.ftps_effective_forward_targets : concat([
        {
          name  = "FTPS_FORWARD_TARGET_${index}_NAME"
          value = target.name
        },
        {
          name  = "FTPS_FORWARD_TARGET_${index}_PORT"
          value = tostring(target.port)
        },
        {
          name        = "FTPS_FORWARD_TARGET_${index}_USERNAME"
          secret_name = local.ftps_container_app_secret_name_by_key["${target.key_vault_id}|${target.username_secret_name}"]
        },
        {
          name        = "FTPS_FORWARD_TARGET_${index}_PASSWORD"
          secret_name = local.ftps_container_app_secret_name_by_key["${target.key_vault_id}|${target.password_secret_name}"]
        },
        {
          name  = "FTPS_FORWARD_TARGET_${index}_REMOTE_DIR"
          value = target.remote_dir
        }
        ], target.host_secret_name != null ? [
        {
          name        = "FTPS_FORWARD_TARGET_${index}_HOST"
          secret_name = local.ftps_container_app_secret_name_by_key["${target.key_vault_id}|${target.host_secret_name}"]
        }
        ] : target.host != null ? [
        {
          name  = "FTPS_FORWARD_TARGET_${index}_HOST"
          value = target.host
        }
      ] : [])
    ]),
    local.ftps_additional_user_secret_name != null && local.ftps_additional_password_secret_name != null ? [
      {
        name        = "FTPS_ADDITIONAL_USER"
        secret_name = local.ftps_container_app_secret_name_by_key["${data.azurerm_key_vault.this.id}|${local.ftps_additional_user_secret_name}"]
      },
      {
        name        = "FTPS_ADDITIONAL_PASSWORD"
        secret_name = local.ftps_container_app_secret_name_by_key["${data.azurerm_key_vault.this.id}|${local.ftps_additional_password_secret_name}"]
      }
    ] : []
  )
  ftps_passive_ports = [for port in range(var.ftps.passive_port_min, var.ftps.passive_port_max + 1) : {
    exposedPort = port
    external    = true
    targetPort  = port
  }]
  ftps_container_api_env = [
    for e in local.ftps_container_env :
    try(e.value, null) != null
    ? { name = e.name, value = e.value }
    : { name = e.name, secretRef = e.secret_name }
  ]
}

module "container_app" {
  source = "github.com/hmcts/terraform-module-azure-container-app?ref=main"

  providers = {
    azurerm             = azurerm
    azurerm.dns         = azurerm.dns
    azurerm.private_dns = azurerm.private_dns
  }

  product   = var.product
  component = "file-transfer-hub"
  env       = var.env
  project   = "hub"
  name      = "hub-fth"

  common_tags = module.ctags.common_tags

  existing_resource_group_name = "${local.name}-rg"
  location                     = var.location

  log_analytics_workspace_id = var.log_analytics_workspace_id
  subnet_id                  = var.container_apps_subnet_id

  internal_load_balancer_enabled = true

  workload_profiles = {
    "dedicated" = {
      workload_profile_type = var.container_app.workload_profile_type
    }
  }

  environment_certificates = {}

  environment_storage = {}

  container_apps = {
    ftps-server = {
      workload_profile_name = "dedicated"
      key_vault_secrets     = local.ftps_key_vault_secrets
      containers = {
        ftps-server = {
          image  = coalesce(var.container_app_image, var.container_app.image)
          cpu    = var.container_app.cpu
          memory = var.container_app.memory
          env    = local.ftps_container_env
        }
      }

      min_replicas             = 1
      max_replicas             = 1
      ingress_enabled          = true
      ingress_external_enabled = true
      ingress_target_port      = var.ftps.listen_port
      ingress_transport        = "tcp"
      registry_server          = var.acr.login_server
      registry_identity_id     = azurerm_user_assigned_identity.ftps_acr_pull.id

    }
  }
}

resource "terraform_data" "ftps_container_app_id" {
  input = module.container_app.container_app_ids["ftps-server"]
}

resource "terraform_data" "ftps_passive_ports_configuration" {
  input = {
    container_app_id         = module.container_app.container_app_ids["ftps-server"]
    image                    = coalesce(var.container_app_image, var.container_app.image)
    listen_port              = var.ftps.listen_port
    passive_ports            = local.ftps_passive_ports
    registry_server          = var.acr.login_server
    registry_identity_id     = azurerm_user_assigned_identity.ftps_acr_pull.id
    container_app_secrets    = local.ftps_container_app_secrets
    container_app_env        = local.ftps_container_env
    ingress_external_enabled = true
    ingress_target_port      = var.ftps.listen_port
    ingress_transport        = "tcp"
  }
}

resource "azapi_update_resource" "ftps_passive_ports" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = module.container_app.container_app_ids["ftps-server"]

  lifecycle {
    replace_triggered_by = [
      terraform_data.ftps_container_app_id,
      terraform_data.ftps_passive_ports_configuration,
    ]
  }

  body = {
    properties = {
      configuration = {
        activeRevisionsMode = "Single"

        registries = [
          {
            identity = azurerm_user_assigned_identity.ftps_acr_pull.id
            server   = var.acr.login_server
          }
        ]

        ingress = {
          external               = true
          exposedPort            = var.ftps.listen_port
          targetPort             = var.ftps.listen_port
          transport              = "Tcp"
          additionalPortMappings = local.ftps_passive_ports
        }

        secrets = local.ftps_container_app_secrets
      }

      template = {
        containers = [
          {
            name  = "ftps-server"
            image = coalesce(var.container_app_image, var.container_app.image)
            resources = {
              cpu    = var.container_app.cpu
              memory = var.container_app.memory
            }
            env = local.ftps_container_api_env
            probes = [
              {
                type = "Liveness"
                tcpSocket = {
                  port = 8086
                }
                initialDelaySeconds = 15
                periodSeconds       = 30
                failureThreshold    = 3
                successThreshold    = 1
                timeoutSeconds      = 5
              },
              {
                type = "Readiness"
                tcpSocket = {
                  port = 8086
                }
                initialDelaySeconds = 10
                periodSeconds       = 10
                failureThreshold    = 3
                successThreshold    = 1
                timeoutSeconds      = 5
              }
            ]
          }
        ]
      }
    }
  }
}

resource "azurerm_monitor_metric_alert" "ftps_no_replicas" {
  count               = local.ftps_no_replica_alert_enabled ? 1 : 0
  name                = "${local.name}-ftps-no-replicas"
  resource_group_name = "${local.name}-rg"
  scopes              = [module.container_app.container_app_ids["ftps-server"]]
  description         = "Alert when the FTPS container app has no active replicas. Azure Container Apps does not expose a ready replica metric, so this alert uses the Replica count metric as the closest supported signal."
  severity            = var.monitoring.no_replica_alert_severity
  enabled             = true
  auto_mitigate       = true
  frequency           = var.monitoring.no_replica_alert_frequency
  window_size         = var.monitoring.no_replica_alert_window_size
  tags                = module.ctags.common_tags

  criteria {
    metric_namespace = "Microsoft.App/containerapps"
    metric_name      = "Replicas"
    aggregation      = "Maximum"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.ftps_container_health[0].id
  }
}
