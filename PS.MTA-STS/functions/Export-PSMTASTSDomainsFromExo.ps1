function Export-PSMTASTSDomainsFromExo {
    <#
        .SYNOPSIS
        Export-PSMTASTSDomainsFromExo

        .DESCRIPTION
        This script exports all domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to a .csv file.

        .PARAMETER DisplayResult
        Provide a Boolean value, if the result should be displayed in the console. Default is $true.

        .PARAMETER CsvPath
        Provide a String containing the path to the .csv file, where the result should be exported to.

        .PARAMETER DomainName
        Provide a PSCustomObject containing the result of Get-AcceptedDomain. If not provided, the script will run Get-AcceptedDomain itself.

        .PARAMETER DnsServer
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

        .PARAMETER ExoHost
        Provide a String containing the host name of the MX record, which should be used to check, if the MX record points to Exchange Online. Default is *.mail.protection.outlook.com.

        .PARAMETER CsvEncoding
        Provide encoding of csv file. Default is "UTF8".

        .PARAMETER CsvDelimiter
        Provide delimiter of csv file. Default is ";".

        .PARAMETER DnsServer
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

        .EXAMPLE
        Export-PSMTASTSDomainsFromExo -CsvPath "C:\Temp\ExoDomains.csv"

        Gets accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\ExoDomains.csv".

        .EXAMPLE
        Get-AcceptedDomain -ResultSize 10 | Export-PSMTASTSDomainsFromExo -CsvPath "C:\Temp\ExoDomains.csv"

        Gets 10 accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\ExoDomains.csv".
        If you want to filter the accepted domains first, you can do so and pipe it to the Export-PSMTASTSDomainsFromExo function.

        .EXAMPLE
        "contoso.com","fabrikam.com" | Export-PSMTASTSDomainsFromExo -CsvPath "C:\Temp\ExoDomains.csv"

        Checks if the MX record points to Exchange Online for the domains "contoso.com" and "fabrikam.com". The result is exported to "C:\Temp\ExoDomains.csv".

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding()]
    param(
        [string]
        $CsvPath = (Join-Path -Path $env:TEMP -ChildPath "$(Get-Date -Format yyyyMMddhhmmss)_mta-sts-export.csv"),

        [Parameter(ValueFromPipeline = $true)]
        [PSObject[]]
        $DomainName,

        [Bool]
        $DisplayResult = $true,

        [String]
        $DnsServer = "8.8.8.8",

        [string]
        $CsvEncoding = "UTF8",

        [string]
        $CsvDelimiter = ";",

        [Parameter(DontShow = $true)]
        [String]
        $ExoHost = "*.mail.protection.outlook.com"
    )
    
    begin {
        # Prepare result array
        $result = @()
    }
    
    process {
        # Preset ErrorActionPreference to Stop
        $ErrorActionPreference = "Stop"

        # Trap errors
        trap {
            Write-Error $_
            return
        }
        
        # Connect to Exchange Online, if not already connected
        $exchangeConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue | Sort-Object -Property TokenExpiryTimeUTC -Descending | Select-Object -First 1 -ExpandProperty State
        if (($exchangeConnection -ne "Connected") -and ($null -eq $DomainName)) {
            Write-Warning "Connecting to Exchange Online"
            $null = Connect-ExchangeOnline -ShowBanner:$false
        }

        # Get either full list of accepted domains or the provided list of accepted domains
        if($null -eq $DomainName) {
            Write-Verbose "Getting all domains from Exchange Online and checking MX-Record. Please wait..."
            $acceptedDomains = Get-AcceptedDomain -ResultSize unlimited -ErrorAction Stop
        }
        else {
            Write-Verbose "Checking MX-Record for provided domains. Please wait..."
            $acceptedDomains = $DomainName | Get-AcceptedDomain -ErrorAction Stop
        }
        $acceptedDomains = $acceptedDomains | Sort-Object -Property Name

        $counter = 1
        foreach ($acceptedDomain in $acceptedDomains) {
            Write-Verbose "Checking $counter / $($acceptedDomains.count) - $($acceptedDomain.DomainName)"
            # Prepare result object
            $resultObject = [PSCustomObject]@{
                Name                  = $acceptedDomain.Name        # Name of the domain
                DomainName            = $acceptedDomain.DomainName  # Domain name
                MX_Record_Pointing_To = ""                          # MX Record pointing to Exchange Online or other host(s) found? (Yes/No)
                MTA_STS_TXTRecord     = ""                          # MTA-STS TXT Record
                MTA_STS_Policy        = ""                          # MTA-STS Policy, if available
                MTA_STS_CanBeUsed     = ""                          # Can MTA-STS be used? (Yes/No)
                TLSRPT                = ""                          # TLSRPT Record, if available
            }

            # Checking MTA-STS TXT Record
            # Example: _mta-sts.example.com. IN TXT "v=STSv1; id=20160831085700Z"
            $mtaStsDNSHost = "_mta-sts." + $acceptedDomain.DomainName
            $mtaStsTXTRecord = Resolve-PSMTASTSDnsName -Name $mtaStsDNSHost -Type TXT -Server $DnsServer -ErrorAction Stop | Where-Object {$_.Strings -match "v=STSv1"}

            if ($null -ne $mtaStsTXTRecord) {
                $resultObject.MTA_STS_TXTRecord = $mtaStsTXTRecord.strings -join " | " # Strings are joined, because multiple strings can be returned
            }

            # Checking MTA-STS Policy
            <# Example:
                version: STSv1
                mode: enforce
                mx: *.mail.protection.outlook.com
                max_age: 604800
            #>
            $mtaStsUri = "https://mta-sts.{0}/.well-known/mta-sts.txt" -f $acceptedDomain.DomainName
            Write-Verbose "...checking MTA-STS Policy file at $mtaStsUri"
            try {
                # Try to get the MTA-STS Policy file
                $mtaStsPolicyResponse = Invoke-WebRequest -URI $mtaStsUri -TimeoutSec 20 -ErrorAction SilentlyContinue
                $resultObject.MTA_STS_Policy = ($mtaStsPolicyResponse.Content).Trim() #.Replace("`r`n","")
            }
            catch {
                # If the MTA-STS Policy file is not available or other issues occur, the result will be set to "ERROR: $($_.Exception.InnerException.Message)"
                $resultObject.MTA_STS_Policy = "ERROR: $($_.Exception.InnerException.Message)"
            }

            # Checking TLSRPT Record
            # Example: _smtp._tls.example.com. IN TXT "v=TLSRPTv1;rua=mailto:reports@example.com"
            $tlsRptDNSHost = "_smtp._tls." + $acceptedDomain.DomainName
            $tlsRptRecord = Resolve-PSMTASTSDnsName -Name $tlsRptDNSHost -Type TXT -Server $DnsServer -ErrorAction Stop | Where-Object {$_.Strings -like "v=TLSRPTv1*"}

            if ($null -ne $tlsRptRecord) {
                $resultObject.TLSRPT = $tlsRptRecord.Strings[0]
            }

            # Checking MX Record
            # Example: example.com. IN MX 0 example-com.mail.protection.outlook.com.
            $mxRecord = Resolve-PSMTASTSDnsName -Name $acceptedDomain.DomainName -Type MX -Server $DnsServer -ErrorAction Stop

            $resultObject.MTA_STS_CanBeUsed = "No" # Default value
            # Check if the domain is an onmicrosoft.com domain
            if ($acceptedDomain.DomainName -like "*.onmicrosoft.com") {
                $resultObject.MX_Record_Pointing_To = "WARNING: You cannot configure MTA-STS for an onmicrosoft.com domain."
            }
            # Check if the MX record points to Exchange Online
            elseif (($mxRecord.NameExchange.count -eq 1) -and ($mxRecord.NameExchange -like $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = $mxRecord.NameExchange
                # Check if MTA-STS can be used (TXT record and Policy file are configured)
                if (("" -eq $resultObject.MTA_STS_TXTRecord) -and ("" -eq $resultObject.MTA_STS_Policy)) {
                    $resultObject.MTA_STS_CanBeUsed = "Yes"
                }
                elseif (("" -ne $resultObject.MTA_STS_TXTRecord) -and ($resultObject.MTA_STS_Policy -like "ERROR: *" -or "" -eq $resultObject.MTA_STS_Policy)) {
                    $resultObject.MTA_STS_CanBeUsed = "WARNING: MTA-STS TXT record is configured, but MTA-STS Policy file is not available."
                }
                elseif (("" -eq $resultObject.MTA_STS_TXTRecord) -and ("" -ne $resultObject.MTA_STS_Policy)) {
                    $resultObject.MTA_STS_CanBeUsed = "INFORMATION: MTA-STS TXT record is not configured, but MTA-STS Policy file is configured."
                }
                else {
                    $resultObject.MTA_STS_CanBeUsed = "COMPLETED: MTA-STS TXT record and MTA-STS Policy file are configured. Please double-check the content of the MTA-STS Policy file."
                }
            }
            # Check if the MX record points to another host than Exchange Online or if multiple MX records were found
            elseif (($mxRecord.NameExchange.count -gt 1) -or ($mxRecord.NameExchange -notlike $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = "WARNING: MX Record does not point to Exchange Online (only). The following host(s) was/were found: $($mxRecord.NameExchange -join ", ")"
            }
            # Assume, that no MX record was found
            else {
                $resultObject.MX_Record_Pointing_To = "ERROR: No MX record found. Please assure, that the MX record for $($acceptedDomain.DomainName) points to Exchange Online."
            }
        
            # Add the result to the result array
            Write-Verbose "...adding result to result array."
            $result += $resultObject

            # Increase the counter for verbose output
            $counter++
        }
    }
    
    end {
        # Output the result in a new PowerShell window
        $domainsToExport = $result
        if($DisplayResult) {
            Write-Warning "Please select/highlight the domains you want to configure MTA-STS for in the new PowerShell window and click OK. You can select multiple entries by holding the CTRL key OR by selecting your first entry, then holding the SHIFT key and selecting your last entry."
            $domainsToExport = $result | Sort-Object -Property MTA_STS_CanBeUsed, Name | Out-GridView -Title "Please select the domains you want to configure MTA-STS for and click OK." -PassThru
        }

        # Check if the user selected any domains
        if ($null -eq $domainsToExport) {
            Write-Verbose "No domains selected. Exiting."
            return
        }

        # Export the result to a .csv file
        Write-Warning "Exporting $($domainsToExport.count) domain(s) to $CsvPath"
        $domainsToExport | Export-Csv -Path $CsvPath -Delimiter $CsvDelimiter -Encoding $CsvEncoding -NoTypeInformation -Force
    }
}