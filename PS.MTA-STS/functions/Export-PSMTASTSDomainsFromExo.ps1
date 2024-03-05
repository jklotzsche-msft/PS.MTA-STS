function Export-PSMTASTSDomainsFromExo {
    <#
        .SYNOPSIS
        Export-PSMTASTSDomainsFromExo.ps1

        .DESCRIPTION
        This script exports all domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to a .csv file.

        .PARAMETER DisplayResult
        Provide a Boolean value, if the result should be displayed in the console. Default is $true.

        .PARAMETER CsvPath
        Provide a String containing the path to the .csv file, where the result should be exported to.

        .PARAMETER MTASTSDomain
        Provide a PSCustomObject containing the result of Get-AcceptedDomain. If not provided, the script will run Get-AcceptedDomain itself.

        .PARAMETER DnsServerToQuery
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

        .PARAMETER ExoHost
        Provide a String containing the host name of the MX record, which should be used to check, if the MX record points to Exchange Online. Default is *.mail.protection.outlook.com.

        .PARAMETER CsvEncoding
        Provide encoding of csv file. Default is "UTF8".

        .PARAMETER CsvDelimiter
        Provide delimiter of csv file. Default is ";".

        .PARAMETER Verbose
        Switch to run the command in a Verbose mode.

        .EXAMPLE
        Export-PSMTASTSDomainsFromExo.ps1 -CsvPath "C:\Temp\ExoDomains.csv"

        Gets accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\ExoDomains.csv".

        .EXAMPLE
        Get-AcceptedDomain -ResultSize 10 | Export-PSMTASTSDomainsFromExo.ps1 -CsvPath "C:\Temp\ExoDomains.csv"

        Gets 10 accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\ExoDomains.csv".
        If you want to filter the accepted domains first, you can do so and pipe it to the Export-PSMTASTSDomainsFromExo function.

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $CsvPath,

        [Parameter(ValueFromPipeline = $true)]
        [PSObject[]]
        $MTASTSDomain,

        [Bool]
        $DisplayResult = $true,

        [String]
        $DnsServerToQuery = "8.8.8.8",

        [string]
        $CsvEncoding = "UTF8",

        [string]
        $CsvDelimiter = ";",

        [Parameter(DontShow = $true)]
        [String]
        $ExoHost = "*.mail.protection.outlook.com"
    )
    
    begin {
        # Get all domains from Exchange Online
        $result = @()
    }
    
    process {
        trap {
            Write-Error $_
            return
        }
        
        # Connect to Exchange Online, if not already connected
        $exchangeConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue | Sort-Object -Property TokenExpiryTimeUTC -Descending | Select-Object -First 1 -ExpandProperty State
        if (($exchangeConnection -ne "Connected") -and ($null -eq $Domainomain)) {
            Write-Warning "Connecting to Exchange Online..."
            $null = Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }

        if($null -eq $MTASTSDomain) {
            Write-Verbose "Getting all domains from Exchange Online and checking MX-Record. Please wait..."
            $AcceptedDomains = Get-AcceptedDomain -ResultSize unlimited | Sort-Object -Property Name
        }

        foreach ($MTASTSDomain in $AcceptedDomains) {
        
            $resultObject = [PSCustomObject]@{
                Name                  = $Domain.Name
                DomainName            = $Domain.DomainName
                MTA_STS_TXTRecord     = ""
                MTA_STS_Policy        = ""
                MTA_STS_CanBeUsed     = ""
                MX_Record_Pointing_To = ""
            }

            #Checking MX Record
            Write-Verbose "Checking MX record for $($MTASTSDomain.DomainName)..."
            $mxRecord = Resolve-DnsName -Name $MTASTSDomain.DomainName -Type MX -Server $DnsServerToQuery -ErrorAction SilentlyContinue

            #Checking MTA-STS TXT Record
            $DNSHost = "_mta-sts." + $MTASTSDomain
            $MTASTS_TXTRecord = Resolve-DnsName -Name $DNSHost -Type TXT -ErrorAction SilentlyContinue | Where-Object {$_.Strings -match "v=STSv1"}
            If ($Null -eq $MTASTS_TXTRecord)
            {
                $resultObject.MTA_STS_TXTRecord = "No"
            } else {
                $resultObject.MTA_STS_TXTRecord = "Yes"
            }

            #Checking MTA-STS Policy
            $URI = "https://mta-sts.$Domain/.well-known/mta-sts.txt"
            try {
                $Response = Invoke-WebRequest -URI $URI -TimeoutSec 1
                $MTASTS_Policy = ($response.Content).trim().Replace("`r`n","")
                $resultObject.MTA_STS_Policy = $MTASTS_Policy
            } catch {
                #If ($Silent -ne $True)
                #{
                #    Write-Host "An exception was caught: $($_.Exception.Message)" -ForegroundColor Yellow
                #}
            }


            if ($MTASTSDomain.DomainName -like "*.onmicrosoft.com") {
                $resultObject.MX_Record_Pointing_To = "WARNING: You cannot configure MTA-STS for an onmicrosoft.com domain."
                $resultObject.MTA_STS_CanBeUsed = "No"
            }
            elseif (($mxRecord.NameExchange.count -eq 1) -and ($mxRecord.NameExchange -like $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = $mxRecord.NameExchange
                If ($Null -eq $MTASTS_TXTRecord)
                {
                    $resultObject.MTA_STS_CanBeUsed = "Yes"
                } else {
                    $resultObject.MTA_STS_CanBeUsed = "No"
                }

            }
            elseif (($mxRecord.NameExchange.count -gt 1) -or ($mxRecord.NameExchange -notlike $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = "WARNING: MX Record does not point to Exchange Online (only). The following host(s) was/were found: $($mxRecord.NameExchange -join ", ")"
                $resultObject.MTA_STS_CanBeUsed = "No"
            }
            else {
                $resultObject.MX_Record_Pointing_To = "ERROR: No MX record found. Please assure, that the MX record for $($Domain.DomainName) points to Exchange Online."
                $resultObject.MTA_STS_CanBeUsed = "No"
            }
        
            $result += $resultObject
        }
    }
    
    end {
        # Output the result in a new PowerShell window
        $domainsToExport = $result
        if($DisplayResult) {
            Write-Warning "Please select/highlight the domains you want to configure MTA-STS for in the new PowerShell window and click OK. You can select multiple entries by holding the CTRL key OR by selecting your first entry, then holding the SHIFT key and selecting your last entry."
            $domainsToExport = $result | Sort-Object -Property MTA_STS_CanBeUsed, Name | Out-GridView -Title "Please select the domains you want to use for MTA-STS and click OK." -PassThru
        }

        # Check if the user selected any domains
        if ($null -eq $domainsToExport) {
            Write-Verbose "No domains selected. Exiting."
        }

        # Export the result to a .csv file
        Write-Verbose "Exporting $($domainsToExport.count) domain(s) to $CsvPath..."
        $domainsToExport | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding $CsvEncoding -Delimiter $CsvDelimiter -Force
    }
}