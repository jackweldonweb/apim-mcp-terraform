# ADR 0001: Streamable HTTP as Default MCP Transport

**Status:** Accepted  
**Date:** 2025-05

---

## Context

The Model Context Protocol supports two HTTP-based transports:

1. **HTTP+SSE** — client connects to a persistent SSE endpoint for server-to-client events; sends requests via HTTP POST to a separate messages endpoint.
2. **Streamable HTTP** — a single endpoint handles both directions; the server responds to POST requests with either a direct JSON response or an SSE stream depending on the operation.

The MCP specification formally deprecated HTTP+SSE in May 2025. Clients and servers that only implement HTTP+SSE will not interoperate with the ecosystem going forward.

Azure Load Balancer terminates idle TCP connections after 4 minutes. With HTTP+SSE, the SSE connection is persistent by definition — any client that goes quiet for more than 4 minutes without application-layer keep-alive loses its session silently. With Streamable HTTP, each POST request creates a fresh HTTP connection, so the 4-minute constraint applies differently: it only affects long-running streaming responses.

---

## Decision

Use Streamable HTTP as the default transport for all components in this reference implementation:

- SampleMcpServer calls `WithHttpTransport()` in `Program.cs`, which registers the Streamable HTTP transport handler.
- The `azapi_resource` blocks in both Terraform modules set `transportType = "streamableHTTP"`.
- The `sse-hygiene` policy fragment sets `buffer-response="false"` on `forward-request`, which is required for both transports but is especially critical for the streaming path in Streamable HTTP.

HTTP+SSE is not implemented and not documented as a valid configuration for this repository.

---

## Consequences

**Positive:**
- Aligned with the current MCP specification; no migration needed when HTTP+SSE support is removed from SDKs.
- Simpler client connectivity model — a single HTTPS endpoint replaces the SSE + messages endpoint pair.
- APIM routing is straightforward: a single API path handles all MCP traffic.

**Negative / Risks:**
- Some early MCP client libraries (pre-May 2025) only implement HTTP+SSE. These clients will not connect.
- The keep-alive concern does not disappear: long streaming responses (e.g. a tool call that produces a large SSE event stream) still require `buffer-response="false"` in the APIM policy and a ping interval in the .NET server to survive the Azure LB 4-minute idle cutoff.
- `transportType = "streamableHTTP"` in the azapi resource uses a preview API version (`2025-05-01-preview`). The value may change when the resource reaches GA in the Azure API surface.
