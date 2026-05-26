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
  description = "URL path suffix that APIM routes to this API (e.g. 'incidents-mcp')."
  type        = string
}

variable "openapi_spec_url" {
  description = "URL of the OpenAPI 3.x spec served by the backend REST API.  APIM imports this at apply time to generate operations.  Must be reachable from the Terraform executor or APIM import endpoint."
  type        = string
}

variable "backend_url" {
  description = "Base URL of the backend REST API.  APIM forwards synthesised REST calls here."
  type        = string
}

variable "backend_credential_header_name" {
  description = "HTTP request header APIM uses to pass the backend credential (e.g. 'X-Api-Key' or 'Authorization')."
  type        = string
  default     = "X-Api-Key"
}

variable "backend_credential_kv_secret_id" {
  description = "Versioned or unversioned Azure Key Vault secret ID containing the backend API credential.  APIM reads this via the user-assigned managed identity."
  type        = string
}

variable "apim_user_assigned_identity_client_id" {
  description = "Client ID of the user-assigned managed identity attached to APIM that has Get/List on the Key Vault secret.  Required for KV-backed named values."
  type        = string
}

variable "product_display_name" {
  description = "Display name of the APIM Product that gates access to this MCP endpoint."
  type        = string
  default     = "MCP Gateway — REST-as-MCP"
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
