terraform {
  required_version = ">= 1.13.2"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.59.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "2.4.0"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
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

provider "azurerm" {
  alias = "acr"
  features {}
  subscription_id = var.acr.subscription_id
}

provider "azapi" {}
