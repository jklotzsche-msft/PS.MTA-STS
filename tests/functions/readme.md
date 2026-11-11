# Description

This is where the function tests go.

Make sure to put them in folders reflecting the actual module structure.

It is not necessary to differentiate between internal and public functions here.

`ReviewRegression.Tests.ps1` runs without Azure credentials or a test domain. It mocks DNS, HTTP and Azure operations and covers certificate thumbprint matching, TXT record normalization and cardinality, CSV exports, and telemetry after confirmation or failures.

`Deployment.Tests.ps1` creates real deployment archives and executes the generated policy and root scripts with simulated Azure output bindings. It also checks runtime settings, storage mapping, policy isolation and temporary-directory cleanup. It does not start an Azure Functions host or create Azure resources.

Run both suites directly with Pester 5.7.1 or later:

```powershell
Invoke-Pester -Path .\tests\functions -Output Detailed
```
