locals {
  enable_storage_sftp_test_target = var.env != "prod"
  storage_sftp_host               = "${module.storage.storageaccount_name}.blob.core.windows.net"
}

resource "random_password" "ftps_local_password" {
  count   = local.enable_storage_sftp_test_target ? 1 : 0
  length  = 24
  special = true
}

resource "tls_private_key" "ftps_certificate" {
  count     = local.enable_storage_sftp_test_target ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ftps_certificate" {
  count                 = local.enable_storage_sftp_test_target ? 1 : 0
  private_key_pem       = tls_private_key.ftps_certificate[0].private_key_pem
  validity_period_hours = 24 * 365
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  subject {
    common_name = var.ftps.certificate_common_name
  }
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

#resource "azurerm_key_vault_secret" "ftps_local_username" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.local_user_secret_name
#  value        = var.ftps.local_upload_user
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "text/plain"
#}
#
#resource "azurerm_key_vault_secret" "ftps_local_password" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.local_password_secret_name
#  value        = random_password.ftps_local_password[0].result
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "text/plain"
#}
#
#resource "azurerm_key_vault_secret" "ftps_storage_sftp_username" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.storage_sftp_user_secret_name
#  value        = azurerm_storage_account_local_user.ftps_forwarder[0].name
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "text/plain"
#}
#
#resource "azurerm_key_vault_secret" "ftps_storage_sftp_password" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.storage_sftp_password_secret_name
#  value        = azurerm_storage_account_local_user.ftps_forwarder[0].password
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "text/plain"
#}
#
#resource "azurerm_key_vault_secret" "ftps_certificate" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.certificate_secret_name
#  value        = tls_self_signed_cert.ftps_certificate[0].cert_pem
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "application/x-pem-file"
#}
#
#resource "azurerm_key_vault_secret" "ftps_certificate_key" {
#  count        = local.enable_storage_sftp_test_target ? 1 : 0
#  name         = var.ftps.certificate_key_secret_name
#  value        = tls_private_key.ftps_certificate[0].private_key_pem
#  key_vault_id = azurerm_key_vault.this.id
#  content_type = "application/x-pem-file"
#}
