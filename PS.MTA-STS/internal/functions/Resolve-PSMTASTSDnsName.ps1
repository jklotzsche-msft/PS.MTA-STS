function Resolve-PSMTASTSDnsName {
    <#
        .SYNOPSIS
        Resolve-PSMTASTSDnsName resolves DNS name using specified DNS server.

        .DESCRIPTION
        Resolve-PSMTASTSDnsName resolves DNS name using specified DNS server.
        
        .PARAMETER Name
        Name of the DNS record to resolve.

        .PARAMETER Type
        Type of the DNS record to resolve.

        .PARAMETER Server
        DNS server to use for resolving the DNS record.

        .EXAMPLE
        Resolve-PSMTASTSDnsName -Name "example.com" -Type "TXT" -Server "8.8.8.8"

        Resolves the TXT record for example.com using the DNS server "8.8.8.8". The return value is the TXT record for example.com.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [string]
        $Type,

        [Parameter(Mandatory = $true)]
        [String]
        $Server
    )

    Write-Verbose "...checking $Type record for $Name using DNS server $Server"
    try {
        Resolve-DnsName -Name $Name -Type $Type -Server $Server -QuickTimeout -ErrorAction Stop
    }
    catch {
        if($_.Exception.Message -like "*DNS name does not exist*") {
            Write-Verbose "DNS record not found. Continuing..."
        }
        elseif($_.Exception.Message -like "*timeout period expired*") {
            throw "ERROR: Timeout period expired. Please check the DNS server and try again. Are you able to resolve the DNS record using the defined DNS server?"
        }
        else {
            throw $_
        }
    }
}