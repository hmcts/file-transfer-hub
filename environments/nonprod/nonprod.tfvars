address_space = {
  vnet           = ["10.11.63.0/24"]
  general_subnet = ["10.11.63.0/26"]
  compute_subnet = ["10.11.63.64/26"]
}

hub = {
  next_hop_ip_address = "10.11.72.36"
  vnet_name           = "hmcts-hub-nonprodi"
  resource_group_name = "hmcts-hub-nonprodi"
}

ftps = {
  public_endpoint             = "dtsft.demo.apps.hmcts.net"
  forward_interval_seconds    = 900
  certificate_key_vault_id    = "/subscriptions/d025fece-ce99-4df2-b7a9-b649d3ff2060/resourceGroups/cft-platform-demo-rg/providers/Microsoft.KeyVault/vaults/acmedcdcftappsdemo"
  certificate_secret_name     = "dtsft-demo-apps-hmcts-net"
  certificate_key_secret_name = "dtsft-demo-apps-hmcts-net"
  forward_delete_after        = true
  forward_targets = [
    {
      name                 = "storage"
      host                 = null
      port                 = 22
      remote_dir           = "."
      username_secret_name = "ftps-storage-sftp-username"
      password_secret_name = "ftps-storage-sftp-password"
    },
    {
      name                 = "BAIS"
      host_secret_name     = "LEDS2BAIS-DEMO-FTPS-destination"
      port                 = 22
      remote_dir           = "."
      username_secret_name = "LEDS2BAIS-DEMO-FTPS-Username"
      password_secret_name = "LEDS2BAIS-DEMO-FTPS-Password"
    }
  ]
}
