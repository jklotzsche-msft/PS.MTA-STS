BeforeAll {
    $script:repo = (Resolve-Path "$PSScriptRoot\..\..").Path
    . "$script:repo\PS.MTA-STS\internal\scripts\New-PSMTASTSVariables.ps1"
    . "$script:repo\PS.MTA-STS\functions\Update-PSMTASTSFunctionAppFile.ps1"
    . "$script:repo\PS.MTA-STS\functions\New-PSMTASTSFunctionAppDeployment.ps1"

    function Get-AzContext { [CmdletBinding()]param() [pscustomobject]@{ Subscription = @{ Id = 'offline-subscription' } } }
    function Get-AzResourceGroup { [CmdletBinding()]param($Name) }
    function Set-AzDefault { [CmdletBinding()]param($ResourceGroupName) throw 'Unmocked Azure operation.' }
    function Get-AzFunctionApp { [CmdletBinding()]param($ResourceGroupName, $Name) }
    function Get-AzLocation { [CmdletBinding()]param() }
    function Get-AzResourceProvider { [CmdletBinding()]param() }
    function Get-AzFunctionAppSetting { [CmdletBinding()]param($ResourceGroupName, $Name) }
    function Get-AzStorageAccount { [CmdletBinding()]param($ResourceGroupName, $StorageAccountName) }
    function New-AzStorageContext { [CmdletBinding()]param($StorageAccountName) }
    function New-AzStorageAccount {
        [CmdletBinding()]param($ResourceGroupName, $Name, $Location, $SkuName, $AllowBlobPublicAccess, $EnableHttpsTrafficOnly, $MinimumTlsVersion, $EnableSftp)
        throw 'Unmocked Azure operation.'
    }
    function Enable-AzStorageDeleteRetentionPolicy {
        [CmdletBinding()]param($RetentionDays, $Context)
        throw 'Unmocked Azure operation.'
    }
    function New-AzFunctionApp {
        [CmdletBinding()]param($ResourceGroupName, $Name, $Runtime, $StorageAccountName, $FunctionsVersion, $OSType, $RuntimeVersion, $PlanName, $Location, [switch]$DisableApplicationInsights)
        throw 'Unmocked Azure operation.'
    }
    function Publish-AzWebApp {
        [CmdletBinding(SupportsShouldProcess)]param($ResourceGroupName, $Name, $ArchivePath, [switch]$Force)
        throw 'Unmocked Azure operation.'
    }
    function Set-AzWebApp {
        [CmdletBinding()]param($ResourceGroupName, $Name, $FtpsState)
        throw 'Unmocked Azure operation.'
    }
    function Invoke-AzRestMethod {
        [CmdletBinding()]param($Method, $Path, $Payload)
        throw 'Unmocked Azure operation.'
    }
    function Set-AzStorageAccount {
        [CmdletBinding()]param($ResourceGroupName, $Name, $MinimumTlsVersion)
        throw 'Unmocked Azure operation.'
    }
    function Push-OutputBinding {
        [CmdletBinding()]param($Name, $Value)
        throw 'Uncaptured local output binding.'
    }
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type @'
public class HttpResponseContext {
    public System.Net.HttpStatusCode StatusCode { get; set; }
    public System.Collections.Hashtable Headers { get; set; }
    public object Body { get; set; }
}
'@
    }
}

