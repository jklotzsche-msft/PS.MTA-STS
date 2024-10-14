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

        .PARAMETER CsvPath
        Provide path to csv file with accepted domains.
        Csv file should have one column with header "DomainName" and list of domains in each row.

        .PARAMETER DomainName
        Provide list of domains.

        .PARAMETER DnsServer
        Provide IP address of DNS server to use for DNS queries. Default is 8.8.8.8 (Google DNS).

        .PARAMETER DisplayResult
        Provide a Boolean value, if the result should be displayed in the console. Default is $true.

        .PARAMETER ExportResult
        Switch Parameter. Export result to CSV file.
        
        .PARAMETER ResultPath
        Provide path to CSV file where result should be exported. Default is "C:\temp\mta-sts-result.csv".

        .PARAMETER CsvEncoding
        Provide encoding of csv file. Default is "UTF8".

        .PARAMETER CsvDelimiter
        Provide delimiter of csv file. Default is ";".

        .PARAMETER ExoHostName
        Provide a list of hostnames, which should be included in the MTA-STS policy.
        The list of hostnames must be valid, which means that they must be valid domain names.
        For example, 'contoso.com' or 'fabrikam.com'.
        You can also start with a wildcard character to include subdomains.
        So if you want to include all subdomains of 'contoso.com', you can add '*.contoso.com'.

        .EXAMPLE
        Test-PSMTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "func-MTA-STS"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "func-MTA-STS".

        .EXAMPLE
        Test-PSMTASTSConfiguration -DomainName "contoso.com", "fabrikam.com" -FunctionAppName "func-MTA-STS" -ExoHostName "mail.contoso.com"

        Checks if MTA-STS is configured correctly for domains "contoso.com" and "fabrikam.com" in Function App "func-MTA-STS". The ExoHostName parameter is used to add the MX record for "mail.contoso.com" to the MTA-STS policy file tests.

        .EXAMPLE
        Test-PSMTASTSConfiguration -CsvPath "C:\temp\accepted-domains.csv" -FunctionAppName "func-MTA-STS" -ExportResult -ResultPath "C:\temp\mta-sts-result.csv"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and checks if MTA-STS is configured correctly for each domain in Function App "func-MTA-STS". It also exports result to "C:\temp\mta-sts-result.csv".
    #>
    [CmdletBinding(DefaultParameterSetName = "Csv")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "Csv")]
        [string]
        $CsvPath,

        [Parameter(Mandatory = $true, ParameterSetName = "DomainName")]
        [string[]]
        $DomainName,

        [String]
        $DnsServer = "8.8.8.8",

        [Bool]
        $DisplayResult = $true,

        [Switch]
        $ExportResult,
    
        [String]
        $ResultPath = (Join-Path -Path $env:TEMP -ChildPath "$(Get-Date -Format yyyyMMddhhmmss)_mta-sts-test-result.csv"),

        [string]
        $CsvEncoding = "UTF8",

        [string]
        $CsvDelimiter = ";",

        [ValidateScript({
                # the provided list of hostnames must be valid, which means that they must be valid domain names
                # Domain Names cannot start with a dot, so we need to check for that
                # Additionally, they can start with a wildcard, if subdomains should be included
                foreach ($hostname in $_) {
                    if ($hostname -notmatch "^[a-zA-Z0-9][a-zA-Z0-9-_.]*$" -and $hostname -notmatch "^\*.[a-zA-Z0-9][a-zA-Z0-9-_.]*$") {
                        throw "MX endpoint '$hostname' is not valid. The name can contain only letters, numbers, hyphens, underscores and periods. You can also start with a wildcard character to include subdomains."
                    }

                    if ($hostname -like "*mail.protection.outlook.com") {
                        throw "MX endpoint '$hostname' cannot be added, because the DNS zone '*.mail.protection.outlook.com' will be added automatically. Please remove it from the list."
                    }
                }
                # if the list of entries is valid, return $true
                $true
            })]
        [String[]]
        $ExoHostName
    )

    begin {
        # Trap errors
        trap {
            throw $_
        }

        # Preset ActionPreference to Stop, if not set by user through common parameters
        if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $local:ErrorActionPreference = "Stop" }

        # Prepare result array
        $result = @()

        # Import csv file with accepted domains
        if ($CsvPath) {
            Write-Verbose "Importing csv file from $CsvPath"
            $domainList = Import-Csv -Path $CsvPath -Encoding $CsvEncoding -Delimiter $CsvDelimiter | Select-Object -ExpandProperty DomainName
        }
    }

    process {
        # Import domains from input parameter
        if ($DomainName) {
            Write-Verbose "Creating array of domains from input parameter"
            $domainList = @()
            foreach ($domain in $DomainName) { $domainList += $domain }
        }

        # Check, if domains have correct format
        foreach ($domain in $domainList) {
            if ($domain -notmatch "^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$") {
                throw -Message "Domain $domain has incorrect format. Please provide domain in format 'contoso.com'."
            }
        }

        # Prepare variables
        ## MTA-STS TXT Record
        $txtRecordContent = "v=STSv1; id=*Z;"
        ## MTA-STS Policy File
        $mtaStsPolicyFileContent = @"
version: STSv1
mode: *
~mxRecords~
max_age: 604800
"@
        [string]$mxHostNames = "mx: *.mail.protection.outlook.com`n" # Add default MX record, which is always added
        foreach ($hostName in $ExoHostName) {
            $mxHostNames += "mx: $hostName`n" # Add MX record for each specified hostname
        }
        $mtaStsPolicyFileContent = $mtaStsPolicyFileContent.replace("~mxRecords~", ($mxHostNames.TrimEnd("`n")))
        ## Counter for verbose output
        $counter = 1

        # Loop through all domains
        $domainListCount = $domainList.Count
        foreach ($domain in $domainList) {
            Write-Verbose "Checking $counter / $($domainList.count) - $($domain)"

            $CNameHost = Resolve-DnsName -Name "mta-sts.$Domain" -Type "CNAME"
            If ($Null -ne $CNameHost) {
                $Hostname = $CNameHost.NameHost
            }
            else {
                $Hostname = ""
            }

            #Progress Bar
            [int]$Percent = 100 / $domainListCount * $counter
            Write-Progress -Activity "Test in Progress" -Status "$Percent% Complete:" -PercentComplete $Percent

            # Prepare result object
            $resultObject = [PSCustomObject]@{
                DomainName            = $domain
                Host                  = $Hostname
                MX_Record_Pointing_To = ""
                # MX_Record_Result      = ""
                MTA_STS_CNAME         = ""
                MTA_STS_Policy        = ""
                MTA_STS_PolicyContent = ""
                MTA_STS_TXTRecord     = ""
                MTA_STS_OVERALL       = "OK"
                TLSRPT                = ""
            }

            # Checking MTA-STS TXT Record
            # Example: _mta-sts.example.com. IN TXT "v=STSv1; id=20160831085700Z"
            $mtaStsDNSHost = "_mta-sts." + $domain
            $mtaStsTXTRecord = Resolve-PSMTASTSDnsName -Name $mtaStsDNSHost -Type TXT -Server $DnsServer -ErrorAction SilentlyContinue | Where-Object { $_.Strings -match "v=STSv1" }

            if ($mtaStsTXTRecord -and ($mtaStsTXTRecord.strings -like $txtRecordContent)) {
                $resultObject.MTA_STS_TXTRecord = "OK"
            }
            elseif ($mtaStsTXTRecord -and ($mtaStsTXTRecord.strings -notlike $txtRecordContent)) {
                $resultObject.MTA_STS_TXTRecord = "TXT record does not contain the expected content. The following content was found: $($mtaStsTXTRecord.strings -join ", ")"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
            else {
                $resultObject.MTA_STS_TXTRecord = "TXT record was not found."
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            # Check MTA-STS CNAME record
            $mtaStsName = "mta-sts." + $domain
            $cnameRecord = Resolve-PSMTASTSDnsName -Name $mtaStsName -Type CNAME -Server $DnsServer -ErrorAction SilentlyContinue

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
    
            # Checking MTA-STS Policy
            $mtaStsUri = "https://mta-sts.{0}/.well-known/mta-sts.txt" -f $domain
            Write-Verbose "...checking MTA-STS Policy file at $mtaStsUri"
            
            try {
                $mtaStsPolicyResponse = Invoke-WebRequest -Uri $mtaStsUri -TimeoutSec 20 -ErrorAction Stop
                $resultObject.MTA_STS_PolicyContent = ($mtaStsPolicyResponse.Content).Trim()
            }
            catch {
                $resultObject.MTA_STS_Policy = "ERROR"
                $resultObject.MTA_STS_PolicyContent = $_.Exception.Message
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            if (($resultObject.MTA_STS_PolicyContent -like $mtaStsPolicyFileContent) -and (($resultObject.MTA_STS_PolicyContent -like "*mode: enforce*") -or ($resultObject.MTA_STS_PolicyContent -like "*mode: testing*") -or ($resultObject.MTA_STS_PolicyContent -like "*mode: none*"))) {
                $resultObject.MTA_STS_Policy = "OK"
            }
            else {
                $resultObject.MTA_STS_Policy = "Policy file does not contain the expected content.`nCurrently allowed mx records are: $($mxHostNames -join ", ").`nHave you forgotten to add the MX records to the policy file using the '-ExoHostName' parameter?"
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }

            # Checking TLSRPT Record
            # Example: _smtp._tls.example.com. IN TXT "v=TLSRPTv1;rua=mailto:reports@example.com"
            $tlsRptDNSHost = "_smtp._tls." + $domain
            $tlsRptRecord = Resolve-PSMTASTSDnsName -Name $tlsRptDNSHost -Type TXT -Server $DnsServer -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_.Strings -like "v=TLSRPTv1*" }

            if ($null -ne $tlsRptRecord) {
                $resultObject.TLSRPT = $tlsRptRecord.Strings[0]
            }

            # Checking MX Record
            # Example: example.com. IN MX 0 example-com.mail.protection.outlook.com.
            $mxRecord = Resolve-PSMTASTSDnsName -Name $domain -Type MX -Server $DnsServer -ErrorAction SilentlyContinue

            $resultObject.MX_Record_Pointing_To = $mxRecord.NameExchange -join ", "

            <# Removed the MX record check, because we cannot tell foreach domain, which MX record is correct. Previously, this was possible, as we only checked for the single Exchange Online MX record *.mail.protection.outlook.com.
            # Check if the domain is an onmicrosoft.com domain
            if ($domain -like "*.onmicrosoft.com") {
                $resultObject.MX_Record_Result = "WARNING: You cannot configure MTA-STS for an onmicrosoft.com domain."
                $resultObject.MTA_STS_OVERALL = "ISSUE_FOUND"
            }
            # Check if the MX record points to Exchange Online
            elseif (($mxRecord.NameExchange.count -eq 1) -and ($mxRecord.NameExchange -like $ExoHost)) {
                # MX record points to Exchange Online (only)
                $resultObject.MX_Record_Result = "OK"
            }
            # Check if the MX record points to another host than Exchange Online or if multiple MX records were found
            elseif (($mxRecord.NameExchange.count -gt 1) -or ($mxRecord.NameExchange -notlike $ExoHost)) {
                $resultObject.MX_Record_Result = "WARNING: MX Record does not point to Exchange Online (only). The following host(s) was/were found: $($mxRecord.NameExchange -join ", ")"
            }
            # Assume, that no MX record was found
            else {
                $resultObject.MX_Record_Result = "ERROR: No MX record found. Please assure, that the MX record for $domain points to Exchange Online."
            }
            #>

            # Add the result to the result array
            Write-Verbose "...adding result to result array."
            $result += $resultObject

            # Increase the counter for verbose output
            $counter++
        }

        # Output the result in a new PowerShell window
        if ($DisplayResult) {
            Write-Warning "Please check the results in the new PowerShell window."
            $result | Out-GridView -Title "Test MTA-STS Configuration"
        }

        # Export result to CSV
        if ($ExportResult) {
            Write-Warning "Exporting result to $ResultPath"
            $result | Export-Csv -Path $ResultPath -Encoding UTF8 -Delimiter ";" -NoTypeInformation
        }
    }
}