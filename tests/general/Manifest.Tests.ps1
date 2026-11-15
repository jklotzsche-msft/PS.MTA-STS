Describe "Validating the module manifest" {
    $moduleRoot = (Resolve-Path "$global:testroot\..\PS.MTA-STS").Path
    $manifest = ((Get-Content "$moduleRoot\PS.MTA-STS.psd1") -join "`n") | Invoke-Expression
    . "$moduleRoot\internal\functions\ConvertFrom-PSMTASTSTxtRecord.ps1"

    Context "Basic resources validation" {
        $files = Get-ChildItem "$moduleRoot\functions" -Recurse -File | Where-Object Name -like "*.ps1"
        It "Exports all functions in the public folder" -TestCases @{ files = $files; manifest = $manifest } {
            
            $functions = (Compare-Object -ReferenceObject $files.BaseName -DifferenceObject $manifest.FunctionsToExport | Where-Object SideIndicator -Like '<=').InputObject
            $functions | Should -BeNullOrEmpty
        }
        It "Exports no function that isn't also present in the public folder" -TestCases @{ files = $files; manifest = $manifest } {
            $functions = (Compare-Object -ReferenceObject $files.BaseName -DifferenceObject $manifest.FunctionsToExport | Where-Object SideIndicator -Like '=>').InputObject
            $functions | Should -BeNullOrEmpty
        }
        
        It "Exports none of its internal functions" -TestCases @{ moduleRoot = $moduleRoot; manifest = $manifest } {
            $files = Get-ChildItem "$moduleRoot\internal\functions" -Recurse -File -Filter "*.ps1"
            $files | Where-Object BaseName -In $manifest.FunctionsToExport | Should -BeNullOrEmpty
        }
    }
    
    Context "TXT record decoding validation" {
        It "accepts plain unquoted DNS TXT payloads" {
            $record = [pscustomobject]@{ Type = 16; Data = 'v=STSv1; id=20261111000000Z;' }
            ($record | ConvertFrom-PSMTASTSTxtRecord) | Should -Be 'v=STSv1; id=20261111000000Z;'
        }

        It "accepts plain unquoted DNS TXT payloads when returned as an array" {
            $record = [pscustomobject]@{ Type = 16; Data = @('v=STSv1; id=20261111000000Z;') }
            ($record | ConvertFrom-PSMTASTSTxtRecord) | Should -Be 'v=STSv1; id=20261111000000Z;'
        }

        It "rejects malformed DNS TXT presentation data" {
            { [pscustomobject]@{ Type = 16; Data = '"unterminated' } | ConvertFrom-PSMTASTSTxtRecord } | Should -Throw '*Malformed DNS TXT*'
        }
    }

    Context "Function app cleanup validation" {
        $moduleRoot = (Resolve-Path "$global:testroot\..\PS.MTA-STS").Path
        . "$moduleRoot\functions\Remove-PSMTASTSFunctionAppDeployment.ps1"

        It "removes a single bound certificate by thumbprint" {
            InModuleScope PS.MTA-STS {
                Mock Get-AzFunctionApp {
                    [pscustomobject]@{ AppServicePlan = 'test-plan'; Name = $Name }
                }
                Mock Get-AzFunctionAppSetting {
                    @{ 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING' = 'DefaultEndpointsProtocol=https;AccountName=reviewstore;AccountKey=abc' }
                }
                Mock Get-AzWebApp {
                    [pscustomobject]@{ HostNameSslStates = @([pscustomobject]@{ Thumbprint = 'ABC123' }) }
                }
                Mock Remove-AzFunctionApp {}
                Mock Remove-AzStorageAccount {}
                Mock Remove-AzAppServicePlan {}
                Mock Get-AzApplicationInsights { @() }
                Mock Get-AzResource { @() }
                Mock Get-AzWebAppCertificate {
                    @([pscustomobject]@{ Thumbprint = 'ABC123' })
                }
                Mock Remove-AzWebAppCertificate {
                    $script:removedThumbprint = $ThumbPrint
                }

                Remove-PSMTASTSFunctionAppDeployment -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -StorageAccountName 'reviewstore' -Confirm:$false
                $script:removedThumbprint | Should -Be 'ABC123'
            }
        }

        It "ignores certificate entries without thumbprint metadata when removing bound certificates" {
            InModuleScope PS.MTA-STS {
                Mock Get-AzFunctionApp {
                    [pscustomobject]@{ AppServicePlan = 'test-plan'; Name = $Name }
                }
                Mock Get-AzFunctionAppSetting {
                    @{ 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING' = 'DefaultEndpointsProtocol=https;AccountName=reviewstore;AccountKey=abc' }
                }
                Mock Get-AzWebApp {
                    [pscustomobject]@{ HostNameSslStates = @([pscustomobject]@{ Thumbprint = 'ABC123' }) }
                }
                Mock Remove-AzFunctionApp {}
                Mock Remove-AzStorageAccount {}
                Mock Remove-AzAppServicePlan {}
                Mock Get-AzApplicationInsights { @() }
                Mock Get-AzResource { @() }
                Mock Get-AzWebAppCertificate {
                    @(
                        [pscustomobject]@{ Name = 'not-a-certificate' },
                        [pscustomobject]@{ Thumbprint = 'ABC123' }
                    )
                }
                Mock Remove-AzWebAppCertificate {
                    $script:removedThumbprint = $ThumbPrint
                }

                Remove-PSMTASTSFunctionAppDeployment -ResourceGroupName 'rg-test' -FunctionAppName 'func-test' -StorageAccountName 'reviewstore' -Confirm:$false
                $script:removedThumbprint | Should -Be 'ABC123'
            }
        }
    }

    Context "Individual file validation" {
        It "The root module file exists" -TestCases @{ moduleRoot = $moduleRoot; manifest = $manifest } {
            Test-Path "$moduleRoot\$($manifest.RootModule)" | Should -Be $true
        }
        
        foreach ($format in $manifest.FormatsToProcess)
        {
            It "The file $format should exist" -TestCases @{ moduleRoot = $moduleRoot; format = $format } {
                Test-Path "$moduleRoot\$format" | Should -Be $true
            }
        }
        
        foreach ($type in $manifest.TypesToProcess)
        {
            It "The file $type should exist" -TestCases @{ moduleRoot = $moduleRoot; type = $type } {
                Test-Path "$moduleRoot\$type" | Should -Be $true
            }
        }
        
        foreach ($assembly in $manifest.RequiredAssemblies)
        {
            if ($assembly -like "*.dll") {
                It "The file $assembly should exist" -TestCases @{ moduleRoot = $moduleRoot; assembly = $assembly } {
                    Test-Path "$moduleRoot\$assembly" | Should -Be $true
                }
            }
            else {
                It "The file $assembly should load from the GAC" -TestCases @{ moduleRoot = $moduleRoot; assembly = $assembly } {
                    { Add-Type -AssemblyName $assembly } | Should -Not -Throw
                }
            }
        }
        
        foreach ($tag in $manifest.PrivateData.PSData.Tags)
        {
            It "Tags should have no spaces in name" -TestCases @{ tag = $tag } {
                $tag -match " " | Should -Be $false
            }
        }
    }
}