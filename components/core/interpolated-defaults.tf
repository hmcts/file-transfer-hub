locals {
  private_dns_sub_id  = "1baf5470-1c3e-40d3-a6f7-74bfbce4b348"
  hub_subscription_id = data.azurerm_subscription.current.subscription_id
  name                = "file-transfer-hub-${var.env}"
}

data "azurerm_subscription" "current" {}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom    = var.builtFrom
  environment  = var.env
  product      = var.product
  expiresAfter = "3000-01-01"
}
