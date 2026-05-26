# apim-mcp-reference

Production-ready reference implementation for exposing REST APIs as MCP servers through Azure API Management.  Demonstrates two complementary patterns side by side, with full Entra JWT validation, rate limiting, quota enforcement, custom metrics, and structured error handling.

> **Target audience:** Enterprise Azure architects evaluating MCP gateway patterns on existing APIM Premium instances.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  MCP Client (SampleAgentClient)                                  │
│  • Entra JWT (aud = mcp-gateway-audience)                        │
│  • Ocp-Apim-Subscription-Key                                     │
└────────────────────────┬─────────────────────────────────────────┘
                         │ HTTPS / Streamable HTTP
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  Azure API Management (Premium)                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Shared policy fragments                                   │  │
│  │  • validate-entra-token  (inbound)                         │  │
│  │  • rate-limit-per-subscription  (inbound)                  │  │
│  │  • quota-per-subscription  (inbound)                       │  │
│  │  • emit-tool-call-metric  (inbound)                        │  │
│  │  • sse-hygiene  (backend — buffer-response=false)          │  │
│  │  • mcp-error-handling  (on-error — JSON-RPC shaped)        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Pattern 1: REST-as-MCP          Pattern 2: Governed MCP server  │
│  APIM synthesises MCP from       APIM governs an existing .NET   │
│  a managed REST API.             MCP server.                     │
│  No custom server code.          Credential abstraction.         │
└────────┬─────────────────────────────────┬────────────────────────┘
         │ Managed Identity                │ Managed Identity
         ▼                                 ▼
┌──────────────────┐             ┌──────────────────────────────┐
│  SampleRestApi   │             │  SampleMcpServer             │
│  .NET 9 REST API │◄────────────│  .NET 9, MCP StreamableHttp  │
│  (ACA)           │             │  (ACA)                       │
└──────────────────┘             └──────────────────────────────┘
```

### Transport

Streamable HTTP is the default transport.  The HTTP+SSE transport was deprecated in the MCP specification in mid-2025 and should not be used for new deployments.

### Authorisation unit

Each MCP server is one APIM **Product**.  Callers present a product subscription key (`Ocp-Apim-Subscription-Key`) alongside their Entra JWT.

> **Note — APIM Workspaces:** Workspaces do not yet support MCP.  Until MCP support reaches GA in Workspaces, Products are the correct unit of authorisation and isolation.

---

## Trust boundaries

| Boundary | Mechanism |
|---|---|
| Client → APIM | Entra JWT (audience-pinned) + product subscription key |
| APIM → SampleRestApi | Managed Identity token |
| APIM → SampleMcpServer | Managed Identity token (credential abstraction — client never sees this) |
| Backend ingress | Private endpoint or IP allowlist — accepts traffic from APIM only |

---

## Repository structure

```
apim-mcp/
├── infra/terraform/
│   ├── providers.tf              # azurerm >= 4.0, azapi, time
│   ├── main.tf                   # Named values + module composition
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── apim-shared-policy-fragments/
│       │   ├── main.tf           # azurerm_api_management_policy_fragment × 6
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── policies/
│       │       ├── validate-entra-token.xml
│       │       ├── sse-hygiene.xml
│       │       ├── rate-limit-per-subscription.xml
│       │       ├── quota-per-subscription.xml
│       │       ├── emit-tool-call-metric.xml
│       │       └── mcp-error-handling.xml
│       ├── apim-rest-as-mcp/     # Pattern 1
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── apim-govern-mcp-server/  # Pattern 2
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
└── src/
    ├── apim-mcp.sln
    ├── SampleRestApi/            # .NET 9 incident management REST API
    ├── SampleMcpServer/          # .NET 9 MCP server (StreamableHttp)
    └── SampleAgentClient/        # .NET 9 E2E proof through APIM gateway
