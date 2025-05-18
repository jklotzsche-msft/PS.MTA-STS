## Experimental Function

function Update-PSMTASTSFunctionAppFile {
    <#
    .SYNOPSIS
        Publishes Azure Function App files and functions to Azure Function App.

    .DESCRIPTION
        Publishes Azure Function App files and functions to Azure Function App.
        The Azure Function App will be updated with the latest PowerShell code.
        This will overwrite any changes you may have made to the Azure Function App!
        
    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be updated.
    
    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be updated.

    .EXAMPLE
        Update-PSMTASTSFunctionAppFile -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS'

    .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
	#>


    #region Parameter
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_.length -lt 1 -or $_.length -gt 90 -or $_ -notmatch "^[a-zA-Z0-9-_.]*$") {
                    throw "ResourceGroup name '$_' is not valid. The name must be between 1 and 90 characters long and can contain only letters, numbers, hyphens, underscores and periods."
                }
                else {
                    $true
                }
            })]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_.length -lt 2 -or $_.length -gt 60 -or $_ -notmatch "^[a-zA-Z0-9-]*$") {
                    throw "Function App name '$_' is not valid. The name must be between 2 and 60 characters long and can contain only letters, numbers and hyphens."
                }
                else {
                    $true
                }
            })]
        [String]
        $FunctionAppName,

		<#
        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_.length -lt 3 -or $_.length -gt 24 -or $_ -notmatch "^[a-z0-9]*$") {
                    throw "Storage Account name '$_' is not valid. The name must be between 3 and 24 characters long and can contain only lowercase letters and numbers."
                }
                else {
                    $true
                }
            })]
        [String]
        $StorageAccountName
		#>
    )
    #endregion Parameter

    begin {
        # Trap errors
		trap {
			throw $_
		}

		$FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
		If ($FunctionApp -eq $null) {
			Write-Verbose "Function App $FunctionAppName not found. Nothing to remove."
			return
		} else{
			#Getting App Service Plan
			$AppServicePlan = $FunctionApp.AppServicePlan

			#Get Function AppSetting for Storage Account
        	$FunctionAppSetting = Get-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
		
			#Get Storage Account
			$FunctionAppSetting = Get-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
			$StorageAccountName = $FunctionAppSetting.WEBSITE_CONTENTAZUREFILECONNECTIONSTRING.split(";")[1].Replace("AccountName=", "")
			$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction SilentlyContinue
<#
			#Delete Function App
			Write-Verbose "Deleting Function App $FunctionAppName in Resource Group $ResourceGroupName"
			$null = Remove-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -Force -ErrorAction SilentlyContinue

			#Delete Storage Account
			Write-Verbose "Deleting Storage Account $StorageAccountName in Resource Group $ResourceGroupName"
			$null = Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue

			#Delete App Service Plan
			Write-Verbose "Deleting App Service Plan $AppServicePlan in Resource Group $ResourceGroupName"
			$null = Remove-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $AppServicePlan -Force -ErrorAction SilentlyContinue
#>
		}
	}

	process {
		#Get the functions of a Function App
		$FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
		If ($FunctionApp -eq $null) {
			Write-Verbose "Function App $FunctionAppName not found. Nothing to remove."
			return
		} else{
			#Get the functions of a Function App
			$Functions = Get-AzFunctionAppFunction -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue

			#Publish the function app
			Write-Verbose "Publishing Function App $FunctionAppName in Resource Group $ResourceGroupName"
			$null = Publish-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -Force -ErrorAction SilentlyContinue
		}
	}
}