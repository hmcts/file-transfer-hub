module "container_app" {
  source = "github.com/hmcts/terraform-module-azure-container-app?ref=main"

  providers = {
    azurerm             = azurerm
    azurerm.dns         = azurerm.dns
    azurerm.private_dns = azurerm.private_dns
  }

  product   = var.product
  component = var.component
  env       = var.env
  project   = var.project

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
      containers = {
        ftps-server = {
          image  = var.container_app.image
          cpu    = var.container_app.cpu
          memory = var.container_app.memory
        }
      }

      min_replicas = 1
      max_replicas = 1

    }
  }
}
