# Temporarily set to true so that the container-app plan does not attempt to
# read the alert email Key Vault secrets before core apply has created them.
# Remove this line and re-apply once core has been applied and the secrets exist.
maintenance_mode = true

address_space = {
  vnet           = ["10.11.10.0/24"]
  general_subnet = ["10.11.10.0/26"]
  compute_subnet = ["10.11.10.64/26"]
}

hub = {
  next_hop_ip_address = "10.11.8.36"
  vnet_name           = "hmcts-hub-prod-int"
  resource_group_name = "hmcts-hub-prod-int"
}

ftps = {
  public_endpoint      = "dtsft.prod.apps.hmcts.net"
  # forward_interval_seconds  = 60  # Seconds between forwarding runs. Defaults to 60 if omitted. Set to e.g. 300 for 5 minutes.
  certificate_key_vault_id    = "/subscriptions/0978315c-75fe-4ada-9d11-1eb5e0e0b214/resourceGroups/hub-prod-rg/providers/Microsoft.KeyVault/vaults/acmehmctshubprodintsvc"
  certificate_secret_name     = "dtsft-prod-apps-hmcts-net"
  certificate_key_secret_name = "dtsft-prod-apps-hmcts-net"
  forward_delete_after        = true
  manage_storage_sftp_target  = true
  forward_targets = [
    {
      name                 = "primary"
      host                 = "filetranhubprodstor.blob.core.windows.net"
      port                 = 22
      remote_dir           = "."
      username_secret_name = "ftps-storage-sftp-username"
      password_secret_name = "ftps-storage-sftp-password"
    },
    {
      name                 = "BAIS"
      host_secret_name     = "LEDS2BAIS-PROD-FTPS-destination"
      port                 = 22
      remote_dir           = "."
      username_secret_name = "LEDS2BAIS-PROD-FTPS-Username"
      password_secret_name = "LEDS2BAIS-PROD-FTPS-Password"
    }
  ]
}
