address_space = {
  vnet           = ["10.11.63.0/24"]
  general_subnet = ["10.11.63.0/26"]
  compute_subnet = ["10.11.63.64/26"]
}

# Temporarily set to true so that the container-app plan does not attempt to
# read the alert email Key Vault secrets before core apply has created them.
# Remove this line and re-apply once core has been applied and the secrets exist.
# maintenance_mode = true

container_app = {
  # Set to true only in a short-lived test branch when you want the deployed
  # Container App revision to exit during startup and trigger the no-replica alert.
  # failure_test_runtime_exit = true
}

hub = {
  next_hop_ip_address = "10.11.72.36"
  vnet_name           = "hmcts-hub-nonprodi"
  resource_group_name = "hmcts-hub-nonprodi"
}

ftps = {
  public_endpoint = "dtsft.demo.apps.hmcts.net"
  # forward_interval_seconds  = 60  # Seconds between forwarding runs. Defaults to 60 if omitted. Set to e.g. 300 for 5 minutes.
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
