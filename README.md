# apim-mcp-reference

Production-ready reference implementation for exposing REST APIs and existing MCP servers through Azure API Management as governed Model Context Protocol endpoints. Built for enterprise architects who need Entra authentication, rate limiting, quota, credential abstraction, and streaming-safe diagnostics — without writing custom MCP server code for every backend.

---

## The Problem

MCP clients (AI agents, copilots, IDE extensions) need to call tools on your backend services. You want:

- **Centralised auth** — clients authenticate once at the gateway, not per-backend.
- **Credential abstraction** — clients never hold backend API keys or service credentials.
- **Rate limiting and quota** — per-subscription, independently tunable per MCP server.
- **Observability** — structured tool call metrics and logs without touching backend code.
- **Streaming integrity** — SSE and Streamable HTTP streams must not be buffered or broken by the gateway.

APIM Premium provides all of this. The non-obvious part is the configuration — a handful of settings in the wrong place silently breaks streaming forever. This reference implementation gets them right.

---

## Two Patterns

```
Pattern 1: REST-as-MCP
─────────────────────
MCP Client ──► APIM ──► (synthesises MCP) ──► SampleRestApi
              │
              └── imports OpenAPI spec, generates tool manifest,
                  marshals JSON-RPC tool calls to REST operations

Pattern 2: Govern Existing MCP Server
──────────────────────────────────────
MCP Client ──► APIM ──► SampleMcpServer (.NET 9) ──► SampleRestApi
              │          (Streamable HTTP, MCP-native)
              │
              └── adds Entra auth, rate limiting, quota, metrics
                  without changing MCP server source code
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure API Management (Premium)                    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Policy Pipeline (all requests)                               │   │
│  │  validate-entra-token → rate-limit → quota → emit-metric     │   │
│  │  → [pattern-specific backend auth] → sse-hygiene             │   │
│  │  on-error: mcp-error-handling                                │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  Pattern 1 Product          Pattern 2 Product                        │
│  sample-rest-api            sample-mcp-server                        │
│       │                          │                                   │
│       ▼                          ▼                                   │
│  API: sample-rest-api       API: sample-mcp-server                   │
│  (OpenAPI import)           (pass-through)                           │
│       │                          │                                   │
│       │ KV-backed named value    │ Managed Identity token            │
│       ▼                          ▼                                   │
└───────┼──────────────────────────┼───────────────────────────────────┘
        │                          │
        ▼                          ▼
  SampleRestApi            SampleMcpServer (.NET 9)
  (Container Apps)          (Container Apps)
                                   │
                                   ▼
                             SampleRestApi
                             (Container Apps)
```

---

## Trust Boundaries

| Boundary | Mechanism | Notes |
|----------|-----------|-------|
| MCP Client → APIM | Entra JWT (audience-pinned) + APIM subscription key | Both required. JWT validates identity and scope; subscription key gates product access. |
| APIM → SampleRestApi (Pattern 1) | Key Vault-backed named value injected as header | Client never sees the backend API key. Rotated in Key Vault without Terraform apply. |
| APIM → SampleMcpServer (Pattern 2) | APIM-acquired Managed Identity token | APIM system identity acquires a token for the backend app registration. Backend validates it. |
| SampleMcpServer → SampleRestApi | Direct HTTP (internal Container Apps network) | No auth — enforced via private/internal ingress, not credentials. |
| Backend isolation | Container Apps ingress restrictions | Both backends must accept connections from APIM only (IP allowlist or internal ingress). |

---

## Limitations

| Limitation | Detail |
|------------|--------|
| APIM Workspaces do not support MCP | The `mcpServers` resource is a service-level resource only. Products are used as the isolation boundary. See [ADR 0003](docs/adr/0003-product-as-authorisation-unit.md). |
| Consumption tier incompatible | MCP requires long-running connections. Consumption tier has a 30-second request timeout and no persistent connection support. |
| `azapi_resource` for mcpServers disabled by default | `count = 0` in both modules. Set to `1` after verifying your APIM instance's API version supports the `2025-05-01-preview` resource type. See [ADR 0002](docs/adr/0002-azapi-for-mcp-control-plane.md). |
| `schema_validation_enabled = false` on azapi mcpServers | The resource type is not yet in the azapi 2.9.0 embedded schema. Remove this flag when the resource reaches GA. |
| Keep-alive required | Azure Load Balancer drops idle TCP connections after 4 minutes. SampleMcpServer's `KeepAliveService` pings every 2 minutes. See [docs/03-sse-gotchas.md](docs/03-sse-gotchas.md#4-azure-load-balancer-4-minute-idle-timeout). |

---

## Prerequisites

- Azure subscription with an existing APIM **Premium** instance
- Terraform >= 1.7
- .NET 9 SDK
- Azure CLI (for initial auth: `az login`)
- Key Vault with a secret for the SampleRestApi backend credential (Pattern 1)
- Entra app registration for the APIM gateway audience
- Entra app registration for the SampleMcpServer backend (Pattern 2)

---

## Quick Start

### 1. Infrastructure

```bash
cd infra/terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in your APIM name, resource group, Key Vault IDs, etc.

terraform init \
  -backend-config="storage_account_name=<sa>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=apim-mcp/dev/terraform.tfstate" \
  -backend-config="resource_group_name=<rg>"

terraform plan
terraform apply
```

### 2. SampleRestApi

```bash
cd src/SampleRestApi
dotnet run
# API available at https://localhost:7xxx
# OpenAPI spec at https://localhost:7xxx/openapi/v1.json
# Scalar UI at https://localhost:7xxx/scalar
```

### 3. SampleMcpServer

```bash
cd src/SampleMcpServer
export RestApi__BaseUrl=https://localhost:7xxx
dotnet run
# MCP endpoint at http://localhost:5xxx/mcp
```

