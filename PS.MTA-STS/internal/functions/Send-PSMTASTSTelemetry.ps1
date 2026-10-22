<#
.SYNOPSIS
    Sends a telemetry event to a configured HTTP endpoint without interrupting the main workflow.

.DESCRIPTION
    Serializes a PowerShell hashtable into JSON and POSTs it to a telemetry receiver, such as an Azure Function App.
    Telemetry should be fire-and-forget so the primary domain operation continues even if monitoring is unavailable.
    Best practice: include timestamp, tenant, resource, action, domain, result, and correlation data; keep payloads small and avoid sensitive content.

.PARAMETER TelemetryEndpoint
    The full URL of the telemetry receiver endpoint.

.PARAMETER EventType
    The type of the telemetry event, e.g., "AddDomain" or "RemoveDomain".

.PARAMETER Domain
    The domain name associated with the telemetry event.

.EXAMPLE
    Send-PSMTASTSTelemetry -TelemetryEndpoint "https://telemetry.example.azurewebsites.net/telemetry" -EventType "AddDomain" -Domain "contoso.com"

    Sends a telemetry event for the added domain contoso.com.

.EXAMPLE
    Send-PSMTASTSTelemetry -TelemetryEndpoint "https://telemetry.example.azurewebsites.net/telemetry" -EventType "RemoveDomain" -Domain "contoso.com"

    Sends a telemetry event for the removed domain contoso.com.

.LINK
    https://github.com/jklotzsche-msft/PS.MTA-STS

#>
function Send-PSMTASTSTelemetry {
    param(
        [string]$TelemetryEndpoint,  # URL of the receiver Function
        [string][validateSet("AddDomain","RemoveDomain")]$EventType,
        [string]$Domain
    )

    # Construct the payload for the telemetry event
    $Payload = @{
        eventType = $EventType
        domain = $Domain
    }
    $body = $Payload | ConvertTo-Json -Depth 3 -Compress

    # Send the telemetry event to the configured endpoint
    try {
        $null = Invoke-RestMethod -Uri $TelemetryEndpoint `
            -Method POST `
            -Headers @{ "Content-Type" = "application/json" } `
            -Body $body `
            -TimeoutSec 5 `
            -ErrorAction Stop

        return $true
    }
    catch {
        Write-Warning "Telemetry send failed for domain '$Domain' ($EventType): $($_.Exception.Message)"
        return $false
    }
}
