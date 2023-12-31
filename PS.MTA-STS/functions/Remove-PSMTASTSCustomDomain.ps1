﻿function Remove-PSMTASTSCustomDomain {
    <#
        .SYNOPSIS
        Remove-PSMTASTSCustomDomain removes custom domains from MTA-STS Function App.

        .DESCRIPTION
        Remove-PSMTASTSCustomDomain removes custom domains from MTA-STS Function App. It does not remove AzWebAppCertificates, as they could be used elsewhere.

        .PARAMETER ResourceGroupName
        Provide name of Resource Group where Function App is located.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .PARAMETER DomainName
        Provide name of domain to be removed.

        .PARAMETER WhatIf
        Switch to run the command in a WhatIf mode.

        .PARAMETER Confirm
        Switch to run the command in a Confirm mode.

        .EXAMPLE
        Remove-PSMTASTSCustomDomain -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp" -DomainName "mta-sts.contoso.com"

        Removes domain "mta-sts.contoso.com" from Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS".

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]
        $FunctionAppName,

        [Parameter(Mandatory = $true)]
        [string[]]
        $DomainName
    )
    
    begin {
        if (-not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    
    process {
        trap {
            Write-Error $_
            return
        }

        # Prepare domainname if needed
        $DomainNamesToRemove = @()
        foreach($dn in $DomainName) {
            if ($dn -notlike "mta-sts.*") {
                $DomainNamesToRemove += "mta-sts.$dn"
            }
            else {
                $DomainNamesToRemove += $dn
            }
        }

        # Get current domains
        $currentHostnames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName

        # Remove domain(s) from array
        $newHostNames = @()
        foreach($currentHostname in $currentHostnames) {
            if ($currentHostname -notin $DomainNamesToRemove) {
                $newHostNames += $currentHostname
            }
        }

        # Try to remove domain from Function App
        if ($currentHostnames.count -ne $newHostNames.count) {
            Write-Verbose "Removing $($currentHostnames.count - $newHostNames.count) domains from Function App $FunctionAppName..."
            try {
                $null = Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -HostNames $newHostNames -ErrorAction Stop
            }
            catch {
                Write-Error -Message $_.Exception.Message
            }
        }
    }
}