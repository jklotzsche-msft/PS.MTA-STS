function Start-PSMTASTSFunctionAppDeployment {
    <#
    .SYNOPSIS
        Creates an Azure Function App with the needed PowerShell code to publish MTA-STS policies.        

    .DESCRIPTION
        Creates an Azure Function App with the needed PowerShell code to publish MTA-STS policies.
        The Azure Function App will be created in the specified resource group and location.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code.

    .PARAMETER Location
        Provide the Azure location, where the Azure Function App should be created.
        You can get a list of all available locations by running 'Get-AzLocation | Select-Object -ExpandProperty location | Sort-Object'
    
    .PARAMETER ResourceGroupName
        Provide the name of the Azure resource group, where the Azure Function App should be created.
        If the resource group doesn't exist, it will be created.        
    
    .PARAMETER FunctionAppName
        Provide the name of the Azure Function App, which should be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code.
        
    .EXAMPLE
        Start-PSMTASTSFunctionAppDeployment -Location 'West Europe' -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS'
        
        Creates an Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' in the location 'West Europe'.
        If the resource group doesn't exist, it will be created.
        If the Azure Function App doesn't exist, it will be created.
        If the Azure Function App exists, it will be updated with the latest PowerShell code.

    .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>

    #region Parameter
    [CmdletBinding()]
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
        $StorageAccountName
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

        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }
    }
    process {
        trap {
            Write-Error $_
            return
        }
        
        # Check, if Location is valid
        Write-Verbose "Checking if location '$($Location)' is valid."
        $validLocations = Get-AzLocation | Select-Object -ExpandProperty location
        if(-not ($Location -in $validLocations)) {
            Write-Host -Object "Location '$($Location)' is not valid. Please provide one of the following values: $($validLocations -join ', ')" -ForegroundColor Red
            return
        }

        # Create, if resource group doesn't exist already. If it doesn't exist, create it.
        if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            Write-Host -Object "Creating Azure Resource Group $($ResourceGroupName)..." -NoNewline
            $null = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
            Write-Host -Object "OK" -ForegroundColor Green
        }

        # Set default resource group for future cmdlets in this powershell session
        $null = Set-AzDefault -ResourceGroupName $ResourceGroupName

        # Check, if FunctionApp exists already
        if($null -eq (Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction SilentlyContinue)) {
            # Create Storage Account
            Write-Host -Object "Creating Azure Storage Account $StorageAccountName..." -NoNewline
            $newAzStorageAccountProps = @{
                ResourceGroupName = $ResourceGroupName
                Name = $StorageAccountName
                Location = $Location
                SkuName = 'Standard_LRS'
                AllowBlobPublicAccess = $false
                ErrorAction = 'Stop'
            }
            $null = New-AzStorageAccount @newAzStorageAccountProps
            Write-Host -Object "OK" -ForegroundColor Green

            # Create Function App
            Write-Host -Object "Creating Azure Function App $FunctionAppName..." -NoNewline
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
            $null = New-AzFunctionApp @newAzFunctionAppProps
            Write-Host -Object "OK" -ForegroundColor Green
        }

        # Create Function App contents in temporary folder and zip it
        $workingDirectory = Join-Path -Path $env:TEMP -ChildPath "PS.MTA-STS_deployment"
        if (Test-Path -Path $workingDirectory) {
            $null = Remove-Item -Path $workingDirectory -Recurse -Force
        }
        $null = New-Item -Path $workingDirectory -ItemType Directory
        $null = New-Item -Path "$workingDirectory/function" -ItemType Directory
        $null = $PSMTASTS_hostJson | Set-Content -Path "$workingDirectory/function/host.json" -Force
        $null = $PSMTASTS_profilePs1 | Set-Content -Path "$workingDirectory/function/profile.ps1" -Force
        $null = $PSMTASTS_requirementsPsd1 | Set-Content -Path "$workingDirectory/function/requirements.psd1" -Force
        $null = New-Item -Path "$workingDirectory/function/Publish-MTASTSPolicy" -ItemType Directory
        $null = $PSMTASTS_functionJson | Set-Content -Path "$workingDirectory/function/Publish-MTASTSPolicy/function.json" -Force
        $null = $PSMTASTS_runPs1 | Set-Content -Path "$workingDirectory/function/Publish-MTASTSPolicy/run.ps1" -Force
        $null = Compress-Archive -Path "$workingDirectory/function/*" -DestinationPath "$workingDirectory/Function.zip" -Force

        # Wait for Function App to be ready
        Write-Host -Object "Waiting for Azure Function App $($FunctionAppName) to be ready..." -NoNewline
        $null = Start-Sleep -Seconds 60
        Write-Host -Object "OK" -ForegroundColor Green

        # Upload PowerShell code to Azure Function App
        Write-Host -Object "Uploading PowerShell code to Azure Function App $($FunctionAppName)..." -NoNewline
        $null = Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ArchivePath "$workingDirectory/Function.zip" -Confirm:$false -Force
        Write-Host -Object "OK" -ForegroundColor Green

        # Clean up
        $null = Remove-Item -Path $workingDirectory -Recurse -Force
    }
}