```

---

## Prerequisites

- Azure subscription with an existing **APIM Premium** instance
  - Consumption tier is incompatible — MCP requires long-running connections
- Terraform >= 1.7
- Azure CLI authenticated (`az login`)
- .NET 9 SDK (for `src/` projects)

---

## Quickstart

### 1. Configure named values

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in:

```hcl
api_management_name   = "my-apim"
resource_group_name   = "my-rg"
tenant_id             = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
mcp_gateway_audience  = "api://my-mcp-gateway"
sample_rest_api_url   = "https://sample-rest-api.myaca.azurecontainerapps.io"
sample_mcp_server_url = "https://sample-mcp-server.myaca.azurecontainerapps.io"
```

### 2. Deploy infrastructure

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

> Named value propagation: Terraform applies a 120 s sleep after creating named values before activating policy fragments.  This is intentional — do not remove it.

### 3. Run the E2E proof

```bash
cd src
dotnet run --project SampleRestApi &
dotnet run --project SampleMcpServer &
dotnet run --project SampleAgentClient
```

---

## Policy fragments

| Fragment | Section | Purpose |
|---|---|---|
| `validate-entra-token` | inbound | Validates Entra JWT; sets `caller-object-id`, `caller-tenant-id`, `caller-app-id` context variables |
| `rate-limit-per-subscription` | inbound | Short-window burst control; key precedence: sub key → OID → IP |
| `quota-per-subscription` | inbound | Long-window budget cap; replicated across regions in multi-region Premium |
| `emit-tool-call-metric` | inbound | Custom Azure Monitor metric per tool call with caller dimensions |
| `sse-hygiene` | backend | `forward-request` with `buffer-response="false"` — mandatory for SSE/StreamableHttp |
| `mcp-error-handling` | on-error | JSON-RPC 2.0 shaped errors; includes `WWW-Authenticate: Bearer resource_metadata=...` on 401 |

### Fragment ordering (inbound)

```
base → validate-entra-token → rate-limit-per-subscription → quota-per-subscription → emit-tool-call-metric
```

`validate-entra-token` must run first — subsequent fragments read `caller-object-id` and `caller-app-id` from context variables it sets.

---

## Key gotchas

| Gotcha | Impact |
|---|---|
| `buffer-response="false"` is missing | SSE stream is buffered and held until the backend closes; the MCP client hangs |
| `validate-jwt` used instead of `validate-azure-ad-token` | v2.0 tokens from multi-tenant apps fail issuer validation |
| `appid`/`azp` claim not handled with fallback | App-only (v1.0) or delegated (v2.0) tokens fail caller-app-id resolution |
| `&&` written as `&&` in policy XML | XML parse error at deploy time |
| Named values applied before time_sleep | Policy activation fails with "named value not found" on first deploy |
| `context.Response.Body` read in MCP-scoped policy | Triggers response buffering; breaks streaming |
| Rate limit counters misread as global | `rate-limit-by-key` is per-region in multi-region Premium; use `quota-by-key` for global budgets |

---

## Named values reference

| Named value | Type | Description |
|---|---|---|
| `mcp-gateway-tenant-id` | Direct | Azure AD tenant ID |
| `mcp-gateway-audience` | Direct | Token audience (app URI or client ID) |
| `mcp-required-scope` | Direct | Scope callers must present |
| `mcp-rate-limit-calls` | Direct (int) | Call budget per rate-limit window |
| `mcp-rate-limit-period-seconds` | Direct (int) | Rate-limit window in seconds |
| `mcp-quota-calls` | Direct (int) | Long-window call budget |
| `mcp-quota-period-seconds` | Direct (int) | Quota window in seconds |

For production deployments, migrate `mcp-gateway-tenant-id` and `mcp-gateway-audience` to Key Vault-backed named values.

---

## Enterprise adaptation guide

### Multi-region Premium

- Increase `time_sleep.named_values_propagation.create_duration` to `"180s"`.
- `rate-limit-by-key` counters are **per-region** — each region enforces the full limit independently.  Use `quota-by-key` for aggregate cross-region budgets.

### Credential abstraction for Pattern 2

The `apim-govern-mcp-server` module uses a named value placeholder `{{mcp-backend-mi-token}}` for the backend Authorization header.  Replace this with an `authentication-managed-identity` policy block and set the backend resource URI to the SampleMcpServer's Entra app registration.

### Multiple MCP servers

Deploy one `apim-rest-as-mcp` or `apim-govern-mcp-server` module call per server.  Each gets its own APIM Product, API, and policy set.  The shared fragments are deployed once and referenced by all.

### MCP dynamic discovery (OAuth 2.0)

The `mcp-error-handling` fragment returns `WWW-Authenticate: Bearer resource_metadata="https://{host}/.well-known/oauth-protected-resource"` on 401 responses.  Configure the `/.well-known/oauth-protected-resource` endpoint on your APIM custom domain (or a redirect) to return an [RFC 9728](https://datatracker.ietf.org/doc/html/rfc9728) protected resource metadata document pointing to your Entra authorization server.

### MCP control plane (azapi)

There is no native `azurerm_api_management_mcp_server` resource in azurerm as of azurerm 4.x.  Both pattern modules include a commented `azapi_resource` block for registering MCP servers via the APIM REST API (`Microsoft.ApiManagement/service/mcpServers`).  Uncomment and configure when the API version stabilises or when azurerm adds native support.
