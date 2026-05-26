data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── Named values ─────────────────────────────────────────────────────────────
# Direct named values (not KV-backed) for configuration that is not secret.
# The named_values_propagation_trigger below captures all IDs so the policy
# fragments module waits for propagation before activating any fragment.

resource "azurerm_api_management_named_value" "tenant_id" {
  name                = "mcp-gateway-tenant-id"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-gateway-tenant-id"
  value               = var.tenant_id
  secret              = false
}

resource "azurerm_api_management_named_value" "audience" {
  name                = "mcp-gateway-audience"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-gateway-audience"
  value               = var.mcp_gateway_audience
  secret              = false
}

resource "azurerm_api_management_named_value" "required_scope" {
  name                = "mcp-required-scope"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-required-scope"
  value               = var.mcp_required_scope
  secret              = false
}

resource "azurerm_api_management_named_value" "rate_limit_calls" {
  name                = "mcp-rate-limit-calls"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-rate-limit-calls"
  value               = tostring(var.mcp_rate_limit_calls)
  secret              = false
}

resource "azurerm_api_management_named_value" "rate_limit_period" {
  name                = "mcp-rate-limit-period-seconds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-rate-limit-period-seconds"
  value               = tostring(var.mcp_rate_limit_period_seconds)
  secret              = false
}

resource "azurerm_api_management_named_value" "quota_calls" {
  name                = "mcp-quota-calls"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-quota-calls"
  value               = tostring(var.mcp_quota_calls)
  secret              = false
}

resource "azurerm_api_management_named_value" "quota_period" {
  name                = "mcp-quota-period-seconds"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "mcp-quota-period-seconds"
  value               = tostring(var.mcp_quota_period_seconds)
  secret              = false
}

# ── Shared policy fragments ──────────────────────────────────────────────────

module "shared_policy_fragments" {
  source = "./modules/apim-shared-policy-fragments"

  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  named_values_propagation_trigger = join(",", [
    azurerm_api_management_named_value.tenant_id.id,
    azurerm_api_management_named_value.audience.id,
    azurerm_api_management_named_value.required_scope.id,
    azurerm_api_management_named_value.rate_limit_calls.id,
    azurerm_api_management_named_value.rate_limit_period.id,
    azurerm_api_management_named_value.quota_calls.id,
    azurerm_api_management_named_value.quota_period.id,
  ])
}

# ── Pattern 1: REST-as-MCP ───────────────────────────────────────────────────

module "rest_as_mcp" {
  source = "./modules/apim-rest-as-mcp"

  api_management_name  = var.api_management_name
  resource_group_name  = var.resource_group_name
  api_name             = "incidents-rest-as-mcp"
  api_path             = "incidents-mcp"
  openapi_spec_url     = "${var.sample_rest_api_url}/openapi/v1.json"
  backend_url          = var.sample_rest_api_url
  product_display_name = "Incidents MCP (REST-as-MCP)"
  policy_fragment_ids  = module.shared_policy_fragments.policy_fragment_ids
}

# ── Pattern 2: Govern existing MCP server ────────────────────────────────────

module "govern_mcp_server" {
  source = "./modules/apim-govern-mcp-server"

  api_management_name  = var.api_management_name
  resource_group_name  = var.resource_group_name
  api_name             = "sample-mcp-server"
  api_path             = "sample-mcp"
  backend_url          = var.sample_mcp_server_url
  product_display_name = "Sample MCP Server (Governed)"
  policy_fragment_ids  = module.shared_policy_fragments.policy_fragment_ids
}
