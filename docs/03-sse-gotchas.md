# SSE and Streamable HTTP Gotchas Through APIM

A definitive checklist of everything that can silently break MCP streaming through Azure API Management. Each item is a real failure mode, not a theoretical concern.

---

## 1. `buffer-response="false"` is mandatory on `<forward-request>`

**Where:** `sse-hygiene.xml` policy fragment, `<backend>` section.

```xml
<forward-request timeout="600" buffer-response="false" fail-on-error-status-code="false" />
```

**What breaks:** If `buffer-response` is omitted or set to `true`, APIM buffers the entire backend response before forwarding it to the client. For a streaming SSE or Streamable HTTP response, "entire response" means the stream never closes — APIM waits forever, the client receives nothing, and the connection eventually times out.

This failure is silent: APIM returns HTTP 200, no error is logged, and the client just sees a hung connection.

**Why `fail-on-error-status-code="false"`:** The backend returns HTTP 200 even for tool-call errors (errors are expressed in the JSON-RPC response body). Setting this to `true` would cause APIM to treat 4xx/5xx streaming responses as policy errors and close the stream prematurely.

---

## 2. `body_bytes = 0` on all diagnostic blocks — set on the resource, not in policy

**Where:** `azurerm_api_management_diagnostic` resource in the `apim-diagnostics` module.

```hcl
frontend_request  { body_bytes = 0 }
frontend_response { body_bytes = 0 }
backend_request   { body_bytes = 0 }
backend_response  { body_bytes = 0 }
```

**What breaks:** Any non-zero `body_bytes` value causes APIM to buffer the response body to capture the configured number of bytes for logging. This buffering is applied before the response is forwarded to the client, which destroys streaming. The client connection stalls.

**Critical:** This setting is on the `azurerm_api_management_diagnostic` Terraform resource, not in policy XML. Setting it in policy (`<log-to-eventhub>`, etc.) does not help — the diagnostic framework applies buffering independently.

---

## 3. Do not read `context.Response.Body` in MCP-scoped policies

**What breaks:** Any policy expression that accesses `context.Response.Body` — including `<choose>` conditions that inspect the response, `<set-body>`, and custom logging — forces APIM to buffer the response so the policy can read it. Streaming stops.

**Safe alternatives:**
- Read `context.Request.Body` (request body is fully available before streaming begins).
- Check `context.Response.StatusCode` — this is available without buffering.
- Use Application Insights diagnostic logging with `body_bytes = 0` for response content (see item 2).
- Use Event Hub + Stream Analytics for content auditing — decouple the logging pipeline from the response path.

---

## 4. Azure Load Balancer 4-minute idle timeout

**Where:** Any long-lived SSE stream or Streamable HTTP streaming response.

**What breaks:** Azure Load Balancer terminates TCP connections that have been idle (no bytes transmitted) for more than 4 minutes. Between MCP tool calls, the SSE channel can be silent for minutes. The LB closes the connection silently — the server does not know, the client may not know immediately, and subsequent tool calls fail with a connection error.

**Solution — two layers:**

