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

locals {
  acr_registry_id               = "/subscriptions/${var.acr.subscription_id}/resourceGroups/${var.acr.resource_group_name}/providers/Microsoft.ContainerRegistry/registries/${var.acr.name}"
  ftps_certificate_key_vault_id = coalesce(var.ftps.certificate_key_vault_id, data.azurerm_key_vault.this.id)
  ftps_demo_user_secrets = var.env != "nonprod" ? [] : [
    {
      name                  = "ho-moj-ftps-demo-username"
      key_vault_id          = data.azurerm_key_vault.this.id
      key_vault_secret_name = "ho-moj-ftps-demo-username"
    },
    {
      name                  = "ho-moj-ftps-demo-password"
      key_vault_id          = data.azurerm_key_vault.this.id
      key_vault_secret_name = "ho-moj-ftps-demo-password"
    }
  ]
  ftps_legacy_forward_target = {
    name                 = "storage"
    host                 = var.ftps.storage_sftp_host
    port                 = var.ftps.storage_sftp_port
    remote_dir           = var.ftps.storage_sftp_remote_dir
    username_secret_name = var.ftps.storage_sftp_user_secret_name
    password_secret_name = var.ftps.storage_sftp_password_secret_name
    key_vault_id         = null
  }
  ftps_forward_targets = [
    for index, target in (length(var.ftps.forward_targets) > 0 ? var.ftps.forward_targets : [local.ftps_legacy_forward_target]) : {
      name = coalesce(try(target.name, null), "target-${index + 1}")
      host = coalesce(
        try(target.host, null),
        index == 0 && var.env != "prod" ? "${replace(local.name_short, "-", "")}stor.blob.core.windows.net" : null
      )
      port                 = coalesce(try(target.port, null), 22)
      remote_dir           = coalesce(try(target.remote_dir, null), ".")
      username_secret_name = coalesce(try(target.username_secret_name, null), var.ftps.storage_sftp_user_secret_name)
      password_secret_name = coalesce(try(target.password_secret_name, null), var.ftps.storage_sftp_password_secret_name)
      key_vault_id         = coalesce(try(target.key_vault_id, null), data.azurerm_key_vault.this.id)
    }
    if coalesce(
      try(target.host, null),
      index == 0 && var.env != "prod" ? "${replace(local.name_short, "-", "")}stor.blob.core.windows.net" : null
    ) != null
  ]
  ftps_key_vault_secrets = distinct(concat(
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
      for target in local.ftps_forward_targets : {
        name                  = target.username_secret_name
        key_vault_id          = target.key_vault_id
        key_vault_secret_name = target.username_secret_name
      }
    ],
    [
      for target in local.ftps_forward_targets : {
        name                  = target.password_secret_name
        key_vault_id          = target.key_vault_id
        key_vault_secret_name = target.password_secret_name
      }
    ],
    local.ftps_demo_user_secrets,
    var.ftps.certificate_key_secret_name == var.ftps.certificate_secret_name ? [] : [
      {
        name                  = var.ftps.certificate_key_secret_name
        key_vault_id          = local.ftps_certificate_key_vault_id
        key_vault_secret_name = var.ftps.certificate_key_secret_name
      }
    ]
  ))
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
        secret_name = var.ftps.local_user_secret_name
      },
      {
        name        = "FTPS_LOCAL_PASSWORD"
        secret_name = var.ftps.local_password_secret_name
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
        secret_name = var.ftps.certificate_secret_name
      },
      {
        name        = "FTPS_CERTIFICATE_KEY_PEM"
        secret_name = var.ftps.certificate_key_secret_name
      },
      {
        name  = "FTPS_ENABLE_STORAGE_FORWARD"
        value = tostring(var.ftps.forward_enabled)
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
        value = tostring(length(local.ftps_forward_targets))
      },
    ],
    flatten([
      for index, target in local.ftps_forward_targets : [
        {
          name  = "FTPS_FORWARD_TARGET_${index}_NAME"
          value = target.name
        },
        {
          name  = "FTPS_FORWARD_TARGET_${index}_HOST"
          value = target.host
        },
        {
          name  = "FTPS_FORWARD_TARGET_${index}_PORT"
          value = tostring(target.port)
        },
        {
          name        = "FTPS_FORWARD_TARGET_${index}_USERNAME"
          secret_name = target.username_secret_name
        },
        {
          name        = "FTPS_FORWARD_TARGET_${index}_PASSWORD"
          secret_name = target.password_secret_name
        },
        {
          name  = "FTPS_FORWARD_TARGET_${index}_REMOTE_DIR"
          value = target.remote_dir
        }
      ]
    ]),
    var.env != "nonprod" ? [] : [
      {
        name        = "FTPS_ADDITIONAL_USER"
        secret_name = "ho-moj-ftps-demo-username"
      },
      {
        name        = "FTPS_ADDITIONAL_PASSWORD"
        secret_name = "ho-moj-ftps-demo-password"
      }
    ]
  )
  ftps_passive_ports = [for port in range(var.ftps.passive_port_min, var.ftps.passive_port_max + 1) : {
    exposedPort = port
    external    = true
    targetPort  = port
  }]
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
    }
  }
}
