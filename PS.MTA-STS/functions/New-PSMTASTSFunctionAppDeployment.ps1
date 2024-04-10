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
        
    .PARAMETER StorageAccountName
        Provide the name of the Azure Storage Account, which should be created.
        If the Azure Function App doesn't exist, the Azure Storace Account and Azure Function App will be created.

    .PARAMETER WhatIf
        If this switch is provided, no changes will be made. Only a summary of the changes will be shown.

    .PARAMETER Confirm
        If this switch is provided, you will be asked for confirmation before any changes are made.

    .PARAMETER Policy
        Specifies if the policy is in "Enforce" mode or "Testing" mode

    .EXAMPLE
        New-PSMTASTSFunctionAppDeployment -Location 'West Europe' -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -StorageAccountName 'stpsmtasts'
        
        Creates an Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' in the location 'West Europe'.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code.

    .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>

    #region Parameter
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]
        $Location,

        [Parameter(Mandatory = $true)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]
        $FunctionAppName,

        [Parameter(Mandatory = $true)]
        [String]
        $StorageAccountName,

        [Parameter()]
        [String]
        $PolicyMode="enforce"
    )
    #endregion Parameter

    begin {
        # Check if needed PowerShell modules are installed
        Write-Verbose "Checking if needed PowerShell modules are installed."
        $neededModules = @(
            'Az.Accounts',
            'Az.Resources',
            'Az.Websites'
        )
        $missingModules = @()
        foreach ($neededModule in $neededModules) {
            if ($null -eq (Get-Module -Name $neededModule -ListAvailable -ErrorAction SilentlyContinue)) {
                $missingModules += $neededModule
            }
        }
        if ($missingModules.Count -gt 0) {
            throw @"
The following modules are missing: '{0}'. Please install them using "Install-Module -Name '{0}'
"@ -f ($missingModules -join "', '")
        }

        if ($PolicyMode -ne "Testing" -and $PolicyMode -ne "Enforce" -and $PolicyMode -ne "None"){
            throw @"
            PolicyMode must be "Enforce"(default), "Testing" or "None"
"@
        }

        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    
    process {
        trap {
            Write-Error $_

            # Clean up, if needed
            if (Test-Path -Path $workingDirectory) {
                $null = Remove-Item -Path $workingDirectory -Recurse -Force
            }

            return
        }
        
        # Check, if Location is valid
        Write-Host "Checking if location '$($Location)' is valid."
        $validLocations = Get-AzLocation | Select-Object -ExpandProperty location
        if(-not ($Location -in $validLocations)) {
            Write-Verbose "Location '$($Location)' is not valid. Please provide one of the following values: $($validLocations -join ', ')"
            return
        }

        # Create, if resource group doesn't exist already. If it doesn't exist, create it.
        Write-Host "Checking if ResourceGroup alredy exists"
        if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            Write-Verbose "Creating Azure Resource Group $($ResourceGroupName)..."
            $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        }

        # Set default resource group for future cmdlets in this powershell session
        $null = Set-AzDefault -ResourceGroupName $ResourceGroupName

        #Check if Storage StorageAccountName already exists
        Write-Host "Checking if Storage Account exists in DNS"
        $DNSResult = Resolve-DnsName -Name "$StorageAccountName.blob.core.windows.net" -ErrorAction SilentlyContinue
        If ($Null -ne $DNSResult)
        {
            Write-Host "Storage Account already exists" -ForegroundColor Red
            break
        }

        #Check Function App Name available
        Write-Host "Checking if Function Account exists in DNS"
        $DNSFunctionApp = Resolve-DnsName -Name "$FunctionAppName.azurewebsites.net" -ErrorAction SilentlyContinue
        If ($Null -ne $DNSFunctionApp)
        {
            Write-Host "Storage Account already exists" -ForegroundColor Red
            break
        }

        # Check, if FunctionApp exists already
        $functionAppCreated = $false
        if($null -eq (Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction SilentlyContinue)) {
            # Create Storage Account
            Write-Host "Creating Azure Storage Account $StorageAccountName..."
            $newAzStorageAccountProps = @{
                ResourceGroupName = $ResourceGroupName
                Name = $StorageAccountName
                Location = $Location
                SkuName = 'Standard_LRS'
                AllowBlobPublicAccess = $false
                ErrorAction = 'Stop'
            }
            $null = New-AzStorageAccount @newAzStorageAccountProps

            # Create Function App
            Write-Host "Creating Azure Function App $FunctionAppName..."
            $newAzFunctionAppProps = @{
                ResourceGroupName = $ResourceGroupName
                Name = $FunctionAppName
                Location = $Location
                Runtime = 'PowerShell'
                StorageAccountName = $StorageAccountName
                FunctionsVersion = '4'
                OSType = 'Windows'
                RuntimeVersion = '7.2'
                ErrorAction = 'Stop'
            }
            $AzFunctionAppObject = New-AzFunctionApp @newAzFunctionAppProps

            $functionAppCreated = $true
        }

        function setMode([String]$policy,[String]$mode){
          if ($mode -eq "enforce"){ 
            return $policy
          } else {
            return $policy.replace("mode: enforce","mode: "+$mode.ToLower())
          }
        }

        # Create Function App contents in temporary folder and zip it
        Write-Host "Creating Functions in Temp Folder..."
        $workingDirectory = Join-Path -Path $env:TEMP -ChildPath "PS.MTA-STS_deployment"
        if (Test-Path -Path $workingDirectory) {
            $null = Get-ChildItem -Path $workingDirectory -Recurse | Remove-Item -Recurse -Force -Confirm:$false 
        }

<# Option from Daniel-t
        $null = New-Item -Path $workingDirectory -ItemType Directory
        $null = New-Item -Path "$workingDirectory/function" -ItemType Directory
        $null = $PSMTASTS_hostJson | Set-Content -Path "$workingDirectory/function/host.json" -Force
        $null = $PSMTASTS_profilePs1 | Set-Content -Path "$workingDirectory/function/profile.ps1" -Force
        $null = $PSMTASTS_requirementsPsd1 | Set-Content -Path "$workingDirectory/function/requirements.psd1" -Force
        $null = New-Item -Path "$workingDirectory/function/Publish-MTASTSPolicy" -ItemType Directory
        $null = $PSMTASTS_functionJson | Set-Content -Path "$workingDirectory/function/Publish-MTASTSPolicy/function.json" -Force
        
        $runPs1 = setMode $PSMTASTS_runPs1 $PolicyMode 
        Write-Verbose "Creating policy in $PolicyMode mode"
        $null = $runPs1 | Set-Content -Path "$workingDirectory/function/Publish-MTASTSPolicy/run.ps1" -Force
        #$null = $PSMTASTS_runPs1 | Set-Content -Path "$workingDirectory/function/Publish-MTASTSPolicy/run.ps1" -Force
        $null = Compress-Archive -Path "$workingDirectory/function/*" -DestinationPath "$workingDirectory/Function.zip" -Force
#>

        $null = New-Item -Path $workingDirectory -ItemType Directory -ErrorAction SilentlyContinue
        $null = New-Item -Path "$workingDirectory\function" -ItemType Directory
        $null = $PSMTASTS_hostJson | Set-Content -Path "$workingDirectory\function\host.json" -Force
        $null = $PSMTASTS_profilePs1 | Set-Content -Path "$workingDirectory\function\profile.ps1" -Force
        $null = $PSMTASTS_requirementsPsd1 | Set-Content -Path "$workingDirectory\function\requirements.psd1" -Force
        #Root Website
        $null = New-Item -Path "$workingDirectory\function\WebsiteRoot" -ItemType Directory
        $null = $Root_functionJson | Set-Content -Path "$workingDirectory\function\WebsiteRoot\function.json" -Force
        $null = $Root_runPs1 | Set-Content -Path "$workingDirectory\function\WebsiteRoot\run.ps1" -Force
        #MTA-STS Policy
        $null = New-Item -Path "$workingDirectory\function\MTA-STS" -ItemType Directory
        $null = $PSMTASTS_functionJson | Set-Content -Path "$workingDirectory\function\MTA-STS\function.json" -Force
        $null = $PSMTASTS_runPs1 | Set-Content -Path "$workingDirectory\function\MTA-STS\run.ps1" -Force
        $null = Compress-Archive -Path "$workingDirectory\function\*" -DestinationPath "$workingDirectory/Function.zip" -Force

        # Wait for Function App to be ready
        if($functionAppCreated) {
            Write-Host "Waiting for Azure Function App $($FunctionAppName) to be ready..."
            $null = Start-Sleep -Seconds 60
        }

        # Upload PowerShell code to Azure Function App
        Write-Host "Uploading PowerShell code to Azure Function App $($FunctionAppName)..."
        $null = Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ArchivePath "$workingDirectory/Function.zip" -Confirm:$false -Force
        
        # Clean up
        Write-Host "Cleanup Temp Folder"
        if (Test-Path -Path $workingDirectory) {
            $null = Get-ChildItem -Path $workingDirectory -Recurse | Remove-Item -Recurse -Force -Confirm:$false
        }

        $DefaultHostName = $AzFunctionAppObject.DefaultHostName
        $id = (get-date).Tostring("yyyyMMddHHmm00Z")
        Write-Host "Now you need to create the DNS Entry for your domains" -ForegroundColor Cyan
        Write-Host "_mta-sts.yourdomain.tld TXT v=STSv1; id=$id" -ForegroundColor Cyan
        Write-Host "mta-sts.yourdomain.tld CNAME $DefaultHostName" -ForegroundColor Cyan
    }
}