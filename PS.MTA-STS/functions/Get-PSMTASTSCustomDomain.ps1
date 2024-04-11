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

        .EXAMPLE
        [PSCustomObject]@{
            ResourceGroupName = "rg-MTASTS001"
            FunctionAppName = "func-MTASTS-Enforce"
        },
        [PSCustomObject]@{
            ResourceGroupName = "rg-MTASTS002"
            FunctionAppName = "func-MTASTS-Testing"
        } | Get-PSMTASTSCustomDomain

        Gets list of custom domains of Function App "func-MTASTS-Enforce" in Resource Group "rg-MTASTS001" and Function App "func-MTASTS-Testing" in Resource Group "rg-MTASTS002".
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
        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    
    process {
        Write-Verbose "Getting domains of Function App $FunctionAppName..."
        Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction Stop | Select-Object -Property @{
            Name = "CustomDomains"
            Expression = {
                if ($null -ne $_.HostNames) {
                    $_.HostNames | Where-Object { $_ -notlike "*.azurewebsites.net" }
                }
            }
        },
        @{
            Name = "DefaultDomain"
            Expression = {
                if ($null -ne $_.DefaultHostName) {
                    $_.DefaultHostName
                }
            }
        },
        @{
            Name = "SSLState"
            Expression = {
                if ($null -ne $_.HostNameSslStates) {
                    $_.HostNameSslStates | Select-Object -Property Name,SslState,Thumbprint | Sort-Object -Property Name
                }
            }
        }
    }
}