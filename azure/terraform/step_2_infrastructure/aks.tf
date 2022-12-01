data "azuread_group" "aks_cluster_admins" {
 display_name = var.aks_cluster_admins_aad
}

data "azurerm_resource_group" "aks" {
  name     = module.aks.node_resource_group
}

module "aks" {
  version                               = "6.1.0"
  source                                = "Azure/aks/azurerm"
  resource_group_name                   = data.azurerm_resource_group.onto.name
  prefix                                = "ontoexample"
  cluster_name                          = var.aks_cluster_name
  network_plugin                        = "azure"
  vnet_subnet_id                        = module.network.vnet_subnets[0]
  sku_tier                              = "Paid" # defaults to Free
  role_based_access_control_enabled     = true
  cluster_log_analytics_workspace_name  = var.log_analytics_workspace_name
  rbac_aad_admin_group_object_ids       = [data.azuread_group.aks_cluster_admins.id]
  rbac_aad_managed                      = true
  private_cluster_enabled               = false
  http_application_routing_enabled       = false
  azure_policy_enabled                   = true
  enable_auto_scaling                   = false
  enable_host_encryption                = false
  agents_min_count                      = 1
  agents_max_count                      = 3
  agents_size                           = var.agent_size_default
  agents_max_pods                       = 100
  agents_pool_name                      = "prodk8spool"
  agents_availability_zones             = ["1", "2", "3"]
  os_disk_size_gb                       = 128
  agents_type                           = "VirtualMachineScaleSets"
  microsoft_defender_enabled            = true


  agents_labels = {
    nodepool = "default_nodepool"
  }

  agents_tags = {
    Agent = "ontonodepoolagent",
    Environment = "Production"

  }

  ingress_application_gateway_enabled = var.enable_app_gateway_ingress
  ingress_application_gateway_name = var.enable_app_gateway_ingress ? "ontoexample-k8s-agic-agw" : null
  ingress_application_gateway_subnet_id = var.enable_app_gateway_ingress ? module.network.vnet_subnets[1] : null


  network_policy                 = "azure"
  net_profile_dns_service_ip     = "10.0.0.10"
  net_profile_docker_bridge_cidr = "170.17.0.1/16"
  net_profile_service_cidr       = "10.0.0.0/16"

  depends_on = [module.network]
}

resource "azurerm_kubernetes_cluster_node_pool" "large_pool" {
  name                  = "prodk8slarge"
  kubernetes_cluster_id = module.aks.aks_id
  vm_size               = var.agent_size_large
  enable_auto_scaling   = true   # Spin up a new instance for ontoserver
  max_count             = 8
  min_count             = 1
  vnet_subnet_id        = module.network.vnet_subnets[0]
  os_disk_size_gb       = 1024

  node_labels = {
    nodepool = "prod_k8s_nodepool",
  }

  tags = {
    Environment = var.aks_environment
  }
}

# Attach ACT To the Cluster
resource "azurerm_role_assignment" "acr_kube_role" {
  count                = var.acr_enabled ? 1 : 0
  scope                = azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.system_assigned_identity[0].principal_id
}