### 4. SampleAgentClient

```bash
cd src/SampleAgentClient
export APIM_GATEWAY_URL=https://my-apim.azure-api.net
export APIM_BEARER_TOKEN=<entra-bearer-token>
export APIM_SUBSCRIPTION_KEY=<product-subscription-key>

dotnet run -- --pattern rest-as-mcp
dotnet run -- --pattern existing-mcp
```

---

## Repository Structure

```
apim-mcp/
├── infra/terraform/
│   ├── modules/
│   │   ├── apim-shared-policy-fragments/  # 6 policy fragments, time_sleep propagation
│   │   ├── apim-diagnostics/              # App Insights + Azure Monitor, body_bytes=0
│   │   ├── apim-mcp-from-rest/            # Pattern 1: REST-as-MCP
│   │   └── apim-mcp-from-existing/        # Pattern 2: Govern existing MCP server
│   └── envs/dev/                          # Root module — wires everything together
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf                   # use_oidc = true for CI/CD
│       ├── backend.tf                     # Azure Blob Storage remote state
│       └── terraform.tfvars.example
├── src/
│   ├── SampleRestApi/                     # .NET 9 minimal API — incident management
│   ├── SampleMcpServer/                   # .NET 9 MCP server — wraps SampleRestApi
│   └── SampleAgentClient/                 # .NET 9 console — proves E2E via APIM
├── docs/
│   ├── adr/                               # Architecture Decision Records
│   └── 03-sse-gotchas.md                  # SSE/Streamable HTTP failure mode checklist
└── .github/workflows/
    ├── terraform-validate.yml             # PR: fmt check + validate all modules
    └── dotnet-build.yml                   # PR: build all .NET projects
```

---

## Policy Fragments

Six shared fragments are deployed by the `apim-shared-policy-fragments` module and included in every MCP API policy via `<include-fragment />`. Order within `<inbound>` is significant.

| Fragment | Section | Purpose |
|----------|---------|---------|
| `validate-entra-token` | `<inbound>` | Validates Entra JWT (v1/v2 issuers). Sets `caller-object-id`, `caller-app-id`, `caller-tenant-id` context variables. |
| `rate-limit-per-subscription` | `<inbound>` | `rate-limit-by-key` per subscription key. Sets `X-RateLimit-*` response headers. |
| `quota-per-subscription` | `<inbound>` | `quota-by-key` per subscription key. Long-window budget cap. |
| `emit-tool-call-metric` | `<inbound>` | Emits `mcp-tool-call` custom metric with caller dimensions. |
| `sse-hygiene` | `<backend>` | `<forward-request buffer-response="false" timeout="600" />`. Mandatory for streaming. |
| `mcp-error-handling` | `<on-error>` | JSON-RPC 2.0 error envelope. `WWW-Authenticate` with `resource_metadata` on 401 for MCP OAuth discovery. |

---

## Named Values

All named values are created by the `envs/dev` root module. Policy fragments reference them by name.

| Named Value | Type | Used By |
|-------------|------|---------|
| `mcp-gateway-tenant-id` | Direct | `validate-entra-token` |
| `mcp-gateway-audience` | Direct | `validate-entra-token` |
| `mcp-required-scope` | Direct | `validate-entra-token` |
| `mcp-rate-limit-calls` | Direct | `rate-limit-per-subscription` |
| `mcp-rate-limit-period-seconds` | Direct | `rate-limit-per-subscription` |
| `mcp-quota-calls` | Direct | `quota-per-subscription` |
| `mcp-quota-period-seconds` | Direct | `quota-per-subscription` |
| `{api-name}-backend-credential` | KV-backed, secret | Pattern 1 only |

---

## Architecture Decision Records

- [ADR 0001 — Streamable HTTP as default transport](docs/adr/0001-streamable-http-default.md)
- [ADR 0002 — azapi for MCP control plane resources](docs/adr/0002-azapi-for-mcp-control-plane.md)
- [ADR 0003 — APIM Product as MCP server authorisation unit](docs/adr/0003-product-as-authorisation-unit.md)
- [ADR 0004 — No LLM token limit on MCP traffic](docs/adr/0004-no-llm-token-limit-on-mcp-traffic.md)

---

## Enterprise Adaptation Guide

| Requirement | Adaptation |
|-------------|-----------|
| **Multiple MCP servers** | Add one `module "..."` block in `envs/dev/main.tf` per server, pointing to `apim-mcp-from-rest` or `apim-mcp-from-existing`. Each gets its own Product and subscription key space. |
| **Tighter rate limits for production** | Override `rate_limit_calls`, `rate_limit_period_seconds`, `quota_calls`, `quota_period_seconds` in `terraform.tfvars` per environment. |
| **Per-API rate limits** | Move the rate-limit fragment invocation from the shared module into the per-API policy and add API-specific named values for the thresholds. |
| **Multi-region APIM** | `rate-limit-by-key` counters are per-region. Use `quota-by-key` (cross-region replication) for hard global budgets. See [ADR 0004](docs/adr/0004-no-llm-token-limit-on-mcp-traffic.md). |
| **Private connectivity** | Add a private endpoint for APIM and configure Container Apps internal ingress. The Terraform modules are not opinionated about network topology. |
| **Workspace migration** | When APIM Workspace MCP support reaches GA, see [ADR 0003](docs/adr/0003-product-as-authorisation-unit.md) for the migration path. |
| **Content auditing** | Route responses to Event Hub via `<log-to-eventhub>` with a separate logger. Do not increase `body_bytes` on the Application Insights diagnostic — this breaks streaming. |
| **Custom tool credentials** | Add KV-backed named values for per-tool credentials. Inject them in the API policy using the same `{{named-value-name}}` pattern as Pattern 1. |
