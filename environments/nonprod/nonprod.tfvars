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

container_app = {
  image = "hmctsprod.azurecr.io/file-transfer-hub/ftps-server:main"
}

ftps = {
  public_endpoint = "dtsft.demo.apps.hmcts.net"
}
