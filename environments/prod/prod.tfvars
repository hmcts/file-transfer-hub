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
