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

    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be created.
        If the resource group doesn't exist, it will be created.
        If the resource group exists already, it will be used.

    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code. This will overwrite any changes you made to the Azure Function App!

    .PARAMETER RegisterResourceProvider
        Use this Parameter to Register Resource Provider 'Microsoft.Web' if it is not yet registered

    .PARAMETER StorageAccountName
        Provide the name of the Azure Storage Account, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

    .PARAMETER PolicyMode
        Specifies if the policy is in "Enforce" mode or "Testing" mode

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
                if ($_.length -lt 2 -or $_.length -gt 60 -or $_ -notmatch "^[a-z0-9-]*$") {
                    throw "Function App name '$_' is not valid. The name must be between 2 and 60 characters long and can contain only lowercase letters, numbers and hyphens."
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

        [ValidateSet("Enforce", "Testing", "None")] # ValidateSet is used to limit the possible values
        [String]
        $PolicyMode = "Enforce",

        [String]
        $DnsServer = "8.8.8.8",

        #Register AZ Resource Provider
        [Parameter(Mandatory = $false)][switch]$RegisterResourceProvider
    )
    #endregion Parameter

    begin {
        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    
    process {
        # Preset ErrorActionPreference to Stop
        $ErrorActionPreference = "Stop"

        # Trap errors
        trap {
            Write-Error $_
            return
        }
        
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

        # Check Resource Provider
        $ResourceProvider = Get-AzResourceProvider
        $MicrosoftWeb = $ResourceProvider | Where-Object {$_.ProviderNamespace -eq "Microsoft.Web"}
        If ($Null -eq $MicrosoftWeb)
        {
            #Resource Provicer Microsoft.Web not registered
            If ($RegisterResourceProvider -eq $true)
            {
                Register-AzResourceProvider -ProviderNamespace Microsoft.Web
            } else {
                throw "Azure Resource Provider 'Microsoft.Web' is not registered. Use the -RegisterResourceProvider Parameter to register the Resource Provider."
            }
        }

        # Check if Storage StorageAccountName already exists
        $storageAccountDnsResult = Resolve-PSMTASTSDnsName -Name "$StorageAccountName.blob.core.windows.net" -Type A -Server $DnsServer -ErrorAction Stop
        if ($null -ne $storageAccountDnsResult) {
            $StorageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
            If ($StorageAccounts.StorageAccountName -match $StorageAccountName)
            {
                Write-Verbose "Existing Storage Account found in Resource Group"
                [bool]$ExistingStorageAccount = $true
            } else {
                throw "Storage Account already exists. Please provide a different name for the Storage Account."
            }
            
        }

        # Check, if FunctionApp exists already
        $functionAppDnsResult = Resolve-PSMTASTSDnsName -Name "$FunctionAppName.azurewebsites.net" -Type A -Server $DnsServer -ErrorAction Stop
        if ($null -ne $functionAppDnsResult) {
            throw "Function App already exists. Please provide a different name for the Function Account."
        }

        If ($ExistingStorageAccount -ne $true) {
            # Create Storage Account
            Write-Verbose "Creating Azure Storage Account $StorageAccountName..."
            $newAzStorageAccountProps = @{
                ResourceGroupName     = $ResourceGroupName
                Name                  = $StorageAccountName
                Location              = $Location
                SkuName               = 'Standard_LRS'
                AllowBlobPublicAccess = $false
                EnableHttpsTrafficOnly = $true
                ErrorAction           = 'Stop'
            }
            if ($PSCmdlet.ShouldProcess("Storage Account $StorageAccountName", "Create")) {
                $null = New-AzStorageAccount @newAzStorageAccountProps
            }
        }

        # Create Function App
        Write-Verbose "Creating Azure Function App $FunctionAppName..."
        $newAzFunctionAppProps = @{
            ResourceGroupName  = $ResourceGroupName
            Name               = $FunctionAppName
            Location           = $Location
            Runtime            = 'PowerShell'
            StorageAccountName = $StorageAccountName
            FunctionsVersion   = '4'
            OSType             = 'Windows'
            RuntimeVersion     = '7.2'
            ErrorAction        = 'Stop'
        }
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Create")) {
            $null = New-AzFunctionApp @newAzFunctionAppProps
        }

        # Wait for Function App to be ready
        Write-Verbose "Waiting for Azure Function App $FunctionAppName to be ready..."
        $null = Start-Sleep -Seconds 60

        # Remove AzureWebJobsDashboard
        $FunctionAppSettings = Get-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        If ("AzureWebJobsDashboard" -match $FunctionAppSettings.Name){
            Write-Verbose "Remove AzureWebJobsDashboard"
            Remove-AzFunctionAppSetting -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -AppSettingName "AzureWebJobsDashboard" -Confirm:$false -Force
        }

        # Update the Azure Function App files with the latest PowerShell code
        $updateFunctionAppProps = @{
            ResourceGroupName = $ResourceGroupName
            FunctionAppName   = $FunctionAppName
            PolicyMode        = $PolicyMode
        }
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Update")) {
            $null = Update-PSMTASTSFunctionAppFile @updateFunctionAppProps
        }
    }
}