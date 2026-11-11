BeforeAll {
    $script:repo = (Resolve-Path "$PSScriptRoot\..\..").Path
    foreach ($file in Get-ChildItem "$script:repo\PS.MTA-STS\internal\functions" -Filter *.ps1) {
        . $file.FullName
    }
    foreach ($name in @(
        'Test-PSMTASTSConfiguration', 'Export-PSMTASTSDomainsFromExo',
        'Add-PSMTASTSCustomDomain', 'Remove-PSMTASTSCustomDomain',
        'Remove-PSMTASTSFunctionAppDeployment'
    )) {
        . "$script:repo\PS.MTA-STS\functions\$name.ps1"
    }

    function Get-AzContext { [CmdletBinding()] param() 'offline' }
    function Get-AzFunctionApp { [CmdletBinding()] param($ResourceGroupName, $Name) }
    function Get-AzFunctionAppSetting { [CmdletBinding()] param($ResourceGroupName, $Name) }
    function Get-AzWebApp { [CmdletBinding()] param($ResourceGroupName, $Name) }
    function Get-AzWebAppCertificate { [CmdletBinding()] param($ResourceGroupName) }
    function Get-AzResource { [CmdletBinding()] param($ResourceGroupName, $ResourceType) }
    function Get-PSMTASTSCustomDomain { [CmdletBinding()] param($ResourceGroupName, $FunctionAppName) }
    function Get-ConnectionInformation { [CmdletBinding()] param() }
    function Get-AcceptedDomain { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$Identity, $ResultSize) process {} }
    function Resolve-DnsName { [CmdletBinding()] param($Name, $Type, $Server, [switch]$QuickTimeout) }
    function Set-AzWebApp {
        [CmdletBinding()] param($ResourceGroupName, $Name, $HostNames)
        throw 'Unmocked Azure mutation is prohibited.'
    }
    function Remove-AzFunctionApp {
        [CmdletBinding()] param($ResourceGroupName, $Name, [switch]$Force)
        throw 'Unmocked Azure mutation is prohibited.'
    }
    function Remove-AzStorageAccount {
        [CmdletBinding()] param($ResourceGroupName, $Name, [switch]$Force)
        throw 'Unmocked Azure mutation is prohibited.'
    }
    function Remove-AzAppServicePlan {
        [CmdletBinding()] param($ResourceGroupName, $Name, [switch]$Force)
        throw 'Unmocked Azure mutation is prohibited.'
    }
    function Remove-AzResource {
        [CmdletBinding()] param($ResourceId, [switch]$Force)
        throw 'Unmocked Azure mutation is prohibited.'
    }
    function Remove-AzWebAppCertificate {
        [CmdletBinding(SupportsShouldProcess)] param($ResourceGroupName, $ThumbPrint)
        throw 'Unmocked Azure mutation is prohibited.'
    }

    if (-not ('PSMTASTSDecliningHost' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

public sealed class PSMTASTSDecliningUI : PSHostUserInterface {
    public int Prompts;
    public override PSHostRawUserInterface RawUI { get { return null; } }
    public override string ReadLine() { throw new NotSupportedException(); }
    public override SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
    public override void Write(string text) { }
    public override void Write(ConsoleColor fg, ConsoleColor bg, string text) { }
    public override void WriteLine(string text) { }
    public override void WriteErrorLine(string text) { }
    public override void WriteDebugLine(string text) { }
    public override void WriteProgress(long source, ProgressRecord record) { }
    public override void WriteVerboseLine(string text) { }
    public override void WriteWarningLine(string text) { }
    public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> fields) { throw new NotSupportedException(); }
    public override PSCredential PromptForCredential(string caption, string message, string user, string target) { throw new NotSupportedException(); }
    public override PSCredential PromptForCredential(string caption, string message, string user, string target, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException(); }
    public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
        Prompts++;
        for (int i = 0; i < choices.Count; i++) {
            if (choices[i].Label.Replace("&", "").Equals("No", StringComparison.OrdinalIgnoreCase)) { return i; }
        }
        throw new InvalidOperationException("No negative confirmation choice.");
    }
}
public sealed class PSMTASTSDecliningHost : PSHost {
    private readonly Guid id = Guid.NewGuid();
    public readonly PSMTASTSDecliningUI ReviewUI = new PSMTASTSDecliningUI();
    public override Guid InstanceId { get { return id; } }
    public override string Name { get { return "OfflineRegressionTests"; } }
    public override Version Version { get { return new Version(1, 0); } }
    public override PSHostUserInterface UI { get { return ReviewUI; } }
    public override CultureInfo CurrentCulture { get { return CultureInfo.InvariantCulture; } }
    public override CultureInfo CurrentUICulture { get { return CultureInfo.InvariantCulture; } }
    public override void EnterNestedPrompt() { throw new NotSupportedException(); }
    public override void ExitNestedPrompt() { throw new NotSupportedException(); }
    public override void NotifyBeginApplication() { }
    public override void NotifyEndApplication() { }
    public override void SetShouldExit(int code) { }
}
'@
    }
}

