variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "Australia East"
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
  default     = "ontoexample_resourcegroup"
}

variable "aks_cluster_admins_aad" {
  description = "Azure AD group name for AKS cluster admins"
  type        = string
}

variable "aks_cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "onto-exampke-k8s"
}

variable "agent_size_default" {
  description = "Default Kubernetes nodepool for small pods"
  type        = string
  default     = "Standard_B2ms"
}

variable "agent_size_large" {
  description = "Kubernetes nodepool for memory/cpu hungry pods"
  type        = string
  default     = "Standard_D8s_v4"
}

variable "enable_app_gateway_ingress" {
  description = "Enable the Application Gateway Ingress Controller in AKS"
  type        = bool
  default     = false
}

variable "aks_environment" {
  description = "The AKS Environment type"
  type        = string
  default     = "Production"
}

variable "log_analytics_workspace_name" {
  description = "Log Analytics Workspace name"
  type        = string
  default     = "ontoexample-k8s-logs"
}

variable "disk_type" {
  description = "Disk storage type"
  type        = string
  default     = "Premium_LRS"
}

variable "onto_disk_capacity" {
  description = "Disk capacity (GB)"
  type        = number
  default     = 512
}

variable "acr_enabled" {
  description = "Is ACR installed by terraform"
  type        = bool
  default     = true
}

variable "setup_db" {
  description = "Set up external Postgres Database"
  type        = bool
  default     = false
}

variable "database_sku" {
  description = "Database SKU"
  type        = string
  default     = "B_Gen5_2"
}

variable "database_storage" {
  description = "Database storage (MB)"
  type        = number
  default     = 5120
}

variable "database_user" {
  description = "Database user"
  type        = string
  default     = "ontoserver"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
