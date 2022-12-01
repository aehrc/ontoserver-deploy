module "network" {
  source              = "Azure/network/azurerm"
  resource_group_name = data.azurerm_resource_group.onto.name
  address_space       = "10.0.0.0/8"
  subnet_prefixes     = ["10.244.0.0/16","10.243.0.0/16"]
  subnet_names        = ["subnet1","appgwsubnet"]
}
