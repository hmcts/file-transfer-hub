module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom    = var.builtFrom
  environment  = var.env
  product      = var.product
  expiresAfter = "3000-01-01"
}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  dns_sub_id         = "ed302caf-ec27-4c64-a05e-85731c3ce90e"
  private_dns_sub_id = var.env == "sbox" ? "1497c3d7-ab6d-4bb7-8a10-b51d03189ee3" : "1baf5470-1c3e-40d3-a6f7-74bfbce4b348"
  name               = "file-transfer-hub-${var.env}"
  name_short         = "file-tran-hub-${var.env}"
}
