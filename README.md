# PS.MTA-STS

PowerShell-Mail Transfer Agent-Strict Transport Security | Enhancing mail flow by deploying and testing MTA-STS for Exchange Online using this PowerShell module.

<img alt="Logo - E-Mail flying around planet earth" src="./docs/_images/PS.MTA-STS-Logo.jpg" width="200" />

This module is for you, if you ...

- ... want to improve the security of your mail flow
- ... use Exchange Online for mail flow
- ... have lots of domains and want to deploy MTA-STS for all of them
- ... have an Azure subscription and want to deploy MTA-STS using Azure Static Web Apps or Azure Functions
- ... want to test your MTA-STS configuration using PowerShell

## Why MTA-STS?

MTA-STS is a new internet standard that improves email security and delivery for your organization. MTA-STS leverages the well-known security standard HTTPS, which is used to secure connections to websites, to enable organizations to assert policies and requirements for their email services. MTA-STS also enables organizations to request that remote email servers deliver email messages over a secure connection and to report back on any failures encountered. This helps to ensure that email messages are delivered in a secure and reliable manner.

## What does this module do?

This module supports you at deploying and testing MTA-STS for Exchange Online. It will help you to create the required DNS records and to configure the MTA-STS policy for your domain. It will also help you to test the MTA-STS policy and to troubleshoot any issues you might encounter.

## How to install this module?

You can install this module from the [PowerShell Gallery](https://www.powershellgallery.com/packages/PS.MTA-STS/).

``` Powershell
Install-Module -Name PS.MTA-STS
```

## MTA-STS Deployment

You have two options to deploy MTA-STS for your domain(s) using Azure:

1. Deploy MTA-STS using Azure Static Web Apps
2. Deploy MTA-STS using Azure Functions

> One major difference is, that Azure Static Web Apps allow you to add [5 custom domains per app](https://learn.microsoft.com/en-us/azure/static-web-apps/plans#features), while Azure Functions allow you to add [500 custom domains per app](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale#service-limits). So if you want to deploy MTA-STS for more than 5 domains, you must deploy a Azure Function App or alternatively multiple Azure Static Web Apps.

If you want to deploy a Azure Static Web App to host your MTA-STS policy, check out [the original deployment guide](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide#option-1-recommended-azure-static-web-app).

If you want to deploy a Azure Function App to host your MTA-STS policy using this repository, check out the [PS.MTA-STS deployment guide](./docs/deployFunctionApp.md).

No matter which option you choose, you will end up with a Azure resource that hosts your MTA-STS policy. In both cases, you will be able to use

- 'Export-PSMTASTSDomainsFromExo' function to get a csv file containing your accepted domains with MX record validation
- 'Test-MTASTSConfiguration' function to test your MTA-STS configuration for all provided domains

For more information about the functions, import the module and use 'Get-Help' to get the help for the functions.

``` Powershell
Import-Module -Name PS.MTA-STS
Get-Help -Name Export-PSMTASTSDomainsFromExo -Full
Get-Help -Name Test-MTASTSConfiguration -Full
```

## Resources / Links

[Enhancing mail flow with MTA-STS](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide)

[Azure Static Web Apps hosting plans](https://learn.microsoft.com/en-us/azure/static-web-apps/plans)

[Azure Functions hosting options](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale)

[RFC 8461: SMTP MTA Strict Transport Security (MTA-STS)](https://datatracker.ietf.org/doc/html/rfc8461)
