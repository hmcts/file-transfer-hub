module "networking" {
  source = "github.com/hmcts/terraform-module-azure-virtual-networking?ref=main"

  env                          = var.env
  product                      = var.product
  common_tags                  = module.ctags.common_tags
  component                    = "file-transfer-hub"
  existing_resource_group_name = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location

  vnets = {
    "${local.vnet_key}" = {
      address_space = var.address_space.vnet
      subnets = {
        general = {
          address_prefixes = var.address_space.general_subnet
        }
        compute = {
          address_prefixes = var.address_space.compute_subnet
          delegations = {
            containerapps = {
              service_name = "Microsoft.App/environments"
              actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
            }
          }
        }
      }
    }
  }

  route_tables = {
    rt = {
      subnets = ["${local.vnet_key}-general", "${local.vnet_key}-compute"]
      routes = {
        default = {
          address_prefix         = "0.0.0.0/0"
          next_hop_type          = "VirtualAppliance"
          next_hop_in_ip_address = var.hub.next_hop_ip_address
        }
      }
    }
  }

  # network_security_groups = {
  #   nsg = {
  #     subnets = ["${local.vnet_key}-general", "${local.vnet_key}-compute"]
  #     rules = {
  #       allow_vnet_inbound = {
  #         priority                   = 4010
  #         direction                  = "Inbound"
  #         access                     = "Allow"
  #         protocol                   = "*"
  #         source_port_range          = "*"
  #         destination_port_range     = "*"
  #         source_address_prefix      = "VirtualNetwork"
  #         destination_address_prefix = "VirtualNetwork"
  #       }
  #       allow_azure_load_balancer = {
  #         priority                   = 4020
  #         direction                  = "Inbound"
  #         access                     = "Allow"
  #         protocol                   = "*"
  #         source_port_range          = "*"
  #         destination_port_range     = "*"
  #         source_address_prefix      = "AzureLoadBalancer"
  #         destination_address_prefix = "*"
  #       }
  #     }
  #   }
  # }
}

module "vnet_peer_hub" {
  source = "github.com/hmcts/terraform-module-vnet-peering?ref=master"
  peerings = {
    source = {
      name           = "${module.networking.vnet_names[local.vnet_key]}-vnet-${var.env}-to-hub"
      vnet_id        = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${module.networking.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${module.networking.vnet_names[local.vnet_key]}"
      vnet           = module.networking.vnet_names[local.vnet_key]
      resource_group = module.networking.resource_group_name
    }
    target = {
      name           = "hub-to-${module.networking.vnet_names[local.vnet_key]}-${var.env}"
      vnet           = var.hub.vnet_name
      resource_group = var.hub.resource_group_name
    }
  }

  providers = {
    azurerm.initiator = azurerm
    azurerm.target    = azurerm.hub
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = toset(local.private_dns_zone_names)
  name                  = "${local.name}-dns-link-${var.env}"
  resource_group_name   = data.azurerm_private_dns_zone.privatelink[each.key].resource_group_name
  private_dns_zone_name = data.azurerm_private_dns_zone.privatelink[each.key].name
  virtual_network_id    = module.networking.vnet_ids[local.vnet_key]
  provider              = azurerm.private_dns
}
