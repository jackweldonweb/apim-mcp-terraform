# ── Existing infrastructure ───────────────────────────────────────────────────

variable "api_management_name" {
  description = "Name of the existing APIM Premium instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that contains the APIM instance and related resources."
  type        = string
}

# ── Application Insights ──────────────────────────────────────────────────────

variable "application_insights_id" {
  description = "Resource ID of the Application Insights instance for APIM telemetry."
  type        = string
}

variable "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key.  Keep out of source control — supply via CI secret or Key Vault data source."
  type        = string
  sensitive   = true
}

variable "application_insights_name" {
  description = "Name used for the APIM Application Insights logger resource."
  type        = string
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

variable "key_vault_id" {
  description = "Resource ID of the Key Vault that stores backend credentials for Pattern 1."
  type        = string
}

variable "apim_user_assigned_identity_client_id" {
  description = "Client ID of the user-assigned managed identity that APIM uses to read Key Vault secrets."
  type        = string
}

# ── Pattern 1: REST-as-MCP ────────────────────────────────────────────────────

variable "sample_rest_api_url" {
  description = "Base URL of the SampleRestApi Container Apps deployment (e.g. https://sample-rest-api.internal.example.com)."
  type        = string
}

variable "sample_rest_api_openapi_url" {
  description = "URL of the SampleRestApi OpenAPI spec that APIM imports.  Must be reachable from APIM at apply time."
  type        = string
  default     = ""
}

variable "sample_rest_api_credential_secret_id" {
  description = "Key Vault secret ID for the SampleRestApi backend credential (if the backend requires a key).  Versioned or unversioned URI."
  type        = string
  default     = ""
}

# ── Pattern 2: Govern existing MCP server ─────────────────────────────────────

variable "sample_mcp_server_url" {
  description = "Base URL of the SampleMcpServer Container Apps deployment (e.g. https://sample-mcp-server.internal.example.com)."
  type        = string
}

variable "sample_mcp_server_entra_resource_id" {
  description = "Entra application ID URI of the SampleMcpServer app registration.  APIM acquires a managed-identity token for this resource and injects it as the Authorization header."
  type        = string
}

# ── Authorisation ─────────────────────────────────────────────────────────────

variable "entra_tenant_id" {
  description = "Entra tenant ID used by the validate-entra-token policy fragment."
  type        = string
}

variable "gateway_audience" {
  description = "Entra audience claim the MCP client must include in its bearer token.  Typically the APIM app registration Application ID URI."
  type        = string
}

variable "required_scope" {
  description = "OAuth 2.0 scope that callers must hold.  The validate-entra-token fragment rejects tokens that do not include this scope."
  type        = string
  default     = "mcp.tools"
}

# ── Rate limiting / quota ─────────────────────────────────────────────────────

variable "rate_limit_calls" {
  description = "Number of calls allowed per rate-limit window per subscription."
  type        = number
  default     = 100
}

variable "rate_limit_period_seconds" {
  description = "Rate-limit window duration in seconds."
  type        = number
  default     = 60
}

variable "quota_calls" {
  description = "Total call quota per quota window per subscription."
  type        = number
  default     = 10000
}

variable "quota_period_seconds" {
  description = "Quota window duration in seconds (e.g. 86400 = 1 day)."
  type        = number
  default     = 86400
}
