# PS.MTA-STS

PowerShell-Mail Transfer Agent-Strict Transport Security | Enhancing mail flow by deploying and testing MTA-STS for Exchange Online using this PowerShell module.

<img alt="Logo - E-Mail flying around planet earth. This is the logo for this project." src="./docs/_images/PS.MTA-STS-Logo.jpg" width="200" />

This module is for you, if you ...

- ... want to improve the security of your mail flow
- ... use Exchange Online for mail flow
- ... have lots of domains and want to deploy MTA-STS for all of them
- ... have an Azure subscription and want to deploy MTA-STS using Azure Static Web Apps or Azure Functions
- ... want to test your MTA-STS configuration using PowerShell

## Why MTA-STS?

MTA-STS is a new internet standard that improves email security and delivery for your organization. MTA-STS leverages the well-known security standard HTTPS, which is used to secure connections to websites, to enable organizations to assert policies and requirements for their email services. MTA-STS also enables organizations to request that remote email servers deliver email messages over a secure connection and to report back on any failures encountered. This helps to ensure that email messages are delivered in a secure and reliable manner.

> Please check out our [MTA-STS Infographic](./docs/mta-sts-infographic.md) to learn more about how MTA-STS works. We visualized the usual mail flow without MTA-STS, the possible attack scenario without MTA-STS, the usual mail flow with MTA-STS, and the possible attack scenario with MTA-STS, which can be detected and mitigated.

## SMTP MTA Strict Transport Security (MTA-STS)

Defined in [rfc8461](https://datatracker.ietf.org/doc/html/rfc8461)

MTA-STS consists of two Parts:

- MTA-STS TXT DNS Record
- MTA-STS Policy

### MTA-STS TXT Record

This DNS Record indicates that the Domain supports MTA-STS. The id can be literally anything it's usualy just a datetime value of the last change.

``` Text
_mta-sts.example.com.  IN TXT "v=STSv1; id=20160831085700Z;"
```

### MTA-STS Policy

The MTA-STS Policy is located at the "./well-known/" directory and contains a Text file with the Policy, like [https://mta-sts.example.com/.well-known/mta-sts.txt](https://mta-sts.example.com/.well-known/mta-sts.txt)

For Exchange Online the mta-sts.txt looks like this

``` Text
version: STSv1
mode: enforce
mx: *.mail.protection.outlook.com
max_age: 604800
```

## SMTP TLS Reporting (TLSRPT)

Defined in [rfc8460](https://datatracker.ietf.org/doc/html/rfc8460)

This DNS Record allows the Sender MTA to send Reports (similar to DMARC) to a defined Emailadress or a HTML Site for reporting purposes. While Microsoft does not offer a Service to aggregate these Reports, there are plenty of TLSRPT Data providers that can do this Job.

``` Text
_smtp._tls.example.com. IN TXT "v=TLSRPTv1;rua=mailto:reports@example.com"
_smtp._tls.example.com. IN TXT "v=TLSRPTv1; rua=https://reporting.example.com/v1/tlsrpt"
```

## What does this module do?

This module supports you at deploying and testing MTA-STS for Exchange Online. It will help you to create the required DNS records and to configure the MTA-STS policy for your domain. It will also help you to test the MTA-STS policy and to troubleshoot any issues you might encounter.

## How to install this module?

You can install this module from the [PowerShell Gallery](https://www.powershellgallery.com/packages/PS.MTA-STS/).

``` Powershell
#Install Module using PowerShellGet
Install-Module -Name PS.MTA-STS

#Install Module using Microsoft.PowerShell.PSResourceGet
Install-PSResource -Name PS.MTA-STS
```

## MTA-STS Deployment

You have two options to deploy MTA-STS for your domain(s) using Azure:

1. Deploy MTA-STS using Azure Static Web Apps
2. Deploy MTA-STS using Azure Functions

> One major difference is, that Azure Static Web Apps allow you to add [5 custom domains per app](https://learn.microsoft.com/en-us/azure/static-web-apps/plans#features), while Azure Functions allow you to add [500 custom domains per app](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale#service-limits). So if you want to deploy MTA-STS for more than 5 domains, you must deploy a Azure Function App or alternatively multiple Azure Static Web Apps.

If you want to deploy a Azure Static Web App to host your MTA-STS policy, check out [the original deployment guide](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide#option-1-recommended-azure-static-web-app).

If you want to deploy a Azure Function App to host your MTA-STS policy using this repository, check out the [PS.MTA-STS deployment guide](./docs/deployFunctionApp.md). The deployment guide describes the needed steps and functions to deploy a Azure Function App to host your MTA-STS policy.

No matter which of the options above you choose, you will end up with a Azure resource that hosts your MTA-STS policy. In both cases, you will be able to use at least

- 'Export-PSMTASTSDomainsFromExo' function to get a csv file containing your accepted domains with MX record validation
- 'Update-PSMTASTSFunctionAppFile' function to update the function app files with your MTA-STS policy
- 'Test-MTASTSConfiguration' function to test your MTA-STS configuration for all provided domains

For more information about the functions, import the module and use 'Get-Help' to get the help for the functions.

``` Powershell
Import-Module -Name PS.MTA-STS
Get-Help -Name Export-PSMTASTSDomainsFromExo -Full
Get-Help -Name Update-PSMTASTSFunctionAppFile -Full
Get-Help -Name Test-MTASTSConfiguration -Full
```

## Update existing MTA-STS Deployment

If you already have a MTA-STS deployment and want to update the MTA-STS policy, you can use the 'Update-PSMTASTSFunctionAppFile' function to update the MTA-STS policy for your domains.
This is useful if you want to change the policy mode from 'Testing' to 'Enforce' or if you want to update your app files with the latest version of this module.

``` Powershell
Update-PSMTASTSFunctionAppFile -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -PolicyMode 'Enforce'

# Updates the Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' with policy mode 'Enforce'.
# This will overwrite any changes you made to the Azure Function App!
```

If you want to migrate or rebuild your MTA-STS deployment, check out our [Migrate MTA-STS deployment from Azure Static Web App or old Azure Function App to new Azure Function App](./docs/migrateFunctionApp.md) guide.

## Release Notes

For more information about the latest changes, please check out the [release notes](./docs/releaseNotes.md).

## Frequently Asked Questions (FAQ)

For more information about frequently asked questions, please check out the [FAQ](./docs/faq.md).

## Resources / Links

- [Enhancing mail flow with MTA-STS](https://learn.microsoft.com/en-us/microsoft-365/compliance/enhancing-mail-flow-with-mta-sts?view=o365-worldwide)
- [Azure Static Web Apps hosting plans](https://learn.microsoft.com/en-us/azure/static-web-apps/plans)
- [Azure Functions hosting options](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale)
- [RFC 8461: SMTP MTA Strict Transport Security (MTA-STS)](https://datatracker.ietf.org/doc/html/rfc8461)
- [RFC 8460: SMTP TLS Reporting (TLSRPT)](https://datatracker.ietf.org/doc/html/rfc8460)
