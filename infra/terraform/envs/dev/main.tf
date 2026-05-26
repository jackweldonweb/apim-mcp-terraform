terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.15.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}

# ── Shared named values ───────────────────────────────────────────────────────
#
# These gateway-wide values are referenced by multiple policy fragments.
# All are direct (not KV-backed) because they are not secrets — they are
# well-known configuration values such as tenant ID and audience.

resource "azurerm_api_management_named_value" "tenant_id" {
  name                = "mcp-gateway-tenant-id"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-gateway-tenant-id"
  value               = var.entra_tenant_id
  secret              = false
}

resource "azurerm_api_management_named_value" "audience" {
  name                = "mcp-gateway-audience"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-gateway-audience"
  value               = var.gateway_audience
  secret              = false
}

resource "azurerm_api_management_named_value" "required_scope" {
  name                = "mcp-required-scope"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-required-scope"
  value               = var.required_scope
  secret              = false
}

resource "azurerm_api_management_named_value" "rate_limit_calls" {
  name                = "mcp-rate-limit-calls"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-rate-limit-calls"
  value               = tostring(var.rate_limit_calls)
  secret              = false
}

resource "azurerm_api_management_named_value" "rate_limit_period_seconds" {
  name                = "mcp-rate-limit-period-seconds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-rate-limit-period-seconds"
  value               = tostring(var.rate_limit_period_seconds)
  secret              = false
}

resource "azurerm_api_management_named_value" "quota_calls" {
  name                = "mcp-quota-calls"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-quota-calls"
  value               = tostring(var.quota_calls)
  secret              = false
}

resource "azurerm_api_management_named_value" "quota_period_seconds" {
  name                = "mcp-quota-period-seconds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-quota-period-seconds"
  value               = tostring(var.quota_period_seconds)
  secret              = false
}

# ── Shared policy fragments ───────────────────────────────────────────────────

module "shared_policy_fragments" {
  source = "../../modules/apim-shared-policy-fragments"

  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  # Pass all named value IDs as a single trigger string so time_sleep only
  # fires when named values actually change (not on every apply).
  named_values_propagation_trigger = join(",", [
    azurerm_api_management_named_value.tenant_id.id,
    azurerm_api_management_named_value.audience.id,
    azurerm_api_management_named_value.required_scope.id,
    azurerm_api_management_named_value.rate_limit_calls.id,
    azurerm_api_management_named_value.rate_limit_period_seconds.id,
    azurerm_api_management_named_value.quota_calls.id,
    azurerm_api_management_named_value.quota_period_seconds.id,
  ])
}

# ── Diagnostics ───────────────────────────────────────────────────────────────

module "diagnostics" {
  source = "../../modules/apim-diagnostics"

  api_management_name                     = var.api_management_name
  resource_group_name                     = var.resource_group_name
  application_insights_id                 = var.application_insights_id
  application_insights_instrumentation_key = var.application_insights_instrumentation_key
  application_insights_name               = var.application_insights_name
}

# ── Pattern 1: REST-as-MCP ────────────────────────────────────────────────────
#
# APIM imports the SampleRestApi OpenAPI spec and synthesises an MCP server.
# The backend credential is stored in Key Vault and injected by APIM — the
# MCP client never sees the backend API key.

module "sample_rest_api_mcp" {
  source = "../../modules/apim-mcp-from-rest"

  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  api_name         = "sample-rest-api"
  api_display_name = "Sample REST API (MCP)"
  api_path         = "sample-rest-api"
  backend_url      = var.sample_rest_api_url

  openapi_spec_url = var.sample_rest_api_openapi_url != "" ? var.sample_rest_api_openapi_url : "${var.sample_rest_api_url}/openapi/v1.json"

  backend_credential_kv_secret_id          = var.sample_rest_api_credential_secret_id
  apim_user_assigned_identity_client_id    = var.apim_user_assigned_identity_client_id
  backend_credential_header_name           = "X-Api-Key"

  product_display_name       = "Sample REST API MCP Access"
  product_subscriptions_limit = 10

  policy_fragment_ids = module.shared_policy_fragments.policy_fragment_ids
}

# ── Pattern 2: Govern existing MCP server ─────────────────────────────────────
#
# APIM governs the SampleMcpServer .NET application that already speaks
# Streamable HTTP MCP natively.  APIM adds auth, rate limiting, quota, and
# metrics without changes to the MCP server source code.

module "sample_mcp_server" {
  source = "../../modules/apim-mcp-from-existing"

  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  api_name         = "sample-mcp-server"
  api_display_name = "Sample MCP Server"
  api_path         = "sample-mcp-server"
  backend_url      = var.sample_mcp_server_url

  backend_entra_resource_id = var.sample_mcp_server_entra_resource_id

  product_display_name        = "Sample MCP Server Access"
  product_subscriptions_limit = 10

  policy_fragment_ids = module.shared_policy_fragments.policy_fragment_ids
}
