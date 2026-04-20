output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "container_apps_subnet_id" {
  value = module.networking.subnet_ids["${local.vnet_key}-compute"]
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "storage_account_name" {
  value = module.storage.storageaccount_name
}

output "storage_sftp_host" {
  value = local.storage_sftp_host
}
