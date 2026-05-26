output "api_id" {
  description = "APIM API resource ID."
  value       = azurerm_api_management_api.this.id
}

output "product_id" {
  description = "APIM Product resource ID.  Subscription keys for this product grant MCP client access."
  value       = azurerm_api_management_product.this.id
}

output "mcp_server_id" {
  description = "Resource ID of the azapi mcpServers projection.  Null until the mcpServers API version is confirmed and the resource block uncommented."
  value       = try(azapi_resource.mcp_server[0].id, null)
}

output "backend_credential_named_value_id" {
  description = "APIM named value resource ID for the KV-backed backend credential."
  value       = azurerm_api_management_named_value.backend_credential.id
}
