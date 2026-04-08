output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "container_apps_subnet_id" {
  value = module.network.subnet_ids["${local.vnet_key}-compute"]
}
