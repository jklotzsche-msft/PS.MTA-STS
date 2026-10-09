# Documentation

Ideas about how to implement a Telemetry Function

## Event Payload

```json
{
    "eventType": "DomainAdded/DomainRemoved",
    "timestamp": "2026-10-09T10:00:00Z",
    "tenantId": "<AAD Tenant ID>",
    "domain": "contoso.com",
    "policyMode": "Enforce",
    "errorMessage": null
}
```

## Function App

Function App with Azure Table Storage

```pwsh
# run.ps1 in the telemetry receiver Function
param($Request, $TriggerMetadata)

$event = $Request.Body
$event.receivedAt = (Get-Date -Format "o")

# Write to Azure Table Storage (see below)
Push-OutputBinding -Name tableOutput -Value @{
    PartitionKey = $event.tenantId
    RowKey       = [System.Guid]::NewGuid().ToString()
    EventType    = $event.eventType
    TenantId     = $event.tenantId
    Domain       = $event.domain
    Timestamp    = $event.timestamp
    PolicyMode   = $event.policyMode
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::Accepted
})
```

## Function Json

```json
{
  "bindings": [
    { "type": "httpTrigger", "direction": "in", "name": "Request", "authLevel": "function" },
    { "type": "http",         "direction": "out","name": "Response" },
    {
      "type": "table", "direction": "out", "name": "tableOutput",
      "tableName": "MtaStsTelemetry",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
```