resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = module.ctags.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.name}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = module.ctags.common_tags
}

resource "azurerm_application_insights" "this" {
  name                = "${local.name}-ai"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "other"
  tags                = module.ctags.common_tags
}

resource "azurerm_key_vault" "this" {
  name                        = "${local.name}-kv"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku_name                    = "standard"
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled    = true
  enabled_for_disk_encryption = true
  tags                        = module.ctags.common_tags
}

resource "azurerm_key_vault_access_policy" "this" {
  for_each     = local.key_vault_access_policies
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.key

  certificate_permissions = each.value.certificate_permissions
  key_permissions         = each.value.key_permissions
  storage_permissions     = each.value.storage_permissions
  secret_permissions      = each.value.secret_permissions
}
