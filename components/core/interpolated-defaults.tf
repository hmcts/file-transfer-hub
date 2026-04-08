locals {
  private_dns_sub_id  = "1baf5470-1c3e-40d3-a6f7-74bfbce4b348"
  hub_subscription_id = data.azurerm_subscription.current.subscription_id
  name                = "file-transfer-hub-${var.env}"
  name_short          = "file-tran-hub-${var.env}"
  cft_ptl_subnet_ids = [
    "/subscriptions/1baf5470-1c3e-40d3-a6f7-74bfbce4b348/resourceGroups/cft-ptl-network-rg/providers/Microsoft.Network/virtualNetworks/cft-ptl-vnet/subnets/aks-00",
    "/subscriptions/1baf5470-1c3e-40d3-a6f7-74bfbce4b348/resourceGroups/cft-ptl-network-rg/providers/Microsoft.Network/virtualNetworks/cft-ptl-vnet/subnets/aks-01",
  ]
  key_vault_access_policies = {
    // Allow DTS Platform Operations
    "e7ea2042-4ced-45dd-8ae3-e051c6551789" = {
      certificate_permissions = []
      key_permissions = [
        "Get",
        "List",
        "Update",
        "Create",
        "Delete"
      ]
      storage_permissions = []
      secret_permissions = [
        "Get",
        "List",
        "Set",
        "Delete",
        "Purge"
      ]
    }
    // Allow Backup management
    "de5896d6-6cef-413a-833b-358762739960" = {
      certificate_permissions = []
      key_permissions = [
        "Get",
        "List",
        "Backup"
      ]
      storage_permissions = []
      secret_permissions = [
        "Get",
        "List",
        "Backup"
      ]
    }
  }

  private_dns_zone_names = [
    "privatelink.blob.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.file.core.windows.net",
  ]

  vnet_key = "vnet"
}

data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom    = var.builtFrom
  environment  = var.env
  product      = var.product
  expiresAfter = "3000-01-01"
}

data "azurerm_private_dns_zone" "privatelink" {
  for_each            = toset(local.private_dns_zone_names)
  name                = each.key
  resource_group_name = "core-infra-intsvc-rg"
  provider            = azurerm.private_dns
}
