# Documentation

Ideas about how to implement a Telemetry Function

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


# Set TLS Version 1.3
$subscriptionId = (Get-AzContext).Subscription.Id
$body = @{
    properties = @{
        minTlsVersion     = "1.3"
        scmMinTlsVersion  = "1.3"
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
