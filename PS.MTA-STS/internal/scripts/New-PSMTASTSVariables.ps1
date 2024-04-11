$script:PSMTASTS_hostJson = @'
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
        "version": "[3.*, 4.0.0)"
    }
}
'@

$script:PSMTASTS_profilePs1 = @'
# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution
# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.

#if ($env:MSI_SECRET -and (Get-Module -ListAvailable Az.Accounts)) {
# Write-Host "Connecting to Azure"
# Connect-AzAccount -Identity
#}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias
# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
'@

$script:PSMTASTS_requirementsPsd1 = @'
# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{

}
'@

#Root Function Json
$script:Root_functionJson = @'
{
    "bindings": [
        {
            "route": "/",
            "authLevel": "ANONYMOUS",
            "methods": [
                "get"
            ],
            "type": "httpTrigger",
            "direction": "in",
            "name": "Request"
        },
        {
            "type": "http",
            "direction": "out",
            "name": "Response"
        }
    ]
}
'@

#Root Script
$script:Root_runPs1 = @'
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "Trigger: Static website index has been requested."

# Create HTML
$staticWebsiteIndex = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>MTA-STS</title>
</head>
<body>
    <hl>MTA-STS Static Website Index</hl>
    <p>Looking for the <a href="./.well-known/mta-sts.txt">mta-sts.txt</a>?</p>
</body>
</html>
"@

# Return the response
try {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Headers = @{
            "content-type" = "text/html"
        }
        Body = $staticWebsiteIndex
    })
}
catch {
 # Return error, if something went wrong
 Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Headers = @{
            "Content-type" = "text/plain"
        }
        Body = $_.Exception.Message
    })
}
'@

#MTA-STS Poliy Function JSON
$script:PSMTASTS_functionJson = @'
{
    "bindings": [
        {
            "route": ".well-known/mta-sts.txt",
            "authLevel": "anonymous",
            "methods": [
                "get"
            ],
            "type": "httpTrigger",
            "direction": "in",
            "name": "Request"
        },
        {
            "type": "http",
            "direction": "out",
            "name": "Response"
        }
    ]
}
'@

#MTA-STS Poliy Script
$script:PSMTASTS_runPs1 = @'
param ($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "Trigger: MTA-STS policy has been requested."

# Prepare the response body
## Replace 'enforce' with 'testing' to test the policy without enforcing it
## Or use the "Update-PSMTASTSFunctionAppDeployment" function to update the policy and other function app files to the current version
$mtaStsPolicy = @"
version: STSv1
mode: enforce
mx: *.mail.protection.outlook.com
max_age: 604800
"@

# Return the response
try {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Headers = @{
            "Content-type" = "text/plain"
        }
        Body = $mtaStsPolicy
    })
}
catch {
 # Return error, if something went wrong
 Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Headers = @{
            "Content-type" = "text/plain"
        }
        Body = $_.Exception.Message
    })
}
'@