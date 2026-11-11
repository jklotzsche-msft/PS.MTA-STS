# Description

This is where the function tests go.

Make sure to put them in folders reflecting the actual module structure.

It is not necessary to differentiate between internal and public functions here.

`ReviewRegression.Tests.ps1` runs without Azure credentials or a test domain. It mocks DNS, HTTP and Azure operations and covers certificate thumbprint matching, TXT record normalization and cardinality, CSV exports, and telemetry after confirmation or failures.

Run it directly with Pester 5.7.1 or later:

```powershell
Invoke-Pester -Path .\tests\functions\ReviewRegression.Tests.ps1 -Output Detailed
```
