# Release notes

## Update the module

To update the module to the latest version, use the following command:

```Powershell
Update-Module -Name PS.MTA-STS
```

## Version 1.2.0

The 1.2.0 release of the PS.MTA-STS module includes the following changes and improvements:

- Added 'Update-PSMTASTSFunctionAppFile' function to update the function app files
- Added tests for TLS-RPT to "Export-PSMTASTSDomainsFromExo" and "Test-PSMTASTSConfiguration" --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Added possibility to change policy mode in "Update-PSMTASTSFunctionAppFile" and "New-PSMTASTSFunctionAppDeployment" --> Thanks to [Daniel-t](https://github.com/Daniel-t)
- Updated Function App files (http security headers, root website) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Fixed bug in "Add-PSMTASTSCustomDomain", when no or a single custom domain existed on the Function App --> Thanks to [Daniel-t](https://github.com/Daniel-t)
- Added current state of MTA-STS configuration to "Export-PSMTASTSDomainsFromExo"
- Fixed bug in "New-PSMTASTSFunctionAppDeployment" when Storage Account or Function App name was not valid or taken by someone else. --> Thanks to [BohrenAn](https://github.com/BohrenAn)
- Updated documentation (RFC information, TLS-RPT, Alert rules and much more) --> Thanks to [BohrenAn](https://github.com/BohrenAn)
