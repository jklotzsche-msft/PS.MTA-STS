function Test-PSMTASTSConfiguration {
    <#
        .SYNOPSIS
        Test-PSMTASTSConfiguration checks if MTA-STS is configured correctly for all domains in a CSV file.

        .DESCRIPTION
        Test-PSMTASTSConfiguration checks if MTA-STS is configured correctly for all domains in a CSV file.
        It checks if the...
        - ...TXT record is configured correctly,
        - ...CNAME record is configured correctly,
        - ...policy file is available and
        - ...MX record is configured correctly.

        .PARAMETER DisplayResult
        Provide a Boolean value, if the result should be displayed in the console. Default is $true.

        .PARAMETER CsvPath
        Provide path to csv file with accepted domains.
        Csv file should have one column with header "DomainName" and list of domains in each row.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .PARAMETER DnsServer
        Provide IP address of DNS server to use for DNS queries. Default is 8.8.8.8 (Google DNS).

        .PARAMETER ExportResult
        Switch Parameter. Export result to CSV file.
        
        .PARAMETER ResultPath
        Provide path to CSV file where result should be exported. Default is "C:\temp\mta-sts-result.csv".

        .PARAMETER ExoHost
        Provide a String containing the host name of the MX record, which should be used to check, if the MX record points to Exchange Online. Default is *.mail.protection.outlook.com.

        .PARAMETER WhatIf
        Switch to run the command in a WhatIf mode.

        .PARAMETER Confirm
        Switch to run the command in a Confirm mode.

        .EXAMPLE
        Test-PSMTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "MTA-STS-FunctionApp"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "MTA-STS-FunctionApp".

        .EXAMPLE
        Test-PSMTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "MTA-STS-FunctionApp" -ExportResult -ResultPath "C:\temp\mta-sts-result.csv"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "MTA-STS-FunctionApp". It also exports result to "C:\temp\mta-sts-result.csv".
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $CsvPath,
        
        [Parameter(Mandatory = $true)]
        [String]
        $FunctionAppName,

        [String]
        $DnsServer = "8.8.8.8",

        [Bool]
        $DisplayResult = $true,

        [Parameter(ParameterSetName = "ExportResult")]
        [Switch]
        $ExportResult,
    
        [Parameter(Mandatory = $true, ParameterSetName = "ExportResult")]
        [String]
        $ResultPath,

        [Parameter(DontShow = $true)]
        [String]
        $ExoHost = "*.mail.protection.outlook.com"
    )

    process {
        trap {
            Write-Error $_
            return
        }

        # Prepare variables
        $csv = Import-Csv -Path $CsvPath -Encoding UTF8 -Delimiter ";" -ErrorAction Stop
        $txtRecordContent = "v=STSv1; id=*Z;"
        $mtaStsPolicyFileContent = @"
version: STSv1
mode: enforce
mx: $ExoHost
max_age: 604800
"@
        $counter = 1
        $result = @()

        # Loop through all domains
        foreach ($line in $csv) {
            Write-Verbose "$counter / $($csv.count) - $($line.DomainName)"

            # Prepare result object
            $resultObject = [PSCustomObject]@{
                DomainName         = $line.DomainName
                Host               = "$FunctionAppName.azurewebsites.net"
                MTA_STS_TXT        = ""
                MTA_STS_CNAME      = ""
                MTA_STS_PolicyFile = ""
                MTA_STS_MX         = ""
                MTA_STS_OVERALL    = "OK"
            }

            # Prepare MTA-STS name
            $mtaStsName = "mta-sts.$($line.DomainName)"

            # Check MTA-STS TXT record
            Write-Verbose "...Checking MTA-STS TXT record for $mtaStsName."
            $txtRecord = Resolve-DnsName -Name "_$mtaStsName" -Type TXT -Server $DnsServer -ErrorAction SilentlyContinue
            if ($txtRecord -and ($txtRecord.strings -like $txtRecordContent)) {
                $resultObject.MTA_STS_TXT = "OK"
            }
            elseif ($txtRecord -and ($txtRecord.strings -notlike $txtRecordContent)) {
                $resultObject.MTA_STS_TXT = "TXT record does not contain the expected content. The following content was found: $($txtRecord.strings -join ", ")"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
            else {
                $resultObject.MTA_STS_TXT = "TXT record was not found. Please check if the TXT record for $mtaStsName points to the Function App $($resultObject.Host)."
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            # Check MTA-STS CNAME record
            Write-Verbose "...Checking MTA-STS CNAME record for $mtaStsName."
            $cnameRecord = Resolve-DnsName -Name $mtaStsName -Type CNAME -Server $DnsServer -ErrorAction SilentlyContinue
            if ($cnameRecord -and ($resultObject.Host -eq $cnameRecord.NameHost)) {
                $resultObject.MTA_STS_CNAME = "OK"
            }
            elseif ($cnameRecord -and ($resultObject.Host -ne $cnameRecord.NameHost)) {
                $resultObject.MTA_STS_CNAME = "CNAME record does not contain the expected content. The following content was found: $($cnameRecord.NameHost -join ", ")"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
            else {
                $resultObject.MTA_STS_CNAME = "CNAME record was not found. Please check if the CNAME record for $mtaStsName points to the Function App $($resultObject.Host)."
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
    
            # Check MTA-STS Policy File
            Write-Verbose "...Checking MTA-STS Policy File for $mtaStsName."
            $mtaStsPolicyUrl = "https://$mtaStsName/.well-known/mta-sts.txt"
            $policyFile = $null
            
            try {
                $policyFile = Invoke-WebRequest -Uri $mtaStsPolicyUrl -ErrorAction SilentlyContinue
            }
            catch {
                $resultObject.MTA_STS_PolicyFile = $_.Exception.Message
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            if ($policyFile -and ($policyFile.Content -eq $mtaStsPolicyFileContent)) {
                $resultObject.MTA_STS_PolicyFile = "OK"
            }
            if ($policyFile -and ($policyFile.Content -ne $mtaStsPolicyFileContent)) {
                $resultObject.MTA_STS_PolicyFile = "Policy file does not contain the expected content. The following content was found: $($policyFile.Content)"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            # Check MX record
            Write-Verbose "...Checking MX record for $($line.DomainName)."
            $mxRecord = Resolve-DnsName -Name $line.DomainName -Type MX -Server $DnsServer -ErrorAction SilentlyContinue
            if (($mxRecord.NameExchange.count -eq 1) -and ($mxRecord.NameExchange -like $ExoHost)) {
                $resultObject.MTA_STS_MX = "OK"
            }
            elseif (($mxRecord.NameExchange.count -ne 1) -or ($mxRecord.NameExchange -notlike $ExoHost)) {
                $resultObject.MTA_STS_MX = "MX record does not contain the expected content. The following content was found: $($mxRecord.NameExchange -join ", ")"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
            else {
                $resultObject.MTA_STS_MX = "MX record was not found. Please check if the MX record for $($line.DomainName) points to Exchange Online."
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            $result += $resultObject
            $counter++
        }

        # Output the result in a new PowerShell window
        if($DisplayResult) {
            Write-Warning "Please check the results in the new PowerShell window."
            $result | Out-GridView -Title "Test MTA-STS Configuration"
        }

        # Export result to CSV
        if ($ExportResult) {
            $result | Export-Csv -Path $ResultPath -Encoding UTF8 -Delimiter ";" -NoTypeInformation
        }
    }
}