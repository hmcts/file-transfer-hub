locals {
  enable_storage_sftp_test_target = var.env != "prod"
  storage_sftp_host               = "${module.storage.storageaccount_name}.blob.core.windows.net"
  storage_sftp_username           = "${module.storage.storageaccount_name}.${var.ftps.storage_sftp_user}"
}

resource "random_password" "ftps_local_password" {
  count   = local.enable_storage_sftp_test_target ? 1 : 0
  length  = 24
  special = true
}

resource "azurerm_storage_account_local_user" "ftps_forwarder" {
  count                = local.enable_storage_sftp_test_target ? 1 : 0
  name                 = var.ftps.storage_sftp_user
  storage_account_id   = module.storage.storageaccount_id
  ssh_key_enabled      = false
  ssh_password_enabled = true
  home_directory       = var.ftps.storage_container_name

  permission_scope {
    service       = "blob"
    resource_name = var.ftps.storage_container_name

    permissions {
      create = true
      delete = true
      list   = true
      read   = true
      write  = true
    }
  }
}

resource "azurerm_key_vault_secret" "ftps_local_username" {
  count        = local.enable_storage_sftp_test_target ? 1 : 0
  name         = var.ftps.local_user_secret_name
  value        = var.ftps.local_upload_user
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "ftps_local_password" {
  count        = local.enable_storage_sftp_test_target ? 1 : 0
  name         = var.ftps.local_password_secret_name
  value        = random_password.ftps_local_password[0].result
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "ftps_storage_sftp_username" {
  count        = local.enable_storage_sftp_test_target ? 1 : 0
  name         = var.ftps.storage_sftp_user_secret_name
  value        = local.storage_sftp_username
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "ftps_storage_sftp_password" {
  count        = local.enable_storage_sftp_test_target ? 1 : 0
  name         = var.ftps.storage_sftp_password_secret_name
  value        = azurerm_storage_account_local_user.ftps_forwarder[0].password
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
}
