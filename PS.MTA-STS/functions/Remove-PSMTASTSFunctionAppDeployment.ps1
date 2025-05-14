function Remove-PSMTASTSFunctionAppDeployment {
    <#
    .SYNOPSIS
        Removes the Azure Function App with the needed PowerShell code to publish MTA-STS policies.

    .DESCRIPTION
        Creates an Azure Function App with the needed PowerShell code to publish MTA-STS policies.
        The Azure Function App will be created in the specified resource group and location.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code. This will overwrite any changes you made to the Azure Function App!

    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be created.
        If the resource group doesn't exist, it will be created.
        If the resource group exists already, it will be used.

    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code. This will overwrite any changes you made to the Azure Function App!

    .PARAMETER StorageAccountName
        Provide the name of the Azure Storage Account, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

    .PARAMETER PlanName
        Provide the name of the Azure App Service Plan, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

        If the PlanName is provided, the location will be set to the location of the App Service Plan.
        The location will still be used to create the resource group.

    .EXAMPLE
        New-PSMTASTSFunctionAppDeployment -Location 'West Europe' -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -StorageAccountName 'stpsmtasts'
        
        Creates an Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' in the location 'West Europe' with policy mode 'Enforce'.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created and app files published.

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

			#Delete Function App
			Write-Verbose "Deleting Function App $FunctionAppName in Resource Group $ResourceGroupName"
			$null = Remove-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -Force -ErrorAction SilentlyContinue

			#Delete Storage Account
			Write-Verbose "Deleting Storage Account $StorageAccountName in Resource Group $ResourceGroupName"
			$null = Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue

			#Delete App Service Plan
			Write-Verbose "Deleting App Service Plan $AppServicePlan in Resource Group $ResourceGroupName"
			$null = Remove-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $AppServicePlan -Force -ErrorAction SilentlyContinue
		}
	}

	process {
	}