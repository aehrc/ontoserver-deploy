
resource "azurerm_container_registry" "acr" {
  name                = "ontoserverexampleacr"
  count               = var.acr_enabled ? 1 : 0
  resource_group_name = data.azurerm_resource_group.onto.name
  location            = data.azurerm_resource_group.onto.location
  sku                 = "Standard"
  admin_enabled       = false
}
