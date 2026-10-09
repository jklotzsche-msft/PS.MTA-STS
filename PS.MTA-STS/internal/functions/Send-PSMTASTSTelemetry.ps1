function Send-PSMTASTSTelemetry {
    param(
        [string]$TelemetryEndpoint,  # URL of the receiver Function
        [hashtable]$Payload
    )
    $body = $Payload | ConvertTo-Json -Depth 3 -Compress
    $null = Invoke-RestMethod -Uri $TelemetryEndpoint -Method POST `
        -Headers @{ "Content-Type" = "application/json" } `
        -Body $body `
        -ErrorAction SilentlyContinue  # never block main operation on telemetry failure
}