// SampleAgentClient — proves E2E connectivity through the APIM MCP gateway.
//
// Usage:
//   dotnet run -- --pattern rest-as-mcp
//   dotnet run -- --pattern existing-mcp
//
// Required environment variables:
//   APIM_GATEWAY_URL        Base URL of the APIM gateway (e.g. https://my-apim.azure-api.net)
//   APIM_BEARER_TOKEN       Entra bearer token — audience must match the APIM gateway audience
//   APIM_SUBSCRIPTION_KEY   APIM product subscription key
//
// Optional:
//   APIM_MCP_PATH_REST      MCP path for Pattern 1 (default: /sample-rest-api/mcp)
//   APIM_MCP_PATH_EXISTING  MCP path for Pattern 2 (default: /sample-mcp-server/mcp)

using System.Net.Http.Headers;
using ModelContextProtocol;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

const string Usage = "Usage: dotnet run -- --pattern <rest-as-mcp|existing-mcp>";

// ── Parse args ────────────────────────────────────────────────────────────────

if (args.Length < 2 || args[0] != "--pattern")
{
    Console.Error.WriteLine(Usage);
    return 1;
}

string pattern = args[1] switch
{
    "rest-as-mcp"  => "rest-as-mcp",
    "existing-mcp" => "existing-mcp",
    _              => null!,
};

if (pattern is null)
{
    Console.Error.WriteLine($"Unknown pattern '{args[1]}'. {Usage}");
    return 1;
}

// ── Read config from environment ──────────────────────────────────────────────

var gatewayUrl      = RequireEnv("APIM_GATEWAY_URL");
var bearerToken     = RequireEnv("APIM_BEARER_TOKEN");
var subscriptionKey = RequireEnv("APIM_SUBSCRIPTION_KEY");

var mcpPath = pattern == "rest-as-mcp"
    ? (Environment.GetEnvironmentVariable("APIM_MCP_PATH_REST")     ?? "/sample-rest-api/mcp")
    : (Environment.GetEnvironmentVariable("APIM_MCP_PATH_EXISTING") ?? "/sample-mcp-server/mcp");

var mcpEndpoint = new Uri(gatewayUrl.TrimEnd('/') + mcpPath);

Console.WriteLine($"Pattern  : {pattern}");
Console.WriteLine($"Endpoint : {mcpEndpoint}");
Console.WriteLine();

// ── Build HTTP client with APIM auth headers ──────────────────────────────────

var httpClient = new HttpClient();
httpClient.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", bearerToken);
httpClient.DefaultRequestHeaders.Add("Ocp-Apim-Subscription-Key", subscriptionKey);

// ── Connect to APIM MCP gateway ───────────────────────────────────────────────

var transportOptions = new HttpClientTransportOptions
{
    Endpoint      = mcpEndpoint,
    Name          = $"apim-{pattern}",
};

var clientOptions = new McpClientOptions
{
    ClientInfo = new Implementation { Name = "SampleAgentClient", Version = "1.0.0" },
};

Console.WriteLine("Connecting to MCP gateway...");

await using var mcpClient = await McpClient.CreateAsync(
    new HttpClientTransport(transportOptions, httpClient),
    clientOptions);

Console.WriteLine("Connected.\n");

// ── List available tools ──────────────────────────────────────────────────────

Console.WriteLine("=== Available Tools ===");
var tools = await mcpClient.ListToolsAsync((RequestOptions?)null);
foreach (var tool in tools)
{
    Console.WriteLine($"  {tool.Name,-32} {tool.Description}");
}
Console.WriteLine();

// ── Exercise all four tools ───────────────────────────────────────────────────
// Sequence: list → get → create → update status

Console.WriteLine("=== Tool Sequence ===\n");

// 1. List incidents
await CallTool(mcpClient, "list_incidents",
    new Dictionary<string, object?>(),
    "Listing all incidents");

// 2. Get incident #1
await CallTool(mcpClient, "get_incident",
    new Dictionary<string, object?> { ["id"] = 1 },
    "Fetching incident #1");

// 3. Create a new incident
await CallTool(mcpClient, "create_incident",
    new Dictionary<string, object?>
    {
        ["title"]       = "Elevated API error rate",
        ["severity"]    = "High",
        ["description"] = "5xx responses from payment-service increased to 8% over the last 5 minutes.",
    },
    "Creating a new incident");

// 4. Update incident #1 to Resolved
await CallTool(mcpClient, "update_incident_status",
    new Dictionary<string, object?> { ["id"] = 1, ["status"] = "Resolved" },
    "Resolving incident #1");

Console.WriteLine("\nDone.");
return 0;

// ── Helpers ───────────────────────────────────────────────────────────────────

static async Task CallTool(
    McpClient client,
    string toolName,
    Dictionary<string, object?> arguments,
    string label)
{
    Console.WriteLine($">> {label}");
    var result = await client.CallToolAsync(toolName, arguments);

    if (result.IsError == true)
    {
        var errorText = result.Content.OfType<TextContentBlock>().FirstOrDefault()?.Text ?? "(no error detail)";
        Console.WriteLine($"   ERROR: {errorText}");
    }
    else
    {
        var text = result.Content.OfType<TextContentBlock>().FirstOrDefault()?.Text ?? "(no content)";
        try
        {
            var parsed = System.Text.Json.JsonDocument.Parse(text);
            Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(
                parsed, new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            Console.WriteLine($"   {text}");
        }
    }
    Console.WriteLine();
}

static string RequireEnv(string name)
{
    var value = Environment.GetEnvironmentVariable(name);
    if (string.IsNullOrWhiteSpace(value))
        throw new InvalidOperationException($"Required environment variable '{name}' is not set.");
    return value;
}
