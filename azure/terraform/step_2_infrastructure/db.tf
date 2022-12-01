resource "azurerm_postgresql_server" "onto" {
  count                            = var.setup_db ? 1 : 0
  location                         = var.azure_location
  name                             = "ontoserver-example-db"
  resource_group_name              = data.azurerm_resource_group.onto.name
  sku_name                         = var.database_sku
  version                          = "11"
  storage_mb                       = var.database_storage
  auto_grow_enabled                = true
  administrator_login              = var.database_user
  administrator_login_password     = var.database_password
  public_network_access_enabled    = true
  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_postgresql_database" "onto" {
  count               = var.setup_db ? 1 : 0
  charset             = "UTF8"
  collation           = "en-AU"
  name                = "ontoserver"
  resource_group_name = data.azurerm_resource_group.onto.name
  server_name         = azurerm_postgresql_server.onto[0].name
}

resource "azurerm_postgresql_firewall_rule" "onto" {
  name                = "azure-services"
  count               = var.setup_db ? 1 : 0
  resource_group_name = data.azurerm_resource_group.onto.name
  server_name         = azurerm_postgresql_server.onto[0].name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}
