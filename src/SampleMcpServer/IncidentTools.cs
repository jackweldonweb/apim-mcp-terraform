using ModelContextProtocol.Server;
using System.ComponentModel;
using System.Text;
using System.Text.Json;

namespace SampleMcpServer;

/// <summary>
/// MCP tools that wrap the SampleRestApi incident management endpoints.
/// </summary>
[McpServerToolType]
public sealed class IncidentTools(HttpClient httpClient, ILogger<IncidentTools> logger)
{
    private static readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = true };

    [McpServerTool(Name = "list_incidents")]
    [Description("List all current incidents. Returns a JSON array of incident objects including ID, title, severity, status, and timestamps.")]
    public async Task<string> ListIncidentsAsync()
    {
        logger.LogInformation("Tool: list_incidents");
        var response = await httpClient.GetAsync("/incidents");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    [McpServerTool(Name = "get_incident")]
    [Description("Get details of a specific incident by its numeric ID.")]
    public async Task<string> GetIncidentAsync(
        [Description("Numeric ID of the incident to retrieve")] int id)
    {
        logger.LogInformation("Tool: get_incident id={Id}", id);
        var response = await httpClient.GetAsync($"/incidents/{id}");
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return $"Incident {id} not found.";
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    [McpServerTool(Name = "create_incident")]
    [Description("Open a new incident. Returns the created incident with its assigned ID.")]
    public async Task<string> CreateIncidentAsync(
        [Description("Short descriptive title for the incident")] string title,
        [Description("Severity level: Low, Medium, High, or Critical")] string severity,
        [Description("Detailed description of the incident including impact and symptoms")] string description)
    {
        logger.LogInformation("Tool: create_incident title={Title} severity={Severity}", title, severity);
        var body = JsonSerializer.Serialize(new { title, severity, description });
        var content = new StringContent(body, Encoding.UTF8, "application/json");
        var response = await httpClient.PostAsync("/incidents", content);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    [McpServerTool(Name = "update_incident_status")]
    [Description("Update the status of an existing incident. Valid status values: Open, Investigating, Resolved.")]
    public async Task<string> UpdateIncidentStatusAsync(
        [Description("Numeric ID of the incident to update")] int id,
        [Description("New status value: Open, Investigating, or Resolved")] string status)
    {
        logger.LogInformation("Tool: update_incident_status id={Id} status={Status}", id, status);
        var body = JsonSerializer.Serialize(new { status });
        var content = new StringContent(body, Encoding.UTF8, "application/json");
        var response = await httpClient.PatchAsync($"/incidents/{id}/status", content);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return $"Incident {id} not found.";
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }
}
