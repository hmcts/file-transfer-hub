resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = module.ctags.tags
}
