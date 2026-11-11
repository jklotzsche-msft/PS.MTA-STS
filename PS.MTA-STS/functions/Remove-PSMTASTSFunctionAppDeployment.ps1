function Remove-PSMTASTSFunctionAppDeployment {
    <#
    .SYNOPSIS
        Removes the Azure Function App with the needed PowerShell code to publish MTA-STS policies.

    .DESCRIPTION
        Removes the Azure Function App with the needed PowerShell code to publish MTA-STS policies.
        The Azure Function App will be removed from the specified resource group.
        If the resource group doesn't exist, an error will be thrown.
        If the Azure Function App doesn't exist, an error will be thrown.
        If the Azure Function App exists, it will be removed along with the associated Azure Storage Account.

    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be removed from.

    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be removed.

    .PARAMETER StorageAccountName
        Provide the name of the Azure Storage Account, which should be removed.
        If the Azure Function App doesn't exist, an error will be thrown.

    .PARAMETER DoNotRemoveApplicationInsights
        Switch parameter to prevent the removal of the associated Application Insights instance.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet does not run.

        If the PlanName is provided, the location will be set to the location of the App Service Plan.
        The location will still be used to create the resource group.

    .EXAMPLE
        Remove -PSMTASTSFunctionAppDeployment -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -StorageAccountName 'stpsmtasts'

        Removes the Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' and the associated Azure Storage Account.

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
        [String]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_.length -lt 2 -or $_.length -gt 60 -or $_ -notmatch "^[a-zA-Z0-9-]*$") {
                    throw "Function App name '$_' is not valid. The name must be between 2 and 60 characters long and can contain only letters, numbers and hyphens."
                }
                else {
                    $true
                }
            })]
        [String]$FunctionAppName,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
                if ($_.length -lt 3 -or $_.length -gt 24 -or $_ -notmatch "^[a-z0-9]*$") {
                    throw "Storage Account name '$_' is not valid. The name must be between 3 and 24 characters long and can contain only lowercase letters and numbers."
                }
                else {
                    $true
                }
            })]
        [String]$StorageAccountName,
        
        [Parameter(Mandatory = $false)]
        [switch]$DoNotRemoveApplicationInsights = $false
    )
    #endregion Parameter

    begin {
        # Trap errors
        trap {
            throw $_
        }

        $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
        If ($null -eq $FunctionApp) {
            Write-Verbose "Function App $FunctionAppName not found. Nothing to remove."
            return
        } else{
            # Getting App Service Plan
            $AppServicePlan = $FunctionApp.AppServicePlan

            # Get Function AppSetting for Storage Account
            $FunctionAppSetting = Get-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue

            # Get Storage Account mapping from Function App settings
            $connectionString = $FunctionAppSetting['WEBSITE_CONTENTAZUREFILECONNECTIONSTRING']
            
            if ([string]::IsNullOrWhiteSpace($connectionString)) {
                throw "Function App setting 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING' is missing or empty. Cannot validate Storage Account mapping."
            }
            
            # Parse key/value pairs independent from order
            $accountNamePair = $connectionString -split ';' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^(?i)AccountName=' } |
                Select-Object -First 1
            
            if (-not $accountNamePair) {
                throw "Could not find 'AccountName' in WEBSITE_CONTENTAZUREFILECONNECTIONSTRING. Cannot safely determine Storage Account."
            }
            
            $FunctionAppStorageAccountName = ($accountNamePair -split '=', 2)[1].Trim()
            
            if ([string]::IsNullOrWhiteSpace($FunctionAppStorageAccountName)) {
                throw "Parsed AccountName is empty in WEBSITE_CONTENTAZUREFILECONNECTIONSTRING. Cannot safely determine Storage Account."
            }
            
            if ($FunctionAppStorageAccountName -ine $StorageAccountName) {
                throw "Storage Account name '$StorageAccountName' does not match Function App Storage Account '$FunctionAppStorageAccountName'. Aborting to prevent deleting the wrong account."
            }

            # Remove Application Insights instance if it exists and the DoNotRemoveApplicationInsights switch is not set
            if ($DoNotRemoveApplicationInsights -eq $false)
            {
                Write-Verbose "Removing Application Insights instance if it exists."
                $ApplicationInsightsConnectionString = $FunctionAppSetting['APPLICATIONINSIGHTS_CONNECTION_STRING']
                if ($ApplicationInsightsConnectionString -match 'InstrumentationKey=([^;]+)')
                {
                    $InstrumentationKey = $matches[1]

                    # Remove Application Insights instance if it exists
                    $ApplicationInsights = Get-AzApplicationInsights | Where-Object {$_.InstrumentationKey -eq $InstrumentationKey}
                    if ($null -ne $ApplicationInsights) {
                        $null = Remove-AzApplicationInsights -ResourceGroupName $($ApplicationInsights.ResourceGroupName) -Name $($ApplicationInsights.Name) -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }

                    # Delete Smart detector alert rule
                    $SmartDetectorAlertRules = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "microsoft.alertsmanagement/smartdetectoralertrules" | Where-Object {$_.Name -match "$FunctionAppName"}
                    foreach ($SmartDetectorAlertRule in $SmartDetectorAlertRules) {
                        $null = Remove-AzResource -ResourceId $SmartDetectorAlertRule.ResourceId -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                }
            }

            # Get Certificates associated with the Function App
            Write-Verbose "Removing Certificates from Resource Group $ResourceGroupName."
            $webApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
            $boundThumbprints = @($webApp.HostNameSslStates |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.Thumbprint) } |
                Select-Object -ExpandProperty Thumbprint -Unique)

            # Delete Function App
            Write-Verbose "Deleting Function App $FunctionAppName in Resource Group $ResourceGroupName"
            $null = Remove-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Delete Storage Account
            Write-Verbose "Deleting Storage Account $StorageAccountName in Resource Group $ResourceGroupName"
            $null = Remove-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Delete App Service Plan
            Write-Verbose "Deleting App Service Plan $AppServicePlan in Resource Group $ResourceGroupName"
            $null = Remove-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $AppServicePlan -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Remove Certificates from the Resource Group
            if ($boundThumbprints.Count -gt 0) {
                $certificateThumbprints = Get-AzWebAppCertificate -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
                    Where-Object { $_.Thumbprint -in $boundThumbprints } |
                    Select-Object -ExpandProperty Thumbprint -Unique
                foreach ($thumbprint in $certificateThumbprints) {
                    if ($PSCmdlet.ShouldProcess("Certificate $thumbprint in Resource Group $ResourceGroupName", "Remove certificate")) {
                        $null = Remove-AzWebAppCertificate -ResourceGroupName $ResourceGroupName -ThumbPrint $thumbprint -Confirm:$false -ErrorAction Stop
                        Write-Verbose "Removed Certificate $thumbprint from Resource Group $ResourceGroupName."
                    }
                }
            }
        }
    }

    process {
    }
}