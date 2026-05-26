namespace SampleMcpServer;

/// <summary>
/// Sends periodic keep-alive pings to prevent Azure Load Balancer from closing
/// idle connections on long-running SSE streams.
///
/// Azure Load Balancer terminates TCP connections that have been idle for 4 minutes.
/// The MCP Streamable HTTP transport holds a persistent SSE channel for server-to-client
/// events. Between tool calls the channel can be idle for minutes, triggering the cutoff.
///
/// This service fires every 2 minutes — well under the 4-minute idle threshold.
/// The actual SSE keep-alive comment (": keep-alive\n\n") is emitted by the MCP SDK's
/// HTTP transport layer; this service exists as a monitoring hook and a place to add
/// application-level logic (e.g. metrics, circuit breaking) if needed.
/// </summary>
public sealed class KeepAliveService(ILogger<KeepAliveService> logger) : BackgroundService
{
    // Must be less than Azure LB idle timeout (4 min). 2 min gives comfortable margin.
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(2);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("MCP keep-alive service started — interval {Interval}", Interval);

        using var timer = new PeriodicTimer(Interval);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            logger.LogDebug("MCP keep-alive tick");
        }
    }
}
