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
        Get-PSMTASTSCustomDomain -ResourceGroupName "MTA-STS" -FunctionAppName "func-MTA-STS"

        Gets list of custom domains of Function App "func-MTA-STS" in Resource Group "MTA-STS".

        .EXAMPLE
        [PSCustomObject]@{
            ResourceGroupName = "rg-MTASTS001"
            FunctionAppName = "func-MTA-STS-Enforce"
        },
        [PSCustomObject]@{
            ResourceGroupName = "rg-MTASTS002"
            FunctionAppName = "func-MTA-STS-Testing"
        } | Get-PSMTASTSCustomDomain

        Gets list of custom domains of Function App "func-MTA-STS-Enforce" in Resource Group "rg-MTASTS001" and Function App "func-MTA-STS-Testing" in Resource Group "rg-MTASTS002".
        The result will be a list of custom domains, default domain and SSLStates of both Function Apps.

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $FunctionAppName
    )
    
    begin {
        # Trap errors
        trap {
            throw $_
        }

        # Preset ActionPreference to Stop, if not set by user through common parameters
        if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $local:ErrorActionPreference = "Stop" }
        
        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Verbose "Connecting to Azure service..."
            $null = Connect-AzAccount
        }
    }
    
    process {
        Write-Verbose "Getting domains of Function App $FunctionAppName..."
        Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName | Select-Object -Property @{
            Name       = "CustomDomains"
            Expression = {
                if ($null -ne $_.HostNames) {
                    $_.HostNames | Where-Object { $_ -notlike "*.azurewebsites.net" }
                }
            }
        },
        @{
            Name       = "DefaultDomain"
            Expression = {
                if ($null -ne $_.DefaultHostName) {
                    $_.DefaultHostName
                }
            }
        },
        @{
            Name       = "SSLState"
            Expression = {
                if ($null -ne $_.HostNameSslStates) {
                    $_.HostNameSslStates | Select-Object -Property Name, SslState, Thumbprint | Sort-Object -Property Name
                }
            }
        }
    }
}