Describe 'Domain-free package generation and local function execution' {
    BeforeEach {
        $script:previousTemp = $env:TEMP
        $script:previousTmp = $env:TMP
        $script:previousTmpDir = $env:TMPDIR
        $script:tempRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $script:tempRoot
        $env:TEMP = $script:tempRoot
        $env:TMP = $script:tempRoot
        $env:TMPDIR = $script:tempRoot
        if ([IO.Path]::GetTempPath().TrimEnd('\') -ne $script:tempRoot.TrimEnd('\')) {
            throw 'Temporary directory isolation failed; do not invoke the deployment code.'
        }
        $script:published = @()
        $script:stagingDirectories = @()
        $script:responses = @{}
        $script:settings = @{ WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = 'AccountName=reviewstore;AccountKey=offline' }
        $script:deploymentArgs = @{ ResourceGroupName = 'review-rg'; FunctionAppName = 'review-func' }
        $script:restPayload = $null
        $script:newFunction = $null

        Mock Get-AzResourceGroup { [pscustomobject]@{ Name = 'review-rg' } }
        Mock Set-AzDefault {}
        Mock Get-AzFunctionApp { [pscustomobject]@{ Name = 'review-func' } }
        Mock Get-AzLocation { [pscustomobject]@{ Location = 'westeurope' } }
        Mock Get-AzResourceProvider { [pscustomobject]@{ ProviderNamespace = 'Microsoft.Web'; RegistrationState = 'Registered' } }
        Mock Get-AzFunctionAppSetting { $script:settings }
        Mock Get-AzStorageAccount { [pscustomobject]@{ StorageAccountName = 'reviewstore' } }
        Mock New-AzStorageContext { [pscustomobject]@{ StorageAccountName = 'reviewstore' } }
        Mock New-AzStorageAccount {}
        Mock Enable-AzStorageDeleteRetentionPolicy {}
        Mock New-AzFunctionApp {
            param($Runtime, $RuntimeVersion, $OSType, $FunctionsVersion, $DisableApplicationInsights)
            $script:newFunction = [pscustomobject]@{
                Runtime = $Runtime; RuntimeVersion = $RuntimeVersion; OSType = $OSType
                FunctionsVersion = $FunctionsVersion; DisableApplicationInsights = [bool]$DisableApplicationInsights
            }
        }
        Mock Invoke-RestMethod { [pscustomobject]@{ Status = 3 } }
        Mock Start-Sleep {}
        Mock Publish-AzWebApp {
            param($ArchivePath)
            $script:stagingDirectories += Split-Path -Parent $ArchivePath
            $target = Join-Path $script:tempRoot ('published-' + [guid]::NewGuid().ToString())
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $target -ErrorAction Stop
            $script:published += $target
        }
        Mock Set-AzWebApp {}
        Mock Invoke-AzRestMethod {
            param($Payload)
            $script:restPayload = $Payload | ConvertFrom-Json
        }
        Mock Set-AzStorageAccount {}
        Mock Push-OutputBinding {
            param($Name, $Value)
            $script:responses[$Name] = $Value
        }
    }

    AfterEach {
        $env:TEMP = $script:previousTemp
        $env:TMP = $script:previousTmp
        $env:TMPDIR = $script:previousTmpDir
    }

    It 'generates and executes <Mode> policy with ExtraHosts=<ExtraHosts>' -TestCases @(
        @{ Mode = 'Testing'; ExtraHosts = $false }, @{ Mode = 'Testing'; ExtraHosts = $true },
        @{ Mode = 'Enforce'; ExtraHosts = $false }, @{ Mode = 'Enforce'; ExtraHosts = $true },
        @{ Mode = 'None'; ExtraHosts = $false }, @{ Mode = 'None'; ExtraHosts = $true }
    ) {
        param($Mode, $ExtraHosts)
        $parameters = $script:deploymentArgs + @{ PolicyMode = $Mode }
        if ($ExtraHosts) { $parameters.ExoHostName = @('*.abcd-v1.mx.microsoft', 'mail.example.com') }
        Update-PSMTASTSFunctionAppFile @parameters
        $script:published | Should -HaveCount 1
        Test-Path -LiteralPath $script:stagingDirectories[0] | Should -BeFalse
        $package = $script:published[0]
        foreach ($file in @('host.json', 'profile.ps1', 'requirements.psd1', 'WebsiteRoot\function.json', 'WebsiteRoot\run.ps1', 'MTASTS\function.json', 'MTASTS\run.ps1')) {
            Test-Path -LiteralPath (Join-Path $package $file) | Should -BeTrue
        }
        $hostConfig = Get-Content (Join-Path $package 'host.json') -Raw | ConvertFrom-Json
        $hostConfig.extensionBundle.version | Should -Be '[4.0.0, 5.0.0)'
        $hostConfig.extensions.http.routePrefix | Should -Be ''
        $binding = Get-Content (Join-Path $package 'MTASTS\function.json') -Raw | ConvertFrom-Json
        $binding.bindings[0].route | Should -Be '.well-known/mta-sts.txt'
        $binding.bindings[0].authLevel | Should -Be 'anonymous'
        $binding.bindings[0].methods | Should -Contain 'get'
        . (Join-Path $package 'MTASTS\run.ps1') -Request @{} -TriggerMetadata @{} 6>$null
        [int]$script:responses.Response.StatusCode | Should -Be 200
        $script:responses.Response.Headers['Content-type'] | Should -Be 'text/plain'
        $expected = "version: STSv1`nmode: $($Mode.ToLower())`nmx: *.mail.protection.outlook.com"
        if ($ExtraHosts) { $expected += "`nmx: *.abcd-v1.mx.microsoft`nmx: mail.example.com" }
        $expected += "`nmax_age: 604800"
        ([string]$script:responses.Response.Body).Replace("`r`n", "`n") | Should -Be $expected
        . (Join-Path $package 'WebsiteRoot\run.ps1') -Request @{} -TriggerMetadata @{} 6>$null
        [int]$script:responses.Response.StatusCode | Should -Be 200
        $script:responses.Response.Headers['content-type'] | Should -Be 'text/html'
        $script:responses.Response.Body | Should -Match '\.well-known/mta-sts\.txt'
    }

    It 'sets the documented runtime, TLS and FTP settings during update' {
        Update-PSMTASTSFunctionAppFile @script:deploymentArgs -PolicyMode Testing
        Should -Invoke Set-AzWebApp -Times 1 -Exactly -ParameterFilter { $FtpsState -eq 'Disabled' }
        $script:restPayload.properties.powerShellVersion | Should -Be '7.6'
        $script:restPayload.properties.minTlsVersion | Should -Be '1.2'
        $script:restPayload.properties.scmMinTlsVersion | Should -Be '1.2'
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and $Path -like '*/review-func/config/web?api-version=2026-07-15'
        }
        Should -Invoke Set-AzStorageAccount -Times 1 -Exactly -ParameterFilter { $Name -eq 'reviewstore' -and $MinimumTlsVersion -eq 'TLS1_2' }
    }

    It 'resolves storage settings from <Setting>' -TestCases @(
        @{ Setting = 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING' },
        @{ Setting = 'AzureWebJobsStorage' },
        @{ Setting = 'AzureWebJobsStorage__accountName' }
    ) {
        param($Setting)
        $script:settings = @{}
        $script:settings[$Setting] = if ($Setting -like '*__accountName') { 'reviewstore' } else { 'AccountKey=offline;AccountName=reviewstore;EndpointSuffix=core.windows.net' }
        Update-PSMTASTSFunctionAppFile @script:deploymentArgs
        Should -Invoke Set-AzStorageAccount -Times 1 -Exactly -ParameterFilter { $Name -eq 'reviewstore' }
    }

    It 'does not retain policy changes between consecutive updates' {
        Update-PSMTASTSFunctionAppFile @script:deploymentArgs -PolicyMode Testing -ExoHostName 'mail.example.com'
        Update-PSMTASTSFunctionAppFile @script:deploymentArgs -PolicyMode None
        $script:published | Should -HaveCount 2
        @($script:stagingDirectories | Select-Object -Unique) | Should -HaveCount 2
        . (Join-Path $script:published[1] 'MTASTS\run.ps1') -Request @{} -TriggerMetadata @{} 6>$null
        $script:responses.Response.Body | Should -Match 'mode: none'
        $script:responses.Response.Body | Should -Not -Match 'mx: mail\.example\.com'
    }

    It 'cleans its isolated staging directory after a publishing failure' {
        Mock Publish-AzWebApp {
            param($ArchivePath)
            $script:stagingDirectories += Split-Path -Parent $ArchivePath
            throw 'Simulated publishing failure'
        }
        { Update-PSMTASTSFunctionAppFile @script:deploymentArgs } | Should -Throw '*Simulated publishing failure*'
        $script:stagingDirectories | Should -HaveCount 1
        Test-Path -LiteralPath $script:stagingDirectories[0] | Should -BeFalse
    }

    It 'leaves an unrelated shared staging directory untouched' {
        $sharedDirectory = Join-Path $script:tempRoot 'PS.MTA-STS_deployment'
        $null = New-Item -ItemType Directory -Path $sharedDirectory
        $marker = Join-Path $sharedDirectory 'keep.txt'
        Set-Content -LiteralPath $marker -Value 'unrelated deployment'
        Update-PSMTASTSFunctionAppFile @script:deploymentArgs
        (Get-Content -LiteralPath $marker -Raw).Trim() | Should -Be 'unrelated deployment'
    }

    It 'executes creation orchestration with ApplicationInsights=<Insights>' -TestCases @(
        @{ Insights = $false }, @{ Insights = $true }
    ) {
        param($Insights)
        New-PSMTASTSFunctionAppDeployment @script:deploymentArgs -Location westeurope -StorageAccountName reviewstore -PolicyMode Testing -EnableApplicationInsights:$Insights
        $script:newFunction.Runtime | Should -Be 'PowerShell'
        $script:newFunction.RuntimeVersion | Should -Be '7.6'
        $script:newFunction.OSType | Should -Be 'Windows'
        $script:newFunction.FunctionsVersion | Should -Be '4'
        $script:newFunction.DisableApplicationInsights | Should -Be (-not $Insights)
        Should -Invoke New-AzStorageAccount -Times 1 -Exactly -ParameterFilter { $SkuName -eq 'Standard_LRS' -and $MinimumTlsVersion -eq 'TLS1_2' }
        $script:published | Should -HaveCount 1
        . (Join-Path $script:published[0] 'MTASTS\run.ps1') -Request @{} -TriggerMetadata @{} 6>$null
        $script:responses.Response.Body | Should -Match 'mode: testing'
    }
}
