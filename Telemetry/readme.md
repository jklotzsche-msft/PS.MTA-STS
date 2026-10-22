# Documentation

As a Project we don't have any idea how much this PowerShell Module is used apart from the Downloads on the PSGallery.

So we came up with an optional Telemetry Service when using 'Add-PSMTASTSCustomDomain' / 'Remove-PSMTASTSCustomDomain'.

- The customer uses the module to add or remove a custom domain.
- The module sends a small telemetry event to a Function App when using -SendTelemetry
- The Telemetry Function App stores that event in Azure Table Storage.
- The customer never directly manages this telemetry pipeline; it is an optional background service.

We would love to see how many domains are protected with our PowerShell Module 😍 so please use the -SendTelemetry parameter 👏

## Telemetry Architecture

```txt
+-----------------------------------------------------------------------+
| Customer / Admin                                                      |
|                                                                       |
|  Runs:                                                                |
|  - Add-PSMTASTSCustomDomain -DomainName contoso.com -SendTelemetry    |
|  - Remove-PSMTASTSCustomDomain -DomainName contoso.com -SendTelemetry |
|                                                                       |
|  Optional telemetry is sent only with the -SendTelemetry parameter    |
+------------------------------------+----------------------------------+
                                     |
                                     | HTTPS POST
                                     | JSON payload:
                                     | {
                                     |   "eventType": "AddDomain/RemoveDomain",
                                     |   "domain": "contoso.com"
                                     | }
                                     v
+------------------------------------+----------------------------------+
| PS.MTA-STS PowerShell Module                                          |
|                                                                       |
|  - Detects domain change operation                                    |
|  - Builds telemetry event                                             |
|  - Sends it to the telemetry endpoint                                 |
+------------------------------------+----------------------------------+
                                     |
                                     | POST to:
                                     | https://mtaststelemetry.azurewebsites.net/telemetry
                                     v
+------------------------------------+----------------------------------+
| Azure Function App (Telemetry Receiver)                               |
|                                                                       |
|  - HTTP trigger (anonymous POST)                                      |
|  - Receives event payload                                             |
|  - Writes telemetry record to storage                                 |
+------------------------------------+----------------------------------+
                                     |
                                     | Output binding
                                     v
+------------------------------------+----------------------------------+
| Azure Table Storage                                                   |
|                                                                       |
|  Table: MtaStsTelemetry                                               |
|                                                                       |
|  Record fields:                                                       |
|  - PartitionKey = Telemetry                                           |
|  - RowKey = GUID                                                      |
|  - EventType                                                          |
|  - Domain                                                             |
|  - Timestamp                                                          |
+-----------------------------------------------------------------------+
```

## Infrastructure

```pwsh
# Variables
$ResourceGroup  = "RG_MTASTSTelemetry"
$StorageAccountName = "mtaststelemetry"
$FunctionAppName = ""
$TableName = "MtaStsTelemetry"
$Location = "westeurope"

# Create Storage Account
$newAzStorageAccountProps = @{
    ResourceGroup          = $ResourceGroup
    Name                   = $StorageAccountName
    Location               = $Location
    SkuName                = 'Standard_LRS'
    AllowBlobPublicAccess  = $false
    EnableHttpsTrafficOnly = $true
    MinimumTlsVersion      = "TLS1_2"
    EnableSftp             = $false
}
$null = New-AzStorageAccount @newAzStorageAccountProps

# Create Storage Table
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccountName
$Context = $StorageAccount.Context
New-AzStorageTable -Name $TableName -Context $Context

# Create Azure Function App
$CurrentCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = 'en-US'

        $newAzFunctionAppProps = @{
            ResourceGroup              = $ResourceGroup
            Name                       = $FunctionAppName
            Runtime                    = 'PowerShell'
            StorageAccountName         = $StorageAccountName
            FunctionsVersion           = '4'
            OSType                     = 'Windows'
            RuntimeVersion             = '7.6'
            DisableApplicationInsights = $true
            Location                   = $Location
        }
New-AzFunctionApp @newAzFunctionAppProps

[System.Threading.Thread]::CurrentThread.CurrentCulture = $CurrentCulture

# Set FTP disabled
$null = Set-AzWebApp -ResourceGroup $ResourceGroup -Name $FunctionAppName -FtpsState Disabled

# Set TLS Version 1.2
$subscriptionId = (Get-AzContext).Subscription.Id
$body = @{
    properties = @{
        minTlsVersion     = "1.2"
        scmMinTlsVersion  = "1.2"
    }
} | ConvertTo-Json -Depth 3

$path = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$FunctionAppName/config/web?api-version=2026-07-15"
$null = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $body
```

## host.json

```json
{
  "version": "2.0",
  "extensions": {
    "http": {
      "routePrefix": "",
      "customHeaders": {
        "Permissions-Policy": "geolocation=()",
        "X-Frame-Options": "SAMEORIGIN",
        "Content-Security-Policy": "default-src 'self'",
        "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer"
      }
    }
  },
  "managedDependency": {
    "Enabled": false
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.0.0, 5.0.0)"
  }
}
```

## function.json

```json
{
    "data": {
        "bindings": [
            {
                "authLevel": "anonymous",
                "type": "httpTrigger",
                "direction": "in",
                "name": "Request",
                "methods": [
                    "post"
                ]
            },
            {
                "type": "http",
                "direction": "out",
                "name": "Response"
            },
            {
                "name": "MtaStsTelemetry",
                "direction": "out",
                "type": "table",
                "tableName": "MtaStsTelemetry",
                "methods": [],
                "connection": "mtaststelemetry"
            }
        ]
    }
}
```

## Function App

Function App with Azure Table Storage

```pwsh
# run.ps1 in the telemetry receiver Function
param($Request, $TriggerMetadata)

$event = $Request.Body

# Write to Azure Table Storage (see below)
Push-OutputBinding -Name MtaStsTelemetry -Value @{
    PartitionKey = "Telemetry"
    RowKey       = [System.Guid]::NewGuid().ToString()
    EventType    = $event.eventType
    Domain       = $event.domain
    Timestamp    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::Accepted
})
```

## Event Payload

Eventtype: AddDomain/RemoveDomain

```json
$Body = @"
{
    "eventType": "AddDomain",
    "domain": "contoso.com"
}
"@
$ContentType = "application/json"
Invoke-WebRequest -URI "https://mtaststelemetry.azurewebsites.net/telemetry" -Method "POST" -body $Body -ContentType $ContentType
```
