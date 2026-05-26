variable "api_management_name" {
  description = "Name of the existing APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "api_name" {
  description = "Resource slug for the APIM API and MCP server projection (kebab-case, no spaces)."
  type        = string
}

variable "api_display_name" {
  description = "Human-readable display name shown in the APIM developer portal."
  type        = string
}

variable "api_path" {
  description = "URL path suffix that APIM routes to this MCP server (e.g. 'sample-mcp')."
  type        = string
}

variable "backend_url" {
  description = "Base URL of the .NET MCP server running on Container Apps (e.g. https://sample-mcp.azurecontainerapps.io). APIM proxies all Streamable HTTP traffic here."
  type        = string
}

variable "backend_entra_resource_id" {
  description = <<-EOT
    Entra application URI or client ID of the .NET MCP server backend.
    APIM uses this as the 'resource' claim when acquiring a Managed Identity
    token to authenticate to the backend.  The backend validates this token
    and rejects requests from any other identity.

    Example: "api://sample-mcp-server" or "00000000-0000-0000-0000-000000000000"
  EOT
  type        = string
}

variable "product_display_name" {
  description = "Display name of the APIM Product that gates access to this MCP endpoint."
  type        = string
  default     = "MCP Gateway — Governed MCP Server"
}

variable "product_subscriptions_limit" {
  description = "Maximum number of concurrent product subscriptions."
  type        = number
  default     = 50
}

variable "policy_fragment_ids" {
  description = "Map of fragment name → resource ID from the apim-shared-policy-fragments module.  Used only to establish Terraform dependency ordering; the policy XML references fragments by name."
  type        = map(string)
}
