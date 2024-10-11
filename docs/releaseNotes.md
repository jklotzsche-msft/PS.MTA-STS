# Release notes

## Update the module

To update the module to the latest version, use the following command:

```Powershell
Update-Module -Name PS.MTA-STS
```

## Version 1.3.0

The 1.3.0 release of the PS.MTA-STS module includes (but is not limited to) the following changes and improvements:

- Major change: added compatibility to SMTP DANE with DNSSEC MX records. This enables you to use this solution even if you have multiple MX records for your domains. This could be the case, if you have some domains pointing to the known `*.mail.protection.outlook.com` MX record and some domains pointing to the new `mx.microsoft` endpoints for SMTP DANE with DNSSEC ([GitHub Issue #38](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/38)) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Improved error handling in all functions, which will also prevent functions from failing because of warning messages ([GitHub Issue #37](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/37))
- Upgraded Function Runtime to PowerShell 7.4 in docs and automatic deployment ([GitHub Issue #35](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/35)) --> Thanks to [dreamaker69](https://github.com/dreamaker69)
- Added information about the retirement of Classic Application Insights to the FAQ, additionally added a new switch parameter to disable Application Insights for new deployments in `New-PSMTASTSFunctionAppDeployment` ([GitHub Issue #34](https://github.com/jklotzsche-msft/PS.MTA-STS/issues/34)) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Enabled soft delete for blobs in the storage account in `New-PSMTASTSFunctionAppDeployment` by adding new parameter `StorageDeleteRetentionInDays` which defaults to 7 days (suggested as part of [GitHub Pull Request #33](https://github.com/jklotzsche-msft/PS.MTA-STS/pull/33)) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Added Check of Certification Authority Authorization [CAA Record](https://de.wikipedia.org/wiki/DNS_Certification_Authority_Authorization) and Parameter -SkipCAACheck in Add-PSMTASTSCustomDomain Function --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Lot's of documentation improvements, including an improved section about the MTA-STS policy file

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
