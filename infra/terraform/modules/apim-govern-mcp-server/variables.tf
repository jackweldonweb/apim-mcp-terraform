variable "api_management_name" {
  description = "Name of the existing APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "api_name" {
  description = "Display name and resource slug for the governed MCP server API in APIM."
  type        = string
}

variable "api_path" {
  description = "Path suffix used to route requests to this API (e.g. 'sample-mcp')."
  type        = string
}

variable "backend_url" {
  description = "Base URL of the .NET MCP server backend (e.g. ACA FQDN). APIM proxies all MCP traffic here."
  type        = string
}

variable "backend_managed_identity_resource_id" {
  description = "Resource ID of the user-assigned managed identity used by APIM to authenticate to the backend. Leave empty to use system-assigned identity."
  type        = string
  default     = ""
}

variable "product_display_name" {
  description = "Display name of the APIM Product that gates access to this MCP endpoint."
  type        = string
  default     = "MCP Governed Server Gateway"
}

variable "policy_fragment_ids" {
  description = "Map of fragment name to resource ID output from the apim-shared-policy-fragments module. Used to establish explicit dependency ordering."
  type        = map(string)
}
