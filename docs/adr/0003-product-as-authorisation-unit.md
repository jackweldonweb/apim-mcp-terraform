# ADR 0003: APIM Product as the MCP Server Authorisation Unit

**Status:** Accepted  
**Date:** 2025-05

---

## Context

Azure API Management provides several isolation boundaries for APIs:

- **Workspaces** — the newest model (GA 2024). Each workspace has its own set of APIs, products, and policies. Designed for multi-team scenarios with independent deployment lifecycles.
- **Products** — the traditional model. A product groups one or more APIs and controls subscription access. Each subscriber gets a unique subscription key scoped to the product.
- **Named values / policies at API scope** — configuration applied to a specific API, shared across all products that include it.

For MCP, the natural question is: should each MCP server be a Workspace or a Product?

**Workspaces are not currently supported for MCP.** As of mid-2025, the APIM MCP server projection (`Microsoft.ApiManagement/service/mcpServers`) is not available within APIM Workspaces — it is a service-level resource only. Workspace-scoped MCP support is on the Azure roadmap but has not reached GA.

**Products provide the right semantics for MCP authorisation:** one MCP server = one product = one set of rate limits, quota, and subscription keys. This maps cleanly to the enterprise use case where each MCP server represents a distinct capability surface with its own access control boundary.

---

## Decision

Each MCP server is represented by one APIM Product:

- `azurerm_api_management_product` resource per module (Pattern 1 and Pattern 2 each create one product).
- `subscription_required = true`, `approval_required = true` — subscriptions require explicit approval, preventing unauthorised clients from self-provisioning.
- `subscriptions_limit` is configurable (default 50) — prevents unbounded proliferation.
- Rate limiting and quota policies (`rate-limit-by-key`, `quota-by-key`) key their counters on the subscription key, making each product subscriber independently rate-limited.
- The validate-entra-token policy runs in addition to the subscription key check — clients must present both a valid Entra JWT and a valid product subscription key.

---

## Consequences

**Positive:**
- Each MCP server has an independently managed access policy: rate limits, quota, and approvals can be tuned per product without affecting other MCP servers.
- The subscription key provides a simple, opaque audit trail: every tool call in Application Insights logs includes the subscription key that authorised it.
- Product-level isolation is achievable in the current (non-Workspace) APIM model without preview dependencies.

**Negative / Risks:**
- Products are service-level resources — in a large APIM instance with many teams, the product list can grow unwieldy. Workspaces would provide better team-level isolation.
- When APIM Workspace MCP support reaches GA, migration will require: moving APIs to workspace scope, recreating products within the workspace, migrating subscriptions, and updating client configuration. This is a non-trivial migration.

**Migration path when Workspace MCP support reaches GA:**
1. Create a Workspace per team / per MCP server cluster.
2. Move APIs and products into the workspace.
3. Recreate the `mcpServers` projection at workspace scope (new resource type path expected: `Microsoft.ApiManagement/service/workspaces/mcpServers`).
4. Migrate active subscriptions.
5. Update Terraform modules to use `azurerm_api_management_workspace_*` resources.
