output "endpoint" {
  value       = "https://${azurerm_cdn_endpoint.onto.host_name}/fhir"
  description = "Endpoint"
}
