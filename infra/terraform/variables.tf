variable "api_management_name" {
  description = "Name of the existing APIM Premium instance. This module treats APIM as a data source — it does not provision a new instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID. Written to the mcp-gateway-tenant-id named value."
  type        = string
}

variable "mcp_gateway_audience" {
  description = "Entra application URI or client ID that APIM validates as the token audience. Written to mcp-gateway-audience named value."
  type        = string
}

variable "mcp_required_scope" {
  description = "Scope that callers must present in their Entra token (scp or roles claim). Written to mcp-required-scope named value."
  type        = string
  default     = "mcp.call"
}

variable "mcp_rate_limit_calls" {
  description = "Short-window call budget enforced by rate-limit-per-subscription. Calls per renewal period."
  type        = number
  default     = 300
}

variable "mcp_rate_limit_period_seconds" {
  description = "Renewal period in seconds for the rate limit window."
  type        = number
  default     = 60
}

variable "mcp_quota_calls" {
  description = "Long-window call budget enforced by quota-per-subscription."
  type        = number
  default     = 50000
}

variable "mcp_quota_period_seconds" {
  description = "Renewal period in seconds for the quota window. 604800 = 7 days."
  type        = number
  default     = 604800
}

variable "sample_rest_api_url" {
  description = "Base URL of the SampleRestApi (ACA FQDN). Used by Pattern 2 module as backend URL."
  type        = string
}

variable "sample_mcp_server_url" {
  description = "Base URL of the SampleMcpServer (ACA FQDN). Used by Pattern 2 module as backend URL."
  type        = string
}
