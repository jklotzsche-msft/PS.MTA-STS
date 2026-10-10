<#
.SYNOPSIS
    Sends a telemetry event to a configured HTTP endpoint without interrupting the main workflow.

.DESCRIPTION
    Serializes a PowerShell hashtable into JSON and POSTs it to a telemetry receiver, such as an Azure Function App.
    Telemetry should be fire-and-forget so the primary domain operation continues even if monitoring is unavailable.
    Best practice: include timestamp, tenant, resource, action, domain, result, and correlation data; keep payloads small and avoid sensitive content.

.PARAMETER TelemetryEndpoint
    The full URL of the telemetry receiver endpoint.

.PARAMETER Payload
    A hashtable containing the structured event data to send, such as eventType, domain, result, resourceGroup, and timestamp.

.EXAMPLE
    Send-PSMTASTSTelemetry -TelemetryEndpoint 'https://telemetry.example.azurewebsites.net/telemetry' -Payload @{
        eventType = 'AddDomain'
        domain = 'contoso.com'
        tenantid = (Get-AzContext).Tenant.Id
        PolicyMode = $PolicyMode
    }

.NOTES
    Best practice: use UTC timestamps, never throw from telemetry calls, and keep the payload lean so operational failures are not masked by monitoring issues.
#>
function Send-PSMTASTSTelemetry {
    param(
        [string]$TelemetryEndpoint,  # URL of the receiver Function
        [string][validateSet("AddDomain","RemoveDomain")]$EventType,
        [string]$Domain,
        [string]$TenantId,
        [string]$PolicyMode
    )

    # Construct the payload for the telemetry event
    $Payload = @{
        eventType = $EventType
        domain = $Domain
        tenantId = $TenantId
        policyMode = $PolicyMode
    }
    $body = $Payload | ConvertTo-Json -Depth 3 -Compress

    # Send the telemetry event to the configured endpoint
    $null = Invoke-RestMethod -Uri $TelemetryEndpoint -Method POST `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body $body `
        -ErrorAction SilentlyContinue  # never block main operation on telemetry failure
}
