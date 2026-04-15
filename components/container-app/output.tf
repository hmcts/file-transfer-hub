output "ftps_container_app_fqdn" {
  value = module.container_app.container_app_fqdns["ftps-server"]
}

output "ftps_container_app_id" {
  value = module.container_app.container_app_ids["ftps-server"]
}