1. **Application layer (SampleMcpServer):** The `.NET MCP server must emit SSE comment pings at a regular interval. The `KeepAliveService` in `SampleMcpServer` runs every 2 minutes (well under the 4-minute cutoff). The MCP SDK's HTTP transport layer is responsible for the actual `: keep-alive\n\n` line emission.

2. **Kestrel layer:** Configure `KeepAliveTimeout` on the Kestrel server:
   ```csharp
   builder.WebHost.ConfigureKestrel(options =>
   {
       options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(2);
   });
   ```

**Note:** APIM Premium with Availability Zones or multi-region deployment may have additional LB tiers, each with their own idle timeout. The 2-minute ping interval provides margin against the most restrictive (4-minute) timeout.

---

## 5. `<validate-content>` breaks streaming

**What breaks:** The `<validate-content>` policy validates request or response body against a schema. Schema validation requires buffering the full body. Any use of `<validate-content>` on an MCP API, at any scope (global, API, operation), will buffer and destroy streaming responses.

**Mitigation:** Do not use `<validate-content>` on MCP-scoped policies. Validate request parameters (headers, query strings, path parameters) using `<validate-parameters>` if needed — parameter validation does not require body buffering.

---

## 6. `timeout="600"` on `<forward-request>`

The `timeout` attribute on `<forward-request>` defaults to 300 seconds in APIM. MCP tool calls that trigger long-running operations — file processing, multi-step orchestration, calls to slow external APIs — may take longer than 5 minutes. Setting `timeout="600"` gives a 10-minute window.

**Important:** The `timeout` on `<forward-request>` is the time APIM waits for the backend to respond. It is separate from the connection idle timeout (item 4). A long timeout here does not prevent the LB from closing an idle connection — both mechanisms operate independently.

Tune `timeout` to match your slowest expected tool execution. Do not set it higher than necessary; runaway tools will hold an APIM worker for the full timeout duration.

---

## 7. `schema_validation_enabled = false` on `azapi_resource` for preview ARM types

**Where:** `azapi_resource "mcp_server"` blocks in both Terraform modules.

```hcl
resource "azapi_resource" "mcp_server" {
  schema_validation_enabled = false  # mcpServers not in azapi 2.9.0 schema
  ...
}
```

**What breaks:** Without this flag, `terraform validate` fails because the azapi provider's embedded ARM schema does not recognise `Microsoft.ApiManagement/service/mcpServers`. The provider rejects the `body` block as an unknown property. This is a validation-time failure, not a deploy-time failure.

**Risk:** Disabling schema validation means Terraform will not catch typos in the `body` block at plan time — bad values only surface on apply. Always review the body carefully. Remove `schema_validation_enabled = false` once the resource type reaches GA and appears in the azapi provider's schema.

---

## 8. Named values must propagate before policies reference them

**Where:** `time_sleep` resource in `apim-shared-policy-fragments/main.tf`.

```hcl
resource "time_sleep" "named_values_propagation" {
  create_duration = "120s"
  triggers        = { named_values_trigger = var.named_values_propagation_trigger }
}
```

**What breaks:** APIM replicates named value changes to all gateway nodes asynchronously. If a policy fragment is deployed immediately after a named value is created or updated, gateway nodes that have not yet received the update will return errors (the `{{named-value-name}}` reference resolves to empty or an error). The 120-second sleep gives the replication time to complete.

The `triggers` block ensures the sleep only fires when named values actually change. Subsequent applies that don't touch named values skip the sleep.

---

## 9. `validate-azure-ad-token`, not `validate-jwt`

**Where:** `validate-entra-token.xml` policy fragment.

**What breaks:** `<validate-jwt>` validates token signatures against a static JWKS or symmetric key. It does not handle the Entra v2.0 multi-tenant issuer pattern where the issuer URL contains `{tenantid}` as a template. `<validate-azure-ad-token>` understands the Entra token format, handles v1.0 and v2.0 issuers correctly, and automatically refreshes the signing keys from the Entra OIDC discovery endpoint.

---

## 10. `appid` vs `azp` claim — always use `GetValueOrDefault` fallback

**Where:** `validate-entra-token.xml`, `caller-app-id` variable.

Entra tokens use different claim names for the calling application's client ID depending on the token version:
- **v1.0 tokens:** `appid`
- **v2.0 tokens:** `azp`

Policy expressions that read only `appid` or only `azp` will silently return `null` or an empty string for the wrong token version. Always chain the fallback:

```csharp
((Jwt)context.Variables["jwt"]).Claims
    .GetValueOrDefault("azp",
        ((Jwt)context.Variables["jwt"]).Claims.GetValueOrDefault("appid", "unknown"))
```

---

## 11. `&&` must be `&amp;&amp;` in policy XML attributes

**Where:** Any policy XML attribute containing a C# expression with `&&` (logical AND).

XML attribute values are parsed before the C# expression is evaluated. The `&` character in XML attributes must be escaped as `&amp;`. In attribute values, `&&` becomes `&amp;&amp;`. In element content (e.g. `<value>` body), `&&` can also appear as `&amp;&amp;` for consistency, though CDATA sections can be used as an alternative.

Similarly, `"` inside attribute-value expressions must be `&quot;`.

---

## Summary Checklist

| Item | Where to configure | Common mistake |
|------|--------------------|----------------|
| `buffer-response="false"` | `sse-hygiene.xml` `<backend>` | Omitting it (APIM default is `true`) |
| `body_bytes = 0` | `azurerm_api_management_diagnostic` Terraform resource | Setting it in policy XML instead |
| No `context.Response.Body` reads | All MCP-scoped policies | Using `<set-body>` or `<log-to-eventhub>` on the response |
| Keep-alive ping < 3 min | `KeepAliveService.cs` + Kestrel config | Not implementing it (LB silently drops after 4 min) |
| No `<validate-content>` on MCP APIs | API / Product / Operation policy | Adding it for security without knowing it buffers |
| `timeout="600"` | `sse-hygiene.xml` `<forward-request>` | Leaving default 300s for long-running tools |
| `schema_validation_enabled = false` | `azapi_resource` for mcpServers | Forgetting it → `terraform validate` fails |
| `time_sleep 120s` before policy fragments | `apim-shared-policy-fragments/main.tf` | Named values not yet replicated to all gateway nodes |
| `validate-azure-ad-token` | `validate-entra-token.xml` | Using `validate-jwt` instead |
| `GetValueOrDefault("azp", ..., "appid")` | `validate-entra-token.xml` | Reading only `azp` or only `appid` |
| `&amp;&amp;` in XML attributes | All policy XML | Using literal `&&` → XML parse error |
