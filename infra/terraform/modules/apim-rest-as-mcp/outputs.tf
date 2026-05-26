output "api_id" {
  description = "APIM API resource ID for the REST-as-MCP API."
  value       = azurerm_api_management_api.this.id
}

output "product_id" {
  description = "APIM Product resource ID. Subscription keys for this product grant access."
  value       = azurerm_api_management_product.this.id
}
