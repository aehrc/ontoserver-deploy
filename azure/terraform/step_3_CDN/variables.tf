variable "azure_location" {
  description = "Azure location"
  type        = string
  default     = "Australia East"
}

variable "resource_group" {
  description = "Resource group name"
  type        = string
  default     = "example-onto-resource-group"
}

variable "origin_host" {
  description = "Origin hosting Ontoserver"
  type        = string
}

