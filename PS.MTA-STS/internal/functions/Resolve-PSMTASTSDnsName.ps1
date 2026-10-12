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

        .PARAMETER UseClassicDNS
        Switch to use the classic DNS resolution method with Resolve-DnsName. If not specified, the function will use the Google DNS over HTTPS method.

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
        $Server,

        [Parameter(Mandatory = $false)]
        [switch]
        $UseClassicDNS = $false
    )

    Write-Verbose -Message "...checking $($Type.ToUpper()) record for $Name using DNS server $Server"
    try {
        If ($UseClassicDNS) {
            Resolve-DnsName -Name $Name -Type $Type -Server $Server -QuickTimeout -ErrorAction Stop
        }
        else {
            Invoke-RestMethod -URI "https://dns.google/resolve?name=$Name&type=$Type"
        }
    }
    catch {
        if($_.CategoryInfo.Category -eq "ResourceUnavailable") {
            Write-Verbose -Message "DNS record not found. Continuing..."
        }
        elseif($_.CategoryInfo.Category -eq "OperationTimeout") {
            throw "ERROR: Timeout period expired. Please check the DNS server and try again. Are you able to resolve the DNS record using the specified DNS server?"
        }
        else {
            throw $_
        }
    }
}