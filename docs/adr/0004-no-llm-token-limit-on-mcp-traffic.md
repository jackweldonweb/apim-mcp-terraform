# ADR 0004: No LLM Token Limit Policy on MCP Traffic

**Status:** Accepted  
**Date:** 2025-05

---

## Context

Azure API Management includes the `azure-openai-emit-token-metric` and `llm-token-limit` policy elements, which parse the `usage` block in OpenAI-compatible chat completion responses to track and limit LLM token consumption.

A natural question when building an MCP gateway is whether these policies should be applied to MCP traffic to control the downstream LLM usage that tool calls might trigger.

**`llm-token-limit` and `azure-openai-emit-token-metric` are not applicable to MCP traffic:**

- These policies inspect the HTTP response body for a JSON structure containing `usage.prompt_tokens` and `usage.completion_tokens` — the OpenAI chat completion response format.
- MCP tool call responses are JSON-RPC 2.0 `result` objects. They do not contain an OpenAI `usage` block.
- The MCP server (SampleMcpServer) calls SampleRestApi, which is a plain REST API with no LLM involvement. There are no tokens to measure.
- Even in architectures where an MCP tool internally calls an LLM, the token usage is buried inside the tool's implementation and is not surfaced in the MCP response envelope. The APIM gateway only sees the MCP JSON-RPC layer.

Furthermore, applying `azure-openai-emit-token-metric` to an MCP endpoint would fail silently — APIM would parse each response looking for an `usage` block, find nothing, and emit no metrics. There is no error, just missing data.

---

## Decision

Do not use `llm-token-limit` or `azure-openai-emit-token-metric` on any MCP API or Product policy in this reference implementation.

Instead, use request-based controls appropriate for MCP traffic:

- **`rate-limit-by-key`** (in the `rate-limit-per-subscription` fragment) — limits the number of MCP tool call requests per time window per subscription. This controls call frequency regardless of what the tool does internally.
- **`quota-by-key`** (in the `quota-per-subscription` fragment) — enforces a long-window budget cap on total tool calls per subscription.
- **`emit-metric`** (in the `emit-tool-call-metric` fragment) — emits a custom metric per tool call, keyed by subscription, caller OID, app ID, tenant, API, and operation. Azure Monitor dashboards and alerts can be built on top of this metric.

---

## Consequences

**Positive:**
- No misleading "zero token" data in Application Insights from failed `usage` block parsing.
- Request-based rate limiting and quota are well-suited to MCP's tool call model: each call is a discrete unit of work, and limiting call frequency is meaningful to operators.
- Custom metrics provide fine-grained attribution (by subscription, caller, and operation) without depending on LLM-specific response formats.

**Negative / Risks:**
- If an MCP tool internally calls an LLM and you want to track or limit those downstream token costs, you must implement that tracking inside the tool itself or the backend service — not at the APIM MCP gateway layer.
- If the architecture evolves to expose an OpenAI-compatible `/chat/completions` endpoint alongside the MCP endpoint (a common pattern for dual-protocol gateways), the LLM token policies should be applied to the chat completions API, not the MCP API. Separate APIs with separate policy scopes is the correct model.
