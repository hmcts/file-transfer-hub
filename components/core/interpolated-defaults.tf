locals {
  private_dns_sub_id = "1baf5470-1c3e-40d3-a6f7-74bfbce4b348"
  name               = "file-transfer-hub-${var.env}"
}

module "ctags" {
  source = "github.com/hmcts/terraform-module-common-tags"

  builtFrom    = var.builtFrom
  environment  = var.env
  product      = var.product
  expiresAfter = "3000-01-01"
}
