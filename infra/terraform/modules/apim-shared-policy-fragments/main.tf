terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}

locals {
  policies_path = var.fragments_path != "" ? var.fragments_path : "${path.module}/policies"
}

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# Named values are stored in Key Vault and must propagate to all APIM gateway
# nodes before any policy that references them is activated.  The 120 s delay
# is the minimum observed safe window for propagation in a single-region
# Premium instance; increase to 180 s for multi-region deployments.
resource "time_sleep" "named_values_propagation" {
  create_duration = "120s"

  triggers = {
    named_values_trigger = var.named_values_propagation_trigger
  }
}

resource "azurerm_api_management_policy_fragment" "validate_entra_token" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "validate-entra-token"
  format            = "rawxml"
  value             = file("${local.policies_path}/validate-entra-token.xml")

  depends_on = [time_sleep.named_values_propagation]
}

resource "azurerm_api_management_policy_fragment" "sse_hygiene" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "sse-hygiene"
  format            = "rawxml"
  value             = file("${local.policies_path}/sse-hygiene.xml")

  depends_on = [time_sleep.named_values_propagation]
}

resource "azurerm_api_management_policy_fragment" "rate_limit_per_sub" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "rate-limit-per-subscription"
  format            = "rawxml"
  value             = file("${local.policies_path}/rate-limit-per-subscription.xml")

  depends_on = [time_sleep.named_values_propagation]
}

resource "azurerm_api_management_policy_fragment" "quota_per_sub" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "quota-per-subscription"
  format            = "rawxml"
  value             = file("${local.policies_path}/quota-per-subscription.xml")

  depends_on = [time_sleep.named_values_propagation]
}

resource "azurerm_api_management_policy_fragment" "emit_tool_call_metric" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "emit-tool-call-metric"
  format            = "rawxml"
  value             = file("${local.policies_path}/emit-tool-call-metric.xml")

  depends_on = [time_sleep.named_values_propagation]
}

resource "azurerm_api_management_policy_fragment" "mcp_error_handling" {
  api_management_id = data.azurerm_api_management.this.id
  name              = "mcp-error-handling"
  format            = "rawxml"
  value             = file("${local.policies_path}/mcp-error-handling.xml")

  depends_on = [time_sleep.named_values_propagation]
}
