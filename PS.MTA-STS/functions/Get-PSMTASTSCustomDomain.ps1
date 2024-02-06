function Get-PSMTASTSCustomDomain {
    <#
        .SYNOPSIS
        Get-PSMTASTSCustomDomain gets custom domains of MTA-STS Function App.

        .DESCRIPTION
        Get-PSMTASTSCustomDomain gets custom domains of MTA-STS Function App.

        .PARAMETER ResourceGroupName
        Provide name of Resource Group where Function App is located.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .EXAMPLE
        Get-PSMTASTSCustomDomain -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Gets list of custom domains of Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS".

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]
        $FunctionAppName
    )
    
    begin {
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    
    process {
        Write-Verbose "Getting domains of Function App $FunctionAppName..."
        Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop | Select-Object -ExpandProperty HostNames
    }
}