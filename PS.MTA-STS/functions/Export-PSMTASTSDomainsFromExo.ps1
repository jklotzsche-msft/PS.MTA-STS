function Export-PSMTASTSDomainsFromExo {
    <#
        .SYNOPSIS
        Export-PSMTASTSDomainsFromExo.ps1

        .DESCRIPTION
        This script exports all domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to a .csv file.

        .PARAMETER DisplayResult
        Provide a Boolean value, if the result should be displayed in the console. Default is $true.

        .PARAMETER CsvOutputPath
        Provide a String containing the path to the .csv file, where the result should be exported to.

        .PARAMETER MTASTSDomain
        Provide a PSCustomObject containing the result of Get-AcceptedDomain. If not provided, the script will run Get-AcceptedDomain itself.

        .PARAMETER DnsServerToQuery
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

        .PARAMETER ExoHost
        Provide a String containing the host name of the MX record, which should be used to check, if the MX record points to Exchange Online. Default is *.mail.protection.outlook.com.

        .EXAMPLE
        Export-PSMTASTSDomainsFromExo.ps1 -CsvOutputPath "C:\Temp\MTASTSDomains.csv"

        Gets accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\MTASTSDomains.csv".

        .EXAMPLE
        Get-AcceptedDomain -ResultSize 10 | Export-PSMTASTSDomainsFromExo.ps1 -CsvOutputPath "C:\Temp\MTASTSDomains.csv"

        Gets 10 accepted domains from Exchange Online and checks, if the MX record points to Exchange Online. The result is exported to "C:\Temp\MTASTSDomains.csv".
        If you want to filter the accepted domains first, you can do so and pipe it to the Export-PSMTASTSDomainsFromExo function.

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [String]
        $CsvOutputPath,

        [Parameter(ValueFromPipeline = $true)]
        [PSObject[]]
        $MTASTSDomain,

        [Bool]
        $DisplayResult = $true,

        [String]
        $DnsServerToQuery = "8.8.8.8",

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
        if (($exchangeConnection -ne "Connected") -and ($null -eq $MTASTSDomain)) {
            Write-Warning "Connecting to Exchange Online..."
            $null = Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        }

        if($null -eq $MTASTSDomain) {
            Write-Verbose "Getting all domains from Exchange Online and checking MX-Record. Please wait..."
            $MTASTSDomain = Get-AcceptedDomain -ResultSize unlimited | Sort-Object -Property Name
        }

        foreach ($mtastsd in $MTASTSDomain) {
        
            $resultObject = [PSCustomObject]@{
                Name                  = $mtastsd.Name
                DomainName            = $mtastsd.DomainName
                MTA_STS_CanBeUsed     = ""
                MX_Record_Pointing_To = ""
            }
        
            Write-Verbose "Checking MX record for $($mtastsd.DomainName)..."
            $mxRecord = Resolve-DnsName -Name $mtastsd.DomainName -Type MX -Server $DnsServerToQuery -ErrorAction SilentlyContinue
            if (($mxRecord.NameExchange.count -eq 1) -and ($mxRecord.NameExchange -like $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = $mxRecord.NameExchange
                $resultObject.MTA_STS_CanBeUsed = "Yes"
            }
            elseif (($mxRecord.NameExchange.count -gt 1) -or ($mxRecord.NameExchange -notlike $ExoHost)) {
                $resultObject.MX_Record_Pointing_To = "WARNING: MX Record doesn not point to Exchange Online (only). The following host(s) was/were found: $($mxRecord.NameExchange -join ", ")"
                $resultObject.MTA_STS_CanBeUsed = "No"
            }
            else {
                $resultObject.MX_Record_Pointing_To = "ERROR: No MX record found. Please assure, that the MX record for $($mtastsd.DomainName) points to Exchange Online."
                $resultObject.MTA_STS_CanBeUsed = "No"
            }
        
            $result += $resultObject
        }
    }
    
    end {
        # Output the result in a new PowerShell window
        if($DisplayResult) {
            Write-Warning "Please select/highlight the domains you want to use for MTA-STS in the new PowerShell window and click OK. You can select multiple entries by holding the CTRL key and clicking on the entries OR by holding the SHIFT key and clicking on the first and last entry."
            $domainsToExport = $result | Out-GridView -Title "Please select the domains you want to use for MTA-STS and click OK." -PassThru
        }
        else {
            $domainsToExport = $result
        }

        # Export the result to a .csv file
        if ($domainsToExport) {
            Write-Verbose "Exporting $($domainsToExport.count) domain(s) to $CsvOutputPath..."
            $domainsToExport | Export-Csv -Path $CsvOutputPath -NoTypeInformation -Encoding UTF8 -Delimiter ";" -Force
        }
        else {
            Write-Verbose "No domains selected. Exiting."
        }
    }
}