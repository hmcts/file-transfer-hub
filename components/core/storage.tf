module "storage" {
  source                     = "github.com/hmcts/cnp-module-storage-account?ref=4.x"
  env                        = var.env
  storage_account_name       = "${replace(local.name_short, "-", "")}stor"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  account_kind               = var.storage.account_kind
  account_replication_type   = var.storage.replication_type
  enable_hns                 = local.enable_storage_sftp_test_target
  enable_sftp                = local.enable_storage_sftp_test_target
  containers                 = local.enable_storage_sftp_test_target ? [{ name = var.ftps.storage_container_name, access_type = "private" }] : []
  common_tags                = module.ctags.common_tags
  private_endpoint_subnet_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${module.networking.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${module.networking.vnet_names[local.vnet_key]}/subnets/${module.networking.subnet_names["${local.vnet_key}-general"]}"
  sa_subnets                 = local.cft_ptl_subnet_ids
  retention_period           = var.storage.retention_period
  sa_policy = [
    {
      name = "BlobRetentionPolicy"
      filters = {
        prefix_match = [var.ftps.storage_container_name]
        blob_types   = ["blockBlob"]
      }
      actions = {
        version_delete_after_days_since_creation = var.storage.delete_after_days
      }
    }
  ]
}
