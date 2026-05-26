# ADR 0002: azapi Provider for MCP Control Plane Resources

**Status:** Accepted  
**Date:** 2025-05

---

## Context

The `azurerm` Terraform provider (v4.x as of this writing) does not include a native `azurerm_api_management_mcp_server` resource. The APIM `mcpServers` resource type was added as a preview feature in the Azure REST API at `2025-05-01-preview` and has not yet been incorporated into the azurerm provider's resource model.

Two options exist:

1. **Skip the MCP server projection entirely** — deploy the API, Product, and policies without registering the MCP server endpoint in the APIM control plane. MCP clients can still connect to the API path directly; the projection is primarily for management visibility in the Azure portal.

2. **Use the `azapi` provider** — call the Azure REST API directly using `azapi_resource` with the preview API version. The `azapi` provider is maintained by Microsoft and is the recommended path for using Azure resources before they land in the azurerm provider.

---

## Decision

Use the `azapi` provider for the `mcpServers` resource projection with the following constraints:

- `schema_validation_enabled = false` — the `mcpServers` type is not yet in the azapi provider's embedded ARM schema (as of azapi 2.9.0). Without this flag, `terraform validate` fails because the provider rejects the resource body as unrecognised. This flag disables body validation for this specific resource only; all other resources use the default validated mode.
- `count = 0` — the resource block is present but disabled by default. Set to `1` only after verifying the target APIM instance's API version supports `mcpServers`. This prevents accidental apply failures when deploying to older APIM instances.
- The resource type and API version (`2025-05-01-preview`) must be re-verified against the Azure REST API spec before any production apply.

---

## Consequences

**Positive:**
- The MCP server projection is fully expressed in Terraform, making the intent explicit and the configuration reviewable in pull requests.
- `azapi` is a first-class Microsoft provider, not a workaround. The pattern is the same one Microsoft recommends in its own reference architectures for preview resources.

**Negative / Risks:**
- `schema_validation_enabled = false` means Terraform will not catch typos in the `body` block at plan time — errors surface only on apply. Review the body carefully before enabling `count = 1`.
- The `2025-05-01-preview` API version may be superseded. Check the [APIM REST API changelog](https://learn.microsoft.com/en-us/rest/api/apimanagement/changes) before applying.

**Migration path when azurerm catches up:**
1. Remove the `azapi_resource "mcp_server"` block from the module.
2. Add an `azurerm_api_management_mcp_server` resource using the same `api_id`, `transport_type`, and `description` values.
3. Import the existing resource into state: `terraform import azurerm_api_management_mcp_server.<name> <resource_id>`.
4. Remove `azapi` from `required_providers` if no other azapi resources remain.
