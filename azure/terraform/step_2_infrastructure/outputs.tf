output "aks_host" {
  value       = module.aks.host
  sensitive   = true
  description = "Azure Kubernetes Services Host"
}

output "aks_cluster" {
  value       = var.aks_cluster_name
  description = "Kube config to connect to AKS"
}

output "aks_resource_group" {
  value       = module.aks.node_resource_group
  description = "The resource group created for the AKS cluster"
}

output "aks_system_identity" {
  description = "The `azurerm_kubernetes_cluster`'s `identity` block."
  value       = try(module.aks.identity[0], null)
}

output "aks_kubelet_identity" {
  value       = module.aks.kubelet_identity
  description = "The resource group created for the AKS cluster"
}


output "database_host" {
  value       = var.setup_db ? azurerm_postgresql_server.onto[0].fqdn : "Not available for this deployment"
  description = "Database host name"
}

output "database_name" {
  value       = var.setup_db ? azurerm_postgresql_database.onto[0].name : "Not available for this deployment"
  description = "Database name"
}