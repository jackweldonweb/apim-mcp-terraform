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

# Pattern 2: Govern existing MCP server
# APIM sits in front of a .NET MCP server (SampleMcpServer) that already
# speaks the Model Context Protocol.  APIM adds Entra JWT validation,
# rate limiting, quota, metrics, and credential abstraction without any
# changes to the MCP server itself.
#
# Backend auth: Managed Identity — the MCP server accepts tokens from the
# APIM gateway's managed identity only.  The MCP client never sees backend
# credentials (credential abstraction).
#
# Keep-alive: the .NET MCP server must emit a SSE comment ping every <3 min
# to prevent the Azure LB from closing the idle connection (4-min timeout).
#
# NOTE: APIM Workspaces do not yet support MCP — use Products until GA.

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── Backend (credential abstraction) ─────────────────────────────────────────

resource "azurerm_api_management_backend" "this" {
  name                = "${var.api_name}-backend"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  protocol            = "http"
  url                 = var.backend_url

  credentials {
    # APIM injects a Managed Identity token for the backend resource.
    # The MCP server validates this token — the MCP client never sees it.
    authorization {
      scheme    = "Bearer"
      parameter = "{{mcp-backend-mi-token}}"
    }
  }

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
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

  service_url = var.backend_url
}

# ── Policy ────────────────────────────────────────────────────────────────────

resource "azurerm_api_management_api_policy" "this" {
  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <include-fragment fragment-id="validate-entra-token" />
        <include-fragment fragment-id="rate-limit-per-subscription" />
        <include-fragment fragment-id="quota-per-subscription" />
        <include-fragment fragment-id="emit-tool-call-metric" />
        <set-backend-service backend-id="${azurerm_api_management_backend.this.name}" />
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

# ── Product ───────────────────────────────────────────────────────────────────

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

# ── MCP control plane (azapi — no native azurerm resource yet) ────────────────
#
# TODO: Register the governed server as an MCP server once azurerm exposes
# azurerm_api_management_mcp_server.  Until then use azapi_resource:
#
# resource "azapi_resource" "mcp_server" {
#   type      = "Microsoft.ApiManagement/service/mcpServers@2025-01-01"
#   name      = var.api_name
#   parent_id = data.azurerm_api_management.this.id
#
#   body = {
#     properties = {
#       apiId       = azurerm_api_management_api.this.id
#       description = "Governed MCP server: ${var.api_name}"
#     }
#   }
# }
