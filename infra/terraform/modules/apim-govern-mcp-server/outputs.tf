output "api_id" {
  description = "APIM API resource ID for the governed MCP server API."
  value       = azurerm_api_management_api.this.id
}

output "product_id" {
  description = "APIM Product resource ID. Subscription keys for this product grant access."
  value       = azurerm_api_management_product.this.id
}

output "backend_id" {
  description = "APIM Backend resource ID pointing to the .NET MCP server."
  value       = azurerm_api_management_backend.this.id
}
