data "azurerm_key_vault" "this" {
  name                = "${local.name_short}-kv"
  resource_group_name = "${local.name}-rg"
}

data "azurerm_container_registry" "ftps" {
  provider            = azurerm.acr
  name                = var.acr.name
  resource_group_name = var.acr.resource_group_name
}

data "azurerm_key_vault_secret" "ftps" {
  for_each = toset([
    var.ftps.local_user_secret_name,
    var.ftps.local_password_secret_name,
    var.ftps.storage_sftp_user_secret_name,
    var.ftps.storage_sftp_password_secret_name,
    var.ftps.certificate_secret_name,
    var.ftps.certificate_key_secret_name,
  ])

  name         = each.value
  key_vault_id = data.azurerm_key_vault.this.id
}

resource "azurerm_user_assigned_identity" "ftps_acr_pull" {
  name                = "${local.name_short}-acr-pull"
  location            = var.location
  resource_group_name = "${local.name}-rg"
  tags                = module.ctags.common_tags
}

resource "azurerm_role_assignment" "ftps_acr_pull" {
  provider             = azurerm.acr
  scope                = data.azurerm_container_registry.ftps.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ftps_acr_pull.principal_id
}

locals {
  ftps_storage_sftp_host = var.ftps.storage_sftp_host != null ? var.ftps.storage_sftp_host : (var.env != "prod" ? "${replace(local.name_short, "-", "")}stor.blob.core.windows.net" : "")
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
      key_vault_secrets = [
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
          name                  = var.ftps.storage_sftp_user_secret_name
          key_vault_id          = data.azurerm_key_vault.this.id
          key_vault_secret_name = var.ftps.storage_sftp_user_secret_name
        },
        {
          name                  = var.ftps.storage_sftp_password_secret_name
          key_vault_id          = data.azurerm_key_vault.this.id
          key_vault_secret_name = var.ftps.storage_sftp_password_secret_name
        },
        {
          name                  = var.ftps.certificate_secret_name
          key_vault_id          = data.azurerm_key_vault.this.id
          key_vault_secret_name = var.ftps.certificate_secret_name
        },
        {
          name                  = var.ftps.certificate_key_secret_name
          key_vault_id          = data.azurerm_key_vault.this.id
          key_vault_secret_name = var.ftps.certificate_key_secret_name
        },
      ]
      containers = {
        ftps-server = {
          image  = var.container_app.image
          cpu    = var.container_app.cpu
          memory = var.container_app.memory
          env = [
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
              name  = "FTPS_STORAGE_SFTP_HOST"
              value = local.ftps_storage_sftp_host
            },
            {
              name  = "FTPS_STORAGE_SFTP_PORT"
              value = tostring(var.ftps.storage_sftp_port)
            },
            {
              name        = "FTPS_STORAGE_SFTP_USERNAME"
              secret_name = var.ftps.storage_sftp_user_secret_name
            },
            {
              name        = "FTPS_STORAGE_SFTP_PASSWORD"
              secret_name = var.ftps.storage_sftp_password_secret_name
            },
            {
              name  = "FTPS_STORAGE_SFTP_REMOTE_DIR"
              value = var.ftps.storage_sftp_remote_dir
            },
          ]
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

resource "azapi_update_resource" "ftps_passive_ports" {
  type        = "Microsoft.App/containerApps@2024-03-01"
  resource_id = module.container_app.container_app_ids["ftps-server"]

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

        secrets = [
          for name, secret in data.azurerm_key_vault_secret.ftps : {
            name  = name
            value = secret.value
          }
        ]

        ingress = {
          external               = true
          exposedPort            = var.ftps.listen_port
          targetPort             = var.ftps.listen_port
          transport              = "tcp"
          additionalPortMappings = local.ftps_passive_ports
        }
      }
    }
  }
}
