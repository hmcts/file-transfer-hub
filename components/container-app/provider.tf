terraform {
  required_version = ">= 1.13.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.59.0"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias = "dns"
  features {}
  subscription_id = local.dns_sub_id
}

provider "azurerm" {
  alias = "private_dns"
  features {}
  subscription_id = local.private_dns_sub_id
}