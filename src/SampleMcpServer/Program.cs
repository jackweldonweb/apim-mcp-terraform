// SampleMcpServer — .NET 9 MCP server using Streamable HTTP transport.
//
// Backend trust model: APIM is the only caller. APIM authenticates MCP clients
// (Entra JWT + subscription key), then forwards requests using its Managed Identity.
// This service trusts the X-APIM-Identity header injected by APIM and does NOT
// re-validate the bearer token — enforce backend isolation via Container Apps ingress
// restrictions (internal-only ingress or IP allowlist for APIM outbound IPs).
//
// Transport: Streamable HTTP (WithHttpTransport). The deprecated HTTP+SSE transport
// was removed from the MCP spec mid-2025.

using SampleMcpServer;

var builder = WebApplication.CreateBuilder(args);

// ── MCP server ────────────────────────────────────────────────────────────────

builder.Services
    .AddMcpServer()
    .WithHttpTransport()
    .WithTools<IncidentTools>();

// ── Backend HTTP client ───────────────────────────────────────────────────────

builder.Services.AddHttpClient<IncidentTools>(client =>
{
    var baseUrl = builder.Configuration["RestApi:BaseUrl"]
        ?? throw new InvalidOperationException(
            "RestApi:BaseUrl is required. Set it in appsettings.json or via environment variable RestApi__BaseUrl.");
    client.BaseAddress = new Uri(baseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
});

// ── Keep-alive ────────────────────────────────────────────────────────────────
// Azure Load Balancer drops TCP connections idle for >4 min. Register the
// keep-alive service so SSE streams survive between tool calls.

builder.Services.AddHostedService<KeepAliveService>();

// Kestrel HTTP/1.1 keep-alive timeout — set to 2 min as a belt-and-suspenders
// measure alongside the application-layer SSE pings emitted by the MCP SDK.
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(2);
});

var app = builder.Build();

// ── Request logging for APIM-forwarded identity ───────────────────────────────

app.Use(async (context, next) =>
{
    // APIM injects the authenticated caller's identity as X-APIM-Identity.
    // Log it so the MCP server has an audit trail of who is calling, even
    // though auth has already been validated by APIM upstream.
    var apimIdentity = context.Request.Headers["X-APIM-Identity"].FirstOrDefault();
    if (apimIdentity is not null)
    {
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogInformation("Request from APIM caller identity: {Identity}", apimIdentity);
    }
    await next(context);
});

// ── MCP endpoint ──────────────────────────────────────────────────────────────

app.MapMcp("/mcp");

app.Run();