Describe 'Review regression tests without Azure or a test domain' {
    BeforeEach {
        $script:mtaText = 'v=STSv1; id=20261111000000Z;'
        $script:tlsText = 'v=TLSRPTv1; rua=mailto:reports@example.com'
        $script:mtaDoh = @([pscustomobject]@{ Type = 16; Data = '"' + $script:mtaText + '"' })
        $script:tlsDoh = @([pscustomobject]@{ Type = 16; Data = '"' + $script:tlsText + '"' })
        $script:mtaClassic = @([pscustomobject]@{ Strings = @($script:mtaText) })
        $script:tlsClassic = @([pscustomobject]@{ Strings = @($script:tlsText) })
        $script:bindings = @()
        $script:certificates = @(
            [pscustomobject]@{ Name = 'mtasts-cert-mta-sts-example-com'; Thumbprint = 'BOUND'; ResourceId = 'bound-cert' },
            [pscustomobject]@{ Name = 'mtasts-cert-mta-sts-example-net'; Thumbprint = 'SECOND'; ResourceId = 'second-cert' },
            [pscustomobject]@{ Name = 'mtasts-cert-mta-sts-example-com-other-org'; Thumbprint = 'OTHER'; ResourceId = 'other-cert' }
        )
        $script:events = @()
        $script:domainArgs = @{ ResourceGroupName = 'review-rg'; FunctionAppName = 'review-func' }
        $script:removeArgs = $script:domainArgs + @{ StorageAccountName = 'reviewstore' }

        Mock Get-AzFunctionApp { [pscustomobject]@{ Name = 'review-func'; AppServicePlan = 'review-plan' } }
        Mock Get-AzFunctionAppSetting { @{ WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = 'AccountName=reviewstore;AccountKey=offline' } }
        Mock Get-AzWebApp { [pscustomobject]@{ HostNameSslStates = $script:bindings } }
        Mock Get-AzWebAppCertificate { $script:certificates }
        Mock Get-AzResource { $script:certificates }
        Mock Get-PSMTASTSCustomDomain {
            [pscustomobject]@{
                DefaultDomain = 'review-func.azurewebsites.net'
                CustomDomains = @('mta-sts.example.com', 'mta-sts.existing.example.com')
            }
        }
        Mock Get-ConnectionInformation { [pscustomobject]@{ State = 'Connected'; TokenExpiryTimeUTC = [datetime]::MaxValue } }
        Mock Get-AcceptedDomain {
            [pscustomobject]@{ Name = 'Example'; DomainName = 'example.com' }
            [pscustomobject]@{ Name = 'Example Net'; DomainName = 'example.net' }
        }
        Mock Invoke-RestMethod {
            param($Uri)
            $answer = switch -Regex ($Uri) {
                'type=CNAME' { [pscustomobject]@{ Type = 5; Data = 'review-func.azurewebsites.net.' }; break }
                'name=_mta-sts\.' { $script:mtaDoh; break }
                'name=_smtp\._tls\.' { $script:tlsDoh; break }
                'type=MX' { [pscustomobject]@{ Type = 15; Data = '0 example-com.mail.protection.outlook.com.' }; break }
                default { throw "Unexpected offline HTTP request: $Uri" }
            }
            [pscustomobject]@{ Status = 0; Answer = @($answer) }
        }
        Mock Invoke-WebRequest {
            [pscustomobject]@{ Content = "version: STSv1`nmode: enforce`nmx: *.mail.protection.outlook.com`nmax_age: 604800" }
        }
        Mock Resolve-DnsName {
            param($Name, $Type)
            switch ($Type) {
                CNAME { [pscustomobject]@{ NameHost = 'review-func.azurewebsites.net' } }
                TXT {
                    if ($Name -like '_mta-sts.*') { $script:mtaClassic } else { $script:tlsClassic }
                }
                MX { [pscustomobject]@{ NameExchange = 'example-com.mail.protection.outlook.com' } }
            }
        }
        Mock Set-AzWebApp {}
        Mock Remove-AzFunctionApp {}
        Mock Remove-AzStorageAccount {}
        Mock Remove-AzAppServicePlan {}
        Mock Remove-AzResource {}
        Mock Remove-AzWebAppCertificate {}
        Mock Send-PSMTASTSTelemetry {
            param($EventType, $Domain)
            $script:events += [pscustomobject]@{ EventType = $EventType; Domain = $Domain }
            $true
        }
    }

    Context 'Certificate identity' {
        It 'does not scan or delete certificates without SSL bindings' {
            Remove-PSMTASTSFunctionAppDeployment @script:removeArgs
            Should -Invoke Get-AzWebAppCertificate -Times 0 -Exactly
            Should -Invoke Remove-AzWebAppCertificate -Times 0 -Exactly
            Should -Invoke Remove-AzResource -Times 0 -Exactly
        }

        It 'deletes only the bound thumbprint, not a certificate with a similar name' {
            $script:bindings = @([pscustomobject]@{ Name = 'mta-sts.example.com'; Thumbprint = 'bound' })
            Remove-PSMTASTSFunctionAppDeployment @script:removeArgs
            Should -Invoke Remove-AzWebAppCertificate -Times 1 -Exactly -ParameterFilter {
                $ResourceGroupName -eq 'review-rg' -and $ThumbPrint -eq 'BOUND'
            }
            Should -Invoke Remove-AzWebAppCertificate -Times 1 -Exactly
            Should -Invoke Remove-AzResource -Times 0 -Exactly
        }

        It 'handles multiple bindings and repeated thumbprints without duplicate deletion' {
            $script:bindings = @(
                [pscustomobject]@{ Name = 'mta-sts.example.com'; Thumbprint = 'BOUND' },
                [pscustomobject]@{ Name = 'mta-sts.example.net'; Thumbprint = 'SECOND' },
                [pscustomobject]@{ Name = 'mta-sts.alias.example.com'; Thumbprint = 'BOUND' },
                [pscustomobject]@{ Name = 'review-func.azurewebsites.net'; Thumbprint = '' }
            )
            Remove-PSMTASTSFunctionAppDeployment @script:removeArgs
            Should -Invoke Remove-AzWebAppCertificate -Times 1 -Exactly -ParameterFilter { $ThumbPrint -eq 'BOUND' }
            Should -Invoke Remove-AzWebAppCertificate -Times 1 -Exactly -ParameterFilter { $ThumbPrint -eq 'SECOND' }
            Should -Invoke Remove-AzWebAppCertificate -Times 2 -Exactly
        }

        It 'does not delete certificates if the bound thumbprint is absent' {
            $script:bindings = @([pscustomobject]@{ Name = 'mta-sts.example.com'; Thumbprint = 'ABSENT' })
            Remove-PSMTASTSFunctionAppDeployment @script:removeArgs
            Should -Invoke Remove-AzWebAppCertificate -Times 0 -Exactly
            Should -Invoke Remove-AzResource -Times 0 -Exactly
        }

        It 'does not delete certificates in WhatIf mode' {
            $script:bindings = @([pscustomobject]@{ Name = 'mta-sts.example.com'; Thumbprint = 'BOUND' })
            Remove-PSMTASTSFunctionAppDeployment @script:removeArgs -WhatIf
            Should -Invoke Remove-AzWebAppCertificate -Times 0 -Exactly
        }

        It 'surfaces certificate deletion failures' {
            $script:bindings = @([pscustomobject]@{ Name = 'mta-sts.example.com'; Thumbprint = 'BOUND' })
            Mock Remove-AzWebAppCertificate { throw 'Simulated certificate deletion failure' }
            { Remove-PSMTASTSFunctionAppDeployment @script:removeArgs } | Should -Throw '*Simulated certificate deletion failure*'
        }
    }

    Context 'TXT record normalization and cardinality' {
        It 'recognizes MTA-STS and TLS-RPT with Classic=<Classic>' -TestCases @(
            @{ Classic = $true }, @{ Classic = $false }
        ) {
            param($Classic)
            $result = Test-PSMTASTSConfiguration -DomainName example.com -UseClassicDNS:$Classic -DisplayResult $false
            $result.MTA_STS_TXTRecord | Should -Be 'OK'
            $result.TLSRPT | Should -Be $script:tlsText
        }

        It 'ignores CNAME and unrelated TXT answers with Classic=<Classic>' -TestCases @(
            @{ Classic = $true }, @{ Classic = $false }
        ) {
            param($Classic)
            $script:mtaDoh = @([pscustomobject]@{ Type = 5; Data = 'policy.example.net.' }) +
                $script:mtaDoh + @([pscustomobject]@{ Type = 16; Data = '"unrelated TXT data"' })
            $script:tlsDoh = @([pscustomobject]@{ Type = 5; Data = 'reports.example.net.' }) +
                $script:tlsDoh + @([pscustomobject]@{ Type = 16; Data = '"unrelated TXT data"' })
            $script:mtaClassic += [pscustomobject]@{ Strings = @('unrelated TXT data') }
            $script:tlsClassic += [pscustomobject]@{ Strings = @('unrelated TXT data') }
            $result = Test-PSMTASTSConfiguration -DomainName example.com -UseClassicDNS:$Classic -DisplayResult $false
            $result.MTA_STS_TXTRecord | Should -Be 'OK'
            $result.TLSRPT | Should -Be $script:tlsText
        }

        It 'joins segments within one TXT record with Classic=<Classic>' -TestCases @(
            @{ Classic = $true }, @{ Classic = $false }
        ) {
            param($Classic)
            $script:mtaClassic = @([pscustomobject]@{ Strings = @('v=STSv1; id=', '20261111000000Z;') })
            $script:tlsClassic = @([pscustomobject]@{ Strings = @('v=TLSRPT', 'v1; rua=mailto:reports@example.com') })
            $script:mtaDoh = @([pscustomobject]@{ Type = 16; Data = '"v=STSv1; id=" "20261111000000Z;"' })
            $script:tlsDoh = @([pscustomobject]@{ Type = 16; Data = '"v=TLSRPT""v1; rua=mailto:reports@example.com"' })
            $result = Test-PSMTASTSConfiguration -DomainName example.com -UseClassicDNS:$Classic -DisplayResult $false
            $result.MTA_STS_TXTRecord | Should -Be 'OK'
            $result.TLSRPT | Should -Be $script:tlsText
        }

        It 'still rejects genuinely duplicate <Record> records with Classic=<Classic>' -TestCases @(
            @{ Classic = $true; Record = 'MTA-STS' }, @{ Classic = $false; Record = 'MTA-STS' },
            @{ Classic = $true; Record = 'TLSRPT' }, @{ Classic = $false; Record = 'TLSRPT' }
        ) {
            param($Classic, $Record)
            if ($Record -eq 'MTA-STS') {
                $script:mtaDoh += $script:mtaDoh[0]
                $script:mtaClassic += $script:mtaClassic[0]
            } else {
                $script:tlsDoh += $script:tlsDoh[0]
                $script:tlsClassic += $script:tlsClassic[0]
            }
            { Test-PSMTASTSConfiguration -DomainName example.com -UseClassicDNS:$Classic -DisplayResult $false } |
                Should -Throw "*Multiple $Record TXT records found*"
        }

        It 'reports missing records without throwing' {
            $script:mtaDoh = @()
            $script:tlsDoh = @()
            $result = Test-PSMTASTSConfiguration -DomainName example.com -DisplayResult $false
            $result.MTA_STS_TXTRecord | Should -Be 'TXT record was not found.'
            $result.MTA_STS_OVERALL | Should -Be 'ISSUE_FOUND'
            $result.TLSRPT | Should -BeNullOrEmpty
        }

        It 'exports the same normalized TXT values with Classic=<Classic>' -TestCases @(
            @{ Classic = $true }, @{ Classic = $false }
        ) {
            param($Classic)
            $path = Join-Path $TestDrive "export-$Classic.csv"
            Export-PSMTASTSDomainsFromExo -DomainName example.com -UseClassicDNS:$Classic -DisplayResult $false -CsvPath $path
            $rows = @(Import-Csv $path -Delimiter ';')
            $rows | Should -HaveCount 2
            $rows[0].MTA_STS_TXTRecord | Should -Be $script:mtaText
            $rows[0].TLSRPT | Should -Be $script:tlsText
        }

        It 'decodes quoted and decimal DNS escapes without discarding literal quotes' {
            $record = [pscustomobject]@{ Type = 16; Data = '"first\032\"quoted\"" "second\\part"' }
            ($record | ConvertFrom-PSMTASTSTxtRecord) | Should -Be 'first "quoted"second\part'
        }

        It 'rejects malformed DNS TXT presentation data: <Data>' -TestCases @(
            @{ Data = '"unterminated' }, @{ Data = '"valid" trailing garbage' }, @{ Data = '"invalid\999"' }
        ) {
            param($Data)
            { [pscustomobject]@{ Type = 16; Data = $Data } | ConvertFrom-PSMTASTSTxtRecord } | Should -Throw '*Malformed DNS TXT*'
        }
    }

    Context 'Telemetry follows approved successful changes' {
        It 'sends no events without opt-in for <Operation>' -TestCases @(
            @{ Operation = 'Add' }, @{ Operation = 'Remove' }
        ) {
            param($Operation)
            if ($Operation -eq 'Add') {
                Add-PSMTASTSCustomDomain @script:domainArgs -DomainName new.example.com -SkipCAACheck -DoNotAddManagedCertificate
            } else {
                $script:certificates = @()
                Remove-PSMTASTSCustomDomain @script:domainArgs -DomainName example.com
            }
            $script:events | Should -BeNullOrEmpty
        }

        It 'sends one event only for the changed domain in <Operation> and suppresses helper output' -TestCases @(
            @{ Operation = 'Add' }, @{ Operation = 'Remove' }
        ) {
            param($Operation)
            if ($Operation -eq 'Add') {
                $output = @(Add-PSMTASTSCustomDomain @script:domainArgs -DomainName new.example.com,existing.example.com -SkipCAACheck -DoNotAddManagedCertificate -SendTelemetry)
                $expectedDomain = 'new.example.com'
            } else {
                $script:certificates = @()
                $output = @(Remove-PSMTASTSCustomDomain @script:domainArgs -DomainName example.com,missing.example.com -SendTelemetry)
                $expectedDomain = 'example.com'
            }
            $output | Should -BeNullOrEmpty
            $script:events | Should -HaveCount 1
            $script:events[0].Domain | Should -Be $expectedDomain
            $script:events[0].EventType | Should -Be "${Operation}Domain"
            Should -Invoke Set-AzWebApp -Times 1 -Exactly
        }

        It 'sends no events in WhatIf mode for <Operation>' -TestCases @(
            @{ Operation = 'Add' }, @{ Operation = 'Remove' }
        ) {
            param($Operation)
            if ($Operation -eq 'Add') {
                Add-PSMTASTSCustomDomain @script:domainArgs -DomainName new.example.com -SkipCAACheck -DoNotAddManagedCertificate -SendTelemetry -WhatIf
            } else {
                $script:certificates = @()
                Remove-PSMTASTSCustomDomain @script:domainArgs -DomainName example.com -SendTelemetry -WhatIf
            }
            $script:events | Should -BeNullOrEmpty
            Should -Invoke Set-AzWebApp -Times 0 -Exactly
        }

        It 'does not emit success telemetry after an Azure update error for <Operation>' -TestCases @(
            @{ Operation = 'Add' }, @{ Operation = 'Remove' }
        ) {
            param($Operation)
            Mock Set-AzWebApp { Write-Error 'Simulated Azure update failure' }
            if ($Operation -eq 'Add') {
                { Add-PSMTASTSCustomDomain @script:domainArgs -DomainName new.example.com -SkipCAACheck -DoNotAddManagedCertificate -SendTelemetry -ErrorAction Continue } |
                    Should -Throw '*Simulated Azure update failure*'
            } else {
                { Remove-PSMTASTSCustomDomain @script:domainArgs -DomainName example.com -SendTelemetry -ErrorAction Continue } |
                    Should -Throw '*Simulated Azure update failure*'
            }
            $script:events | Should -BeNullOrEmpty
        }

        It 'sends no event when confirmation is declined for <Operation>' -TestCases @(
            @{ Operation = 'Add' }, @{ Operation = 'Remove' }
        ) {
            param($Operation)
            $hostInstance = New-Object PSMTASTSDecliningHost
            $runspace = [runspacefactory]::CreateRunspace($hostInstance)
            $runspace.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $runspace
            try {
                $null = $ps.AddScript({
                    param($repo, $operation)
                    . "$repo\PS.MTA-STS\functions\$operation-PSMTASTSCustomDomain.ps1"
                    $script:events = @()
                    $script:mutations = 0
                    function Get-AzContext { [CmdletBinding()] param() 'offline' }
                    function Get-AzFunctionApp { [CmdletBinding()] param($ResourceGroupName, $Name) 'offline' }
                    function Get-PSMTASTSCustomDomain {
                        [CmdletBinding()] param($ResourceGroupName, $FunctionAppName)
                        [pscustomobject]@{ DefaultDomain = 'review-func.azurewebsites.net'; CustomDomains = @('mta-sts.example.com', 'mta-sts.other.example.com') }
                    }
                    function Invoke-RestMethod {
                        [CmdletBinding()] param($Uri)
                        [pscustomobject]@{ Answer = @([pscustomobject]@{ Type = 5; Data = 'review-func.azurewebsites.net.' }) }
                    }
                    function Set-AzWebApp {
                        [CmdletBinding()] param($ResourceGroupName, $Name, $HostNames)
                        $script:mutations++
                    }
                    function Send-PSMTASTSTelemetry {
                        param($TelemetryEndpoint, $EventType, $Domain)
                        $script:events += "$EventType $Domain"
                        $true
                    }
                    function Get-AzWebAppCertificate { [CmdletBinding()] param($ResourceGroupName) }
                    if ($operation -eq 'Add') {
                        Add-PSMTASTSCustomDomain -ResourceGroupName review-rg -FunctionAppName review-func -DomainName new.example.com -SkipCAACheck -DoNotAddManagedCertificate -SendTelemetry -Confirm
                    } else {
                        Remove-PSMTASTSCustomDomain -ResourceGroupName review-rg -FunctionAppName review-func -DomainName example.com -SendTelemetry -Confirm
                    }
                    [pscustomobject]@{ Mutations = $script:mutations; Events = $script:events }
                }).AddArgument($script:repo).AddArgument($Operation)
                $report = $ps.Invoke()
                $ps.Streams.Error | Should -BeNullOrEmpty
                $hostInstance.ReviewUI.Prompts | Should -Be 1
                $report.Mutations | Should -Be 0
                $report.Events | Should -BeNullOrEmpty
            } finally {
                $ps.Dispose()
                $runspace.Dispose()
            }
        }
    }
}
