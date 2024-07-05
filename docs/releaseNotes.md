# Release notes

## Update the module

To update the module to the latest version, use the following command:

```Powershell
Update-Module -Name PS.MTA-STS
```

## Version 1.2.2

The 1.2.2 release of the PS.MTA-STS module includes (but is not limited to) the following changes and improvements:

- Enabling Resource Provider "Microsoft.Web" automatically in "New-PSMTASTSFunctionAppDeployment" ([GitHub Issue #3](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/3))
- Added [faq](./faq.md) and [infographics](./mta-sts-infographic.md) on how MTA-STS works to the documentation ([GitHub Issue #16](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/16))
- Added support to reuse existing AppServicePlan, if's in the same resource group as the future Function App ([GitHub Issue #17](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/17))
- Fixed bug in error handling for DNS lookups, if module is used on non-english system ([GitHub Issue #18](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/18))
- Added ProgressBar to "Export-PSMTASTSDomainsFromExo" and "Test-PSMTASTSConfiguration" to show the progress of the export and test ([GitHub Issue #20](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/20))
- Added new Parameter to "Export-PSMTASTSDomainsFromExo" to disabe DNS Lookups for initial export ([GitHub Issue #21](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/21))
- Removing "AzureWebJobsDashboard" app setting automatically after Function App deployment, as this is deprecated ([GitHub Issue #24](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/24))
- Added support to reuse existing StorageAccount, if's in the same resource group as the future Function App ([GitHub Issue #26](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/26))
- Enabled "HttpsTrafficOnly" for new Function App Deployments by default ([GitHub Issue #27](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/27))

## Version 1.2.1

The 1.2.1 release of the PS.MTA-STS module includes the following changes and improvements:

- Added underscore as a valid character for resource group names in "New-PSMTASTSFunctionAppDeployment"
- Fixed bug in "Test-PSMTASTSConfiguration" when using the "-DomainName" parameter

## Version 1.2.0

The 1.2.0 release of the PS.MTA-STS module includes (but is not limited to) the following changes and improvements:

- Added 'Update-PSMTASTSFunctionAppFile' function to update the function app files
- Added tests for TLS-RPT to "Export-PSMTASTSDomainsFromExo" and "Test-PSMTASTSConfiguration" --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Added possibility to change policy mode in "Update-PSMTASTSFunctionAppFile" and "New-PSMTASTSFunctionAppDeployment" --> Thanks to [Daniel-t](https://github.com/Daniel-t)
- Updated Function App files (http security headers, root website) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Fixed bug in "Add-PSMTASTSCustomDomain", when no or a single custom domain existed on the Function App --> Thanks to [Daniel-t](https://github.com/Daniel-t)
- Added current state of MTA-STS configuration to "Export-PSMTASTSDomainsFromExo"
- Fixed bug in "New-PSMTASTSFunctionAppDeployment" when Storage Account or Function App name was not valid or taken by someone else. --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Updated documentation (RFC information, TLS-RPT, Alert rules and much more) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
