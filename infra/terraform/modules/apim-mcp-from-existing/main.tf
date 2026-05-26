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
# APIM sits in front of a .NET 9 MCP server (SampleMcpServer) that speaks
# the Model Context Protocol natively using Streamable HTTP transport.
# APIM adds Entra JWT validation, rate limiting, quota, and metrics without
# any changes to the MCP server source code.
#
# Credential abstraction: APIM acquires a Managed Identity token for the
# backend Entra resource and injects it.  MCP clients authenticate to APIM
# only — they never hold backend credentials.
#
# Backend trust boundary: the Container Apps MCP server accepts connections
# ONLY from the APIM managed identity.  Enforce this via Container Apps
# ingress restrictions (IP allowlist or private endpoint) in addition to the
# managed identity check.
#
# Keep-alive: the .NET MCP server must emit a SSE comment ping every <3 min.
# Azure Load Balancer terminates idle connections after 4 min.  Configure
# the server-side ping in SampleMcpServer Program.cs.
#
# Transport: streamableHTTP (Streamable HTTP — HTTP+SSE deprecated mid-2025).
#
# Authorisation unit: one APIM Product per MCP server.
# NOTE: APIM Workspaces do not yet support MCP — Products are the correct
# isolation boundary until Workspace MCP support reaches GA.

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── Backend (Managed Identity credential abstraction) ────────────────────────
#
# APIM backend resource registers the .NET MCP server.  The authentication
# block instructs APIM to call authentication-managed-identity in the policy
# pipeline to obtain a bearer token for backend_entra_resource_id.
# The actual token acquisition is done by the policy, not here — this resource
# sets the URL and TLS posture only.

resource "azurerm_api_management_backend" "this" {
  name                = "${var.api_name}-backend"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  protocol            = "http"
  url                 = var.backend_url

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

# ── API ───────────────────────────────────────────────────────────────────────

resource "azurerm_api_management_api" "this" {
  name                  = var.api_name
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = var.api_display_name
  path                  = var.api_path
  protocols             = ["https"]
  subscription_required = true
  service_url           = var.backend_url
}

# ── Policy (API scope — all 6 shared fragments + MI backend auth) ─────────────
#
# authentication-managed-identity acquires a token for the backend Entra
# resource using APIM's system-assigned or user-assigned managed identity.
# This token is set as the Authorization header forwarded to the backend.
# The backend (SampleMcpServer) validates this token and rejects all others.
#
# Fragment ordering within inbound:
#   validate-entra-token → (sets caller context variables)
#   rate-limit-per-subscription → (uses caller-object-id)
#   quota-per-subscription → (uses caller-object-id)
#   emit-tool-call-metric → (uses caller-object-id, caller-app-id)
#   authentication-managed-identity → (replaces Authorization before backend)

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
        <authentication-managed-identity resource="${var.backend_entra_resource_id}" />
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
  product_id            = var.api_name
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  display_name          = var.product_display_name
  subscription_required = true
  subscriptions_limit   = var.product_subscriptions_limit
  approval_required     = true
  published             = true
}

resource "azurerm_api_management_product_api" "this" {
  api_name            = azurerm_api_management_api.this.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── MCP server projection (azapi) ─────────────────────────────────────────────
#
# There is no native azurerm_api_management_mcp_server resource in azurerm 4.x.
# Pattern 2 explicitly uses transportType = "streamableHTTP" to match the
# .NET MCP server's Streamable HTTP transport (not SSE, which was deprecated
# mid-2025).
#
# Verify the API version against the APIM REST API spec before enabling.

resource "azapi_resource" "mcp_server" {
  count = 0 # set to 1 once API version is confirmed

  type                      = "Microsoft.ApiManagement/service/mcpServers@2025-05-01-preview"
  schema_validation_enabled = false # mcpServers not yet in azapi embedded schema
  name                      = "${var.api_name}-mcp"
  parent_id                 = data.azurerm_api_management.this.id

  body = {
    properties = {
      apiId         = azurerm_api_management_api.this.id
      transportType = "streamableHTTP"
      description   = var.api_display_name
    }
  }

  response_export_values = ["*"]
}
