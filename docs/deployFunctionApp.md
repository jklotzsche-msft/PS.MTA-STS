# Deploy MTA-STS using a Azure Function App

This guide will help you to deploy MTA-STS for your domain(s) using a Azure Function App. If you want to deploy MTA-STS using a Azure Static Web App, check out [the original deployment guide](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide#option-1-recommended-azure-static-web-app). Please remember, that you can only add [5 custom domains per Azure Static Web App](https://learn.microsoft.com/en-us/azure/static-web-apps/plans#features), while you can add [500 custom domains per Azure Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale#service-limits).

## Prerequisites

1. active Azure Subscription, to create the required Azure resources
2. [PowerShell 7.0](https://learn.microsoft.com/en-us/shows/it-ops-talk/how-to-install-powershell-7) or later
3. PowerShell modules
    - [Az.Accounts](https://www.powershellgallery.com/packages/Az.Accounts)
    - [Az.Websites](https://www.powershellgallery.com/packages/Az.Websites)
    - [ExchangeOnlineManagement](https://www.powershellgallery.com/packages/ExchangeOnlineManagement)
    - [PS.MTA-STS](https://www.powershellgallery.com/packages/PS.MTA-STS)

## Deployment

### Step 1: Create list of domains to deploy MTA-STS for

Before we start deploying Azure resources, we must prepare a list of domains we want to deploy MTA-STS for. We will use this list later to create the required DNS records and to configure the Azure resources for each domain.

To create the list, we will use the prepared PowerShell function [Export-PSMTASTSDomainsFromExo](../PS.MTA-STS/functions/Export-PSMTASTSDomainsFromExo.ps1) from the [PS.MTA-STS module](https://www.powershellgallery.com/packages/PS.MTA-STS/). This function will connect to Exchange Online and read all accepted domains. Then, it will check the MX record for each found domain to validate if it points to Exchange Online. Afterwards, you will be asked to select the domains you want to deploy MTA-STS for from a graphical interface. The selected domains will be exported to a CSV file.

To run the function, open a PowerShell 7.0 or later console, install and import the module:

```PowerShell
Install-Module -Name PS.MTA-STS
Import-Module -Name PS.MTA-STS
```

Then, run the function (edit the path to the CSV file as needed):

```PowerShell
Export-PSMTASTSDomainsFromExo -CsvOutputPath "C:\temp\acceptedDomains.csv"
```

Alternatively, check out the comment-based help of the function using `Get-Help -Name Export-PSMTASTSDomainsFromExo -Full` for more information.

## Step 2: Create Azure Function App

Now that you prepared the list of domains you want to deploy MTA-STS for, we can start to create the required Azure resources.

First of all, we must create a resource group which will combine all necessary resources. To do so, go to [Azure Portal](https://portal.azure.com/#home), search for "Resource groups", switch to the service page and select "Create".

Select your subscription, provide a name for your resource group, select your desired region and select "Review + create".

<img alt="Screenshot of creation of resource group" src="./_images/1_1_deploy_0.png" width="500" />

After the validation passed, select "Create".

Now, we can create the Azure Function App. To do so, go to [Azure Portal](https://portal.azure.com/#home), search for "Function App", switch to the service page and select "Create".

On the new page, enter the following information (as described at step 4 of [Enhancing mail flow with MTA-STS](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide#option-1-recommended-azure-static-web-app)):

- Basics
  - Subscription: Select your subscription
  - Resource group: Select the resource group you created in the previous step
  - Function App Name: MTA-STS-FunctionApp (or any other name you like and complies with the naming rules)
  - Runtime stack: PowerShell Core
  - Version: 7.2
  - Region: Select the same region as you selected for the resource group
  - Operating System: Windows
  - Hosting options and plans: Consumption (Serverless)
Leave the default settings for Storage, Networking, Monitoring and Deployment.

<img alt="Screenshot of creation of Azure Function App" src="./_images/1_1_deploy_1.png" width="500" />

Select "Review + create" and then "Create".

## Step 3: Configure your Azure Function App

Next, we must replace some file contents of our newly created Azure Function App. To do so, go to [Azure Portal](https://portal.azure.com/#home), search for "Function App", switch to the service page and select the function app you created in the previous step.

Select "App files" and replace the contents of "host.json", "profile.ps1" and "requirements.psd1" with the following contents:

1. host.json

```json
{
  "version": "2.0",
  "extensions": {
    "http": {
      "routePrefix": ""
    }
  },
  "managedDependency": {
    "Enabled": true
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.*, 4.0.0)"
  }
}
```

2. profile.ps1

```PowerShell
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
```

3. requirements.psd1

```PowerShell
# This file enables modules to be automatically managed by the Functions service.
# See https://aka.ms/functionsmanageddependency for additional information.
#
@{
    # Basic tools for your function
    'Azure.Function.Tools' = '1.*'
}
```

Now, we can create the function, which publishes the MTA-STS policy.

On the Function App service page, select "Functions" and then "Create".
As "Development environment" select 'Develop in portal' and as "Template" select 'HTTP trigger'.
Provide a name for your function, e.g. 'Publish-MTASTSPolicy' and as authorization select "Anonymous". "Anonymous" is required, as this script will be called by external servers which won't authenticate.

<img alt="Screenshot of creation of Azure Function App function" src="./_images/1_1_deploy_2.png" width="500" />

Select "Create" to create the function.

Now, we can add the code to the function. To do so, select "Code + Test" and copy and paste the following code to the run.ps1 and the function.json:

1. run.ps1

```PowerShell
param (
 $Request,

 $TriggerMetadata
)

Write-Host "Trigger: MTA-STS policy has been requested."

# Prepare the response body
# Replace 'enforce' with 'testing' to test the policy without enforcing it
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
```

2. function.json

```json
{
  "bindings": [
    {
      "name": "Request",
      "route": ".well-known/mta-sts.txt",
      "authLevel": "anonymous",
      "methods": [
        "get"
      ],
      "direction": "in",
      "type": "httpTrigger"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "Response"
    }
  ]
}
```

That's it. Your Function App is now prepared to publish the MTA-STS policy. Custom Domains will be added in step 5.

## Step 4: Create CNAME records in public DNS for your domains

Before adding your custom domains, you have to prepare CNAME records for the validation process. To do so, go to your public DNS provider and create the two following records per domain:

| Name | Type | Value |
| ---- | ---- | ----- |
| mta-sts.\<your-custom-domain> | CNAME | \<your-functionapp-name>.azurewebsites.net. |
| asuid.mta-sts.\<your-custom-domain> | TXT | \<your-functionapp-custom-domain-verification-ID> |

Your can find the \<your-functionapp-custom-domain-verification-ID> in the Azure Portal. Go to your Function App service page, select "Custom domains". You will find the ID in the "Custom domain verification ID" field on top of the page.

## Step 5: Add custom domains to Azure Function App

Now that you have prepared the CNAME records, you can add your custom domains to the Azure Function App. To do so, you can use the [Add-PSMTASTSCustomDomain](../PS.MTA-STS/functions/Add-PSMTASTSCustomDomain.ps1) function. The function will validate the CNAME records and add the custom domain to the Azure Function App.

Simply run the function and edit the parameters as required:

```PowerShell
Add-PSMTASTSCustomDomain -CsvPath "C:\temp\acceptedDomains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"
```

Alternatively, check out the comment-based help of the function using `Get-Help -Name Add-PSMTASTSCustomDomain -Full` for more information.

## Step 6: Create TXT record in public DNS to enable MTA-STS

Lastly, you have to create a TXT record in your public DNS to enable MTA-STS for your domain. To do so, go to your public DNS provider and create the following record per domain:

| Name | Type | Value |
| ---- | ---- | ----- |
| _mta-sts.\<your-custom-domain> | TXT | v=STSv1; id=\<your own unique id, e.g. the current date as 20230712120000>Z; |

## Step 7: Verify MTA-STS policy

To verify that your MTA-STS policy is working, you can use the [Test-MTASTSConfiguration](../PS.MTA-STS/functions/Test-MTASTSConfiguration.ps1) function. The function will test the MTA-STS policy for your domain and return the result. If you want to export the result to a CSV file, you can use the -ExportResult parameter as shown in the second example below.

```PowerShell
    # Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "MTA-STS-FunctionApp".

    Test-MTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "MTA-STS-FunctionApp"


    # Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "MTA-STS-FunctionApp". It also exports result to "C:\temp\mta-sts-result.csv".

    Test-MTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "MTA-STS-FunctionApp" -ExportResult -ResultPath "C:\temp\mta-sts-result.csv"

    
```

## CONGRAULATIONS! You have successfully configured MTA-STS for your domains!

You made a huge step towards a more secure email communication. Now, you can sit back and relax. Your MTA-STS policy will be published automatically. It is recommended to monitor your Azure Function App, so you can react quickly in case of an error. To learn how to create a alert rule for your function app check out [Create or edit an alert rule
](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-new-alert-rule?tabs=metric)
