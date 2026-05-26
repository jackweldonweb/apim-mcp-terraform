output "apim_gateway_url" {
  description = "APIM gateway URL. MCP clients connect to this base URL."
  value       = data.azurerm_api_management.this.gateway_url
}

output "rest_as_mcp_api_id" {
  description = "APIM API resource ID for Pattern 1 (REST-as-MCP)."
  value       = module.rest_as_mcp.api_id
}

output "govern_mcp_server_api_id" {
  description = "APIM API resource ID for Pattern 2 (Governed MCP server)."
  value       = module.govern_mcp_server.api_id
}

output "policy_fragment_ids" {
  description = "Map of shared policy fragment resource IDs."
  value       = module.shared_policy_fragments.policy_fragment_ids
}
