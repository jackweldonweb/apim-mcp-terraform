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
  }
}

# Pattern 1: REST-as-MCP
# APIM imports an existing REST API via its OpenAPI spec and exposes it as an
# MCP server.  No custom MCP server code is required — APIM synthesises the
# tool manifest and marshals JSON-RPC tool calls to the corresponding REST
# operations.
#
# Authorisation unit: one APIM Product per MCP server.
# NOTE: APIM Workspaces do not yet support MCP — use Products until GA.

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── API ──────────────────────────────────────────────────────────────────────

resource "azurerm_api_management_api" "this" {
  name                = var.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  revision            = "1"
  display_name        = var.api_name
  path                = var.api_path
  protocols           = ["https"]

  import {
    content_format = "openapi-link"
    content_value  = var.openapi_spec_url
  }
}

# ── Policy (inline — references shared fragments) ────────────────────────────

resource "azurerm_api_management_api_policy" "this" {
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  # var.policy_fragment_ids is referenced only to establish ordering; the
  # actual fragment names are embedded in the XML below as fragment-id values.
  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <include-fragment fragment-id="validate-entra-token" />
        <include-fragment fragment-id="rate-limit-per-subscription" />
        <include-fragment fragment-id="quota-per-subscription" />
        <include-fragment fragment-id="emit-tool-call-metric" />
      </inbound>
      <backend>
        <include-fragment fragment-id="sse-hygiene" />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <include-fragment fragment-id="mcp-error-handling" />
      </on-error>
    </policies>
  XML

  depends_on = [var.policy_fragment_ids]
}

# ── Product (authorisation unit) ─────────────────────────────────────────────

resource "azurerm_api_management_product" "this" {
  product_id            = replace(lower(var.api_name), " ", "-")
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  display_name          = var.product_display_name
  subscription_required = true
  subscriptions_limit   = 50
  approval_required     = true
  published             = true
}

resource "azurerm_api_management_product_api" "this" {
  api_name            = azurerm_api_management_api.this.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── MCP control plane (azapi — no native azurerm resource yet) ───────────────
#
# TODO: Register the API as an MCP server once the azurerm provider exposes
# azurerm_api_management_mcp_server.  Until then use azapi_resource to call
# the APIM REST API directly:
#
# resource "azapi_resource" "mcp_server" {
#   type      = "Microsoft.ApiManagement/service/mcpServers@2025-01-01"
#   name      = var.api_name
#   parent_id = data.azurerm_api_management.this.id
#
#   body = {
#     properties = {
#       apiId       = azurerm_api_management_api.this.id
#       description = "REST-as-MCP gateway for ${var.api_name}"
#     }
#   }
# }
