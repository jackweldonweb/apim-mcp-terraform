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
# MCP server.  APIM synthesises the MCP tool manifest and marshals JSON-RPC
# tool calls to the corresponding REST operations.  No custom MCP server code
# is required.
#
# Credential abstraction: the backend credential is stored in Key Vault.
# APIM retrieves it via a KV-backed named value and injects it into every
# forwarded request.  MCP clients never see the backend credential.
#
# Authorisation unit: one APIM Product per MCP server.
# NOTE: APIM Workspaces do not yet support MCP — Products are the correct
# isolation boundary until Workspace MCP support reaches GA.

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# ── Backend credential (Key Vault-backed named value) ─────────────────────────
#
# Stored as a secret named value so APIM can rotate the credential from Key
# Vault without a Terraform apply.  The user-assigned managed identity must
# have Key Vault Secrets User on the secret.

resource "azurerm_api_management_named_value" "backend_credential" {
  name                = "${var.api_name}-backend-credential"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "${var.api_name}-backend-credential"
  secret              = true

  value_from_key_vault {
    secret_id          = var.backend_credential_kv_secret_id
    identity_client_id = var.apim_user_assigned_identity_client_id
  }
}

# ── API (imported from OpenAPI spec) ─────────────────────────────────────────

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

  import {
    content_format = "openapi-link"
    content_value  = var.openapi_spec_url
  }
}

# ── Policy (API scope — all 6 shared fragments) ───────────────────────────────
#
# Fragment ordering within inbound is significant:
#   validate-entra-token must run first — it sets caller-object-id and
#   caller-app-id context variables consumed by the fragments that follow.
#
# The backend_credential named value display_name is interpolated by Terraform
# here so the APIM named value reference ({{...}}) is constructed correctly.
# The outer {{ }} are APIM syntax; ${...} is resolved by Terraform at apply time.

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
        <set-backend-service base-url="${var.backend_url}" />
        <set-header name="${var.backend_credential_header_name}" exists-action="override">
          <value>{{${azurerm_api_management_named_value.backend_credential.display_name}}}</value>
        </set-header>
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

  # Fragments must exist before the policy that references them.
  # policy_fragment_ids carries the fragment resource IDs purely for ordering.
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
# The resource type and API version below reflect the APIM REST API as of
# 2025-05 — verify against the latest API spec before applying to production.
# Uncomment once the target environment's APIM version supports mcpServers.

resource "azapi_resource" "mcp_server" {
  count = 0 # set to 1 once API version is confirmed

  type                      = "Microsoft.ApiManagement/service/mcpServers@2025-05-01-preview"
  schema_validation_enabled = false # mcpServers not yet in azapi embedded schema
  name                      = "${var.api_name}-mcp"
  parent_id                 = data.azurerm_api_management.this.id

  body = {
    properties = {
      apiId         = azurerm_api_management_api.this.id
      transportType = "streamableHttp"
      description   = var.api_display_name
    }
  }

  response_export_values = ["*"]
}
