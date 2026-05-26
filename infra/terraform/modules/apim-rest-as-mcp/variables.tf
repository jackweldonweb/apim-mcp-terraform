variable "api_management_name" {
  description = "Name of the existing APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "api_name" {
  description = "Display name and URL slug for the MCP-synthesised REST API in APIM."
  type        = string
}

variable "api_path" {
  description = "Path suffix used to route requests to this API (e.g. 'incidents-mcp')."
  type        = string
}

variable "openapi_spec_url" {
  description = "URL of the OpenAPI 3.x specification for the backend REST API. APIM imports this to generate operations."
  type        = string
}

variable "backend_url" {
  description = "Backend REST API base URL. APIM forwards requests here using Managed Identity."
  type        = string
}

variable "product_display_name" {
  description = "Display name of the APIM Product that gates access to this MCP endpoint."
  type        = string
  default     = "MCP REST-as-MCP Gateway"
}

variable "policy_fragment_ids" {
  description = "Map of fragment name to resource ID output from the apim-shared-policy-fragments module. Used to establish explicit dependency ordering."
  type        = map(string)
}
