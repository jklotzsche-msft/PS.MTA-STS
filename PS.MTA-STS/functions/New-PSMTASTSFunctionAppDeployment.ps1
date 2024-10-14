function New-PSMTASTSFunctionAppDeployment {
    <#
    .SYNOPSIS
        Creates an Azure Function App with the needed PowerShell code to publish MTA-STS policies.

    .DESCRIPTION
        Creates an Azure Function App with the needed PowerShell code to publish MTA-STS policies.
        The Azure Function App will be created in the specified resource group and location.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code. This will overwrite any changes you made to the Azure Function App!

    .PARAMETER Location
        Provide the Azure location, where the Azure Function App should be created.
        You can get a list of all available locations by running 'Get-AzLocation | Select-Object -ExpandProperty location | Sort-Object'

        If the PlanName is provided, the location will be set to the location of the App Service Plan.
        The location will still be used to create the resource group.

    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be created.
        If the resource group doesn't exist, it will be created.
        If the resource group exists already, it will be used.

    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code. This will overwrite any changes you made to the Azure Function App!

    .PARAMETER RegisterResourceProvider
        Use this Parameter to Register Resource Provider 'Microsoft.Web' if it is not yet registered.

    .PARAMETER DisableApplicationInsights
        By default, Application Insights is enabled during the creation of the Azure Function App.
        Use this parameter to disable the creation of the application insights resource during the function app creation. No logs will be available then.

    .PARAMETER StorageAccountName
        Provide the name of the Azure Storage Account, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

    .PARAMETER StorageDeleteRetentionInDays
        Provide the number of days to retain the deleted blobs. Default is 7 days.

    .PARAMETER PlanName
        Provide the name of the Azure App Service Plan, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

        If the PlanName is provided, the location will be set to the location of the App Service Plan.
        The location will still be used to create the resource group.

    .PARAMETER PolicyMode
        Specifies if the policy is in "Enforce" mode or "Testing" mode

    .PARAMETER ExoHostName
        Provide a list of hostnames, which should be included in the MTA-STS policy.
        The list of hostnames must be valid, which means that they must be valid domain names.
        Additionally, they cannot start with a wildcard because it will be added automatically.
        *.mail.protection.outlook.com will be added automatically to the list of hostnames.

    .PARAMETER DnsServer
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

    .PARAMETER WhatIf
        If this switch is provided, no changes will be made. Only a summary of the changes will be shown.

    .PARAMETER Confirm
        If this switch is provided, you will be asked for confirmation before any changes are made.

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
        [String]
        $Location,

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
        $StorageAccountName,

        [String]
        $PlanName,

        [int]
        $StorageDeleteRetentionInDays = 7,

        [ValidateSet("Enforce", "Testing", "None")] # ValidateSet is used to limit the possible values
        [String]
        $PolicyMode = "Enforce",

        [ValidateScript({
                # the provided list of hostnames must be valid, which means that they must be valid domain names
                # Domain Names cannot start with a dot, so we need to check for that
                # Additionally, they can start with a wildcard, if subdomains should be included
                foreach ($hostname in $_) {
                    if ($hostname -notmatch "^[a-zA-Z0-9][a-zA-Z0-9-_.]*$" -and $hostname -notmatch "^\*.[a-zA-Z0-9][a-zA-Z0-9-_.]*$") {
                        throw "MX endpoint '$hostname' is not valid. The name can contain only letters, numbers, hyphens, underscores and periods. You can also start with a wildcard character to include subdomains."
                    }

                    if ($hostname -like "*mail.protection.outlook.com") {
                        throw "MX endpoint '$hostname' cannot be added, because the DNS zone '*.mail.protection.outlook.com' will be added automatically. Please remove it from the list."
                    }
                }
                # if the list of entries is valid, return $true
                $true
            })]
        [String[]]
        $ExoHostName,

        [String]
        $DnsServer = "8.8.8.8",

        #Register AZ Resource Provider
        [Switch]
        $RegisterResourceProvider,

        #Disable Application Insights
        [Switch]
        $DisableApplicationInsights
    )
    #endregion Parameter

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
        # Check, if Location is valid
        Write-Verbose "Checking if location '$($Location)' is valid."
        $validLocations = Get-AzLocation | Select-Object -ExpandProperty location
        if (-not ($Location -in $validLocations)) {
            throw "Location '$($Location)' is not valid. Please provide one of the following values: $($validLocations -join ', ')"
        }

        # Create, if resource group doesn't exist already. If it doesn't exist, create it.
        Write-Verbose "Checking if ResourceGroup '$ResourceGroupName' already exists"
        if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            Write-Verbose "Creating Azure Resource Group '$ResourceGroupName'..."
            if ($PSCmdlet.ShouldProcess("Resource Group $ResourceGroupName", "Create")) {
                $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
            }
        }

        # Set default resource group for future cmdlets in this powershell session
        $null = Set-AzDefault -ResourceGroupName $ResourceGroupName

        # Check, if PlanName is valid, if provided
        if ($PlanName) {
            $appServicePlanResult = Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $PlanName -ErrorAction SilentlyContinue
            if ($null -eq $appServicePlanResult) {
                throw "App Service Plan '$PlanName' does not exist in Resource Group '$ResourceGroupName'. Please provide a valid App Service Plan."
            }
        }

        # Check Resource Provider
        $ResourceProvider = Get-AzResourceProvider
        $MicrosoftWeb = $ResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.Web" }
        if ($Null -eq $MicrosoftWeb) {
            #Resource Provicer Microsoft.Web not registered
            if ($RegisterResourceProvider -eq $true) {
                Register-AzResourceProvider -ProviderNamespace Microsoft.Web
            }
            else {
                Write-Warning -Message "Azure Resource Provider 'Microsoft.Web' is not registered. Please register the Azure Resource Provider 'Microsoft.Web' manually afterwards. See https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types#register-resource-provider for more information."
            }
        }

        # Check if Storage StorageAccountName already exists
        $storageAccountDnsResult = Resolve-PSMTASTSDnsName -Name "$StorageAccountName.blob.core.windows.net" -Type A -Server $DnsServer
        if ($null -ne $storageAccountDnsResult) {
            $StorageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName

            # Check, if Storage Account exists already
            if (($StorageAccounts.StorageAccountName.count -eq 1 -and $StorageAccounts.StorageAccountName -eq $StorageAccountName) -or ($StorageAccounts.StorageAccountName.count -gt 1 -and $StorageAccounts.StorageAccountName -contains $StorageAccountName)) {
                # Single Storage Account found
                Write-Verbose -Message "Existing Storage Account found in Resource Group"
                [bool]$ExistingStorageAccount = $true
            }
            else {
                throw "Storage Account exists somewhere else. Please provide a different name for the Storage Account."
            }
        }
        else {
            Write-Verbose -Message "Storage Account does not exist. Will be created."
            [bool]$ExistingStorageAccount = $false
        }

        # Check, if FunctionApp exists already
        $functionAppDnsResult = Resolve-PSMTASTSDnsName -Name "$FunctionAppName.azurewebsites.net" -Type A -Server $DnsServer
        if ($null -ne $functionAppDnsResult) {
            throw "Function App already exists. Please provide a different name for the Function Account."
        }

        if ($ExistingStorageAccount -ne $true) {
            # Create Storage Account
            Write-Verbose "Creating Azure Storage Account $StorageAccountName..."
            $newAzStorageAccountProps = @{
                ResourceGroupName      = $ResourceGroupName
                Name                   = $StorageAccountName
                Location               = $Location
                SkuName                = 'Standard_LRS'
                AllowBlobPublicAccess  = $false
                EnableHttpsTrafficOnly = $true
            }
            if ($PSCmdlet.ShouldProcess("Storage Account $StorageAccountName", "Create")) {
                $null = New-AzStorageAccount @newAzStorageAccountProps
            }
        }

        # Enable soft delete for blobs
        try {
            $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName
            $null = Enable-AzStorageDeleteRetentionPolicy -RetentionDays $StorageDeleteRetentionInDays -Context $ctx
        }
        catch {
            Write-Warning "Could not enable soft delete for blobs in Storage Account $StorageAccountName. Please enable it manually, if needed."
        }

        # Create Function App
        Write-Verbose "Creating Azure Function App $FunctionAppName..."
        $newAzFunctionAppProps = @{
            ResourceGroupName  = $ResourceGroupName
            Name               = $FunctionAppName
            Runtime            = 'PowerShell'
            StorageAccountName = $StorageAccountName
            FunctionsVersion   = '4'
            OSType             = 'Windows'
            RuntimeVersion     = '7.4'
        }
        # If PlanName is provided, you cannot set the Location anymore.
        # Therefore, we set the PlanName and don't set the Location, if PlanName is provided.
        if ($PlanName) {
            # Add App Service Plan, if provided
            $newAzFunctionAppProps.PlanName = $PlanName
        }
        else {
            $newAzFunctionAppProps.Location = $Location
        }
        # Disable Application Insights, if provided
        if ($DisableApplicationInsights) {
            $newAzFunctionAppProps.DisableApplicationInsights = $true
        }
        # Create Function App
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Create")) {
            $null = New-AzFunctionApp @newAzFunctionAppProps
        }

        # Wait for Function App to be ready
        Write-Verbose "Waiting for Azure Function App $FunctionAppName to be ready..."
        $null = Start-Sleep -Seconds 60

        # Remove AzureWebJobsDashboard, as it is deprecated
        $functionAppSettingsToRemove = @("AzureWebJobsDashboard")
        $FunctionAppSettings = Get-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        foreach ($functionAppSettingToRemove in $functionAppSettingsToRemove) {
            if ($FunctionAppSettings.Keys -contains $functionAppSettingToRemove) {
                Write-Verbose "Remove $functionAppSettingToRemove App Setting from Function App $FunctionAppName..."
                Remove-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -AppSettingName $functionAppSettingToRemove -Confirm:$false -Force
            }
        }

        # Update the Azure Function App files with the latest PowerShell code
        $updateFunctionAppProps = @{
            ResourceGroupName = $ResourceGroupName
            FunctionAppName   = $FunctionAppName
            PolicyMode        = $PolicyMode
        }
        if ($ExoHostName) {
            $updateFunctionAppProps.ExoHostName = $ExoHostName
        }
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Update")) {
            $null = Update-PSMTASTSFunctionAppFile @updateFunctionAppProps
        }
    }
}