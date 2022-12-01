resource "azurerm_cdn_profile" "onto" {
  location            = "global"
  name                = "ontoserver-test"
  resource_group_name = data.azurerm_resource_group.onto.name
  sku                 = "Standard_Akamai"
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_cdn_endpoint" "onto" {
  location            = "global"
  name                = azurerm_cdn_profile.onto.name
  profile_name        = azurerm_cdn_profile.onto.name
  resource_group_name = azurerm_cdn_profile.onto.resource_group_name
  optimization_type   = "GeneralWebDelivery"
  origin {
    host_name = var.origin_host
    name      = "ontoserver-test"
  }
  is_compression_enabled = true
  content_types_to_compress = [
    "application/javascript",
    "application/json",
    "application/x-javascript",
    "application/xml",
    "text/css",
    "text/html",
    "text/javascript",
    "text/plain",
    "application/fhir+json",
    "application/fhir+xml"
  ]
  origin_host_header            = var.origin_host
  querystring_caching_behaviour = "UseQueryString"
  lifecycle {
    ignore_changes = [
      tags,
      // The Terraform provider does not currently have the ability to manage the cache expiration rule.
      // See: https://github.com/terraform-providers/terraform-provider-azurerm/issues/6407
      global_delivery_rule
    ]
  }
}
