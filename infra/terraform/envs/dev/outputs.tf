output "pattern1_api_id" {
  description = "APIM API resource ID for Pattern 1 (REST-as-MCP)."
  value       = module.sample_rest_api_mcp.api_id
}

output "pattern1_product_id" {
  description = "APIM Product ID for Pattern 1.  MCP clients need a subscription key from this product."
  value       = module.sample_rest_api_mcp.product_id
}

output "pattern2_api_id" {
  description = "APIM API resource ID for Pattern 2 (govern existing MCP server)."
  value       = module.sample_mcp_server.api_id
}

output "pattern2_backend_id" {
  description = "APIM Backend resource ID for the SampleMcpServer."
  value       = module.sample_mcp_server.backend_id
}

output "pattern2_product_id" {
  description = "APIM Product ID for Pattern 2.  MCP clients need a subscription key from this product."
  value       = module.sample_mcp_server.product_id
}
