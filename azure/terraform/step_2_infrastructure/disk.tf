resource "azurerm_managed_disk" "onto" {
  name                 = "ontoserver-example"
  resource_group_name  = module.aks.node_resource_group
  location             = var.azure_location
  storage_account_type = var.disk_type
  create_option        = "Empty"
  disk_size_gb         = var.onto_disk_capacity
  lifecycle {
    ignore_changes = [tags]
  }
}
