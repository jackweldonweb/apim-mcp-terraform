// SampleRestApi — incident/alert management REST API.
//
// No authentication on this service — APIM owns client authentication.
// Enforce backend trust via Container Apps ingress: internal-only or IP
// allowlist restricted to the APIM outbound IP range. This service should
// never be reachable directly from the public internet.

using Scalar.AspNetCore;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();
builder.Services.ConfigureHttpJsonOptions(opts =>
{
    opts.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});

var app = builder.Build();

app.MapOpenApi();

if (app.Environment.IsDevelopment())
{
    // Scalar API browser — handy for local dev and for verifying the spec
    // that APIM Pattern 1 imports via /openapi/v1.json
    app.MapScalarApiReference();
}

// ── In-memory incident store ──────────────────────────────────────────────────
// No EF Core — this is a demo backend, not a persistence showcase.

var incidents = new List<Incident>
{
    new(1, "Login service unavailable",   Severity.Critical, "Users cannot authenticate — auth service returning 503",             IncidentStatus.Open,          DateTimeOffset.UtcNow.AddHours(-2)),
    new(2, "Slow database queries",       Severity.High,     "P95 latency exceeded 2 s threshold on orders-db read replica",       IncidentStatus.Investigating,  DateTimeOffset.UtcNow.AddHours(-1)),
    new(3, "CDN cache miss spike",        Severity.Medium,   "Cache hit ratio dropped to 40 % — root cause under investigation",   IncidentStatus.Resolved,       DateTimeOffset.UtcNow.AddMinutes(-30)),
};
var idCounter = incidents.Max(i => i.Id) + 1;
var storeLock = new object();

// ── Endpoints ─────────────────────────────────────────────────────────────────

app.MapGet("/incidents", () =>
{
    lock (storeLock) { return Results.Ok(incidents.ToList()); }
})
.WithName("ListIncidents")
.WithSummary("List all incidents")
.WithDescription("Returns the full list of incidents ordered by creation time descending.");

app.MapGet("/incidents/{id:int}", (int id) =>
{
    lock (storeLock)
    {
        var incident = incidents.FirstOrDefault(i => i.Id == id);
        return incident is null ? Results.NotFound() : Results.Ok(incident);
    }
})
.WithName("GetIncident")
.WithSummary("Get a single incident by ID")
.WithDescription("Returns the incident with the given ID, or 404 if not found.");

app.MapPost("/incidents", (CreateIncidentRequest req) =>
{
    Incident incident;
    lock (storeLock)
    {
        incident = new Incident(idCounter++, req.Title, req.Severity, req.Description,
            IncidentStatus.Open, DateTimeOffset.UtcNow);
        incidents.Add(incident);
    }
    return Results.Created($"/incidents/{incident.Id}", incident);
})
.WithName("CreateIncident")
.WithSummary("Create a new incident")
.WithDescription("Opens a new incident with status Open. Returns the created incident including its assigned ID.");

app.MapMethods("/incidents/{id:int}/status", ["PATCH"], (int id, UpdateStatusRequest req) =>
{
    lock (storeLock)
    {
        var index = incidents.FindIndex(i => i.Id == id);
        if (index < 0) return Results.NotFound();
        incidents[index] = incidents[index] with
        {
            Status    = req.Status,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        return Results.Ok(incidents[index]);
    }
})
.WithName("UpdateIncidentStatus")
.WithSummary("Update the status of an incident")
.WithDescription("Transitions an incident to a new status. Valid values: Open, Investigating, Resolved.");

app.Run();

// ── Domain types ──────────────────────────────────────────────────────────────

record Incident(
    int              Id,
    string           Title,
    Severity         Severity,
    string           Description,
    IncidentStatus   Status,
    DateTimeOffset   CreatedAt,
    DateTimeOffset?  UpdatedAt = null);

record CreateIncidentRequest(
    string   Title,
    Severity Severity,
    string   Description);

record UpdateStatusRequest(IncidentStatus Status);

enum Severity       { Low, Medium, High, Critical }
enum IncidentStatus { Open, Investigating, Resolved }
