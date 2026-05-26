output "api_id" {
  description = "APIM API resource ID."
  value       = azurerm_api_management_api.this.id
}

output "backend_id" {
  description = "APIM Backend resource ID pointing to the .NET MCP server."
  value       = azurerm_api_management_backend.this.id
}

output "product_id" {
  description = "APIM Product resource ID.  Subscription keys for this product grant MCP client access."
  value       = azurerm_api_management_product.this.id
}

output "mcp_server_id" {
  description = "Resource ID of the azapi mcpServers projection.  Null until the resource block is enabled (count = 1)."
  value       = try(azapi_resource.mcp_server[0].id, null)
}
