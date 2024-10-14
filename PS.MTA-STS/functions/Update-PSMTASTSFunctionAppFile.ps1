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

    .PARAMETER PolicyMode
        Specifies if the policy is in "Enforce" mode or "Testing" mode

    .PARAMETER ExoHostName
        Provide a list of hostnames, which should be included in the MTA-STS policy.
        The list of hostnames must be valid, which means that they must be valid domain names.
        For example, 'contoso.com' or 'fabrikam.com'.
        You can also start with a wildcard character to include subdomains.
        So if you want to include all subdomains of 'contoso.com', you can add '*.contoso.com'.
        *.mail.protection.outlook.com will be added automatically to the list of hostnames.

    .PARAMETER WhatIf
        If this switch is provided, no changes will be made. Only a summary of the changes will be shown.

    .PARAMETER Confirm
        If this switch is provided, you will be asked for confirmation before any changes are made.
        
    .EXAMPLE
        Update-PSMTASTSFunctionAppFile -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -PolicyMode 'Testing'
        
        Updates the Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' with policy mode 'Testing'.
        This will overwrite any changes you made to the Azure Function App!

    .EXAMPLE
        Update-PSMTASTSFunctionAppFile -ResourceGroupName 'rg-PSMTASTS' -FunctionAppName 'func-PSMTASTS' -PolicyMode 'Enforce' -ExoHostName '*.abcd-v1.mx.microsoft', 'mail.fabrikam.com'
        
        Updates the Azure Function App with the name 'PSMTASTS' in the resource group 'PSMTASTS' with policy mode 'Enforce'.
        Additionally, it adds the MX record '*.abcd-v1.mx.microsoft' and 'mail.fabrikam.com' to the MTA-STS policy.
        The MTA-STS policy file will look like this:
            version: STSv1
            mode: enforce
            mx: *.mail.protection.outlook.com
            mx: *.abcd-v1.mx.microsoft
            mx: mail.fabrikam.com
            max_age: 604800

        This will overwrite any changes you made to the Azure Function App!

    .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>

    #region Parameter
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String]
        $FunctionAppName,

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
        $ExoHostName
    )
    #endregion Parameter

    begin {
        # Set working directory for temporary files
        $workingDirectory = Join-Path -Path $env:TEMP -ChildPath "PS.MTA-STS_deployment"

        # Trap errors
        trap {
            # Clean up, if needed
            if (Test-Path -Path $workingDirectory) {
                $null = Remove-Item -Path $workingDirectory -Recurse -Force
            }
            
            throw $_
        }

        # Preset ActionPreference to Stop, if not set by user through common parameters
        if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $local:ErrorActionPreference = "Stop" }

        # Check if PowerShell is connected to Azure
        if ( -not (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount
        }
    }
    
    process {
        # Create, if resource group doesn't exist already. If it doesn't exist, create it.
        Write-Verbose "Checking if ResourceGroup '$ResourceGroupName' already exists"
        if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            throw "ResourceGroup '$ResourceGroupName' does not exist. Please create it first."
        }

        # Set default resource group for future cmdlets in this powershell session
        $null = Set-AzDefault -ResourceGroupName $ResourceGroupName

        # Check, if FunctionApp exists already
        Write-Verbose "Checking if Function Account exists in DNS"
        $functionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
        if ($null -eq $functionApp) {
            throw "Function App '$FunctionAppName' does not exist. Please create it first using 'New-PSMTASTSFunctionAppDeployment'."
        }

        # Create Function App contents in temporary folder and zip it
        Write-Verbose "Creating Function App content in temp folder..."
        if (Test-Path -Path $workingDirectory) {
            $null = Get-ChildItem -Path $workingDirectory -Recurse | Remove-Item -Recurse -Force -Confirm:$false
        }

        # Create Function App contents
        
        ## App files
        $null = New-Item -Path $workingDirectory -ItemType Directory -ErrorAction SilentlyContinue
        $null = New-Item -Path "$workingDirectory/function" -ItemType Directory
        $null = $script:PSMTASTS_hostJson | Set-Content -Path "$workingDirectory/function/host.json" -Force
        $null = $script:PSMTASTS_profilePs1 | Set-Content -Path "$workingDirectory/function/profile.ps1" -Force
        $null = $script:PSMTASTS_requirementsPsd1 | Set-Content -Path "$workingDirectory/function/requirements.psd1" -Force
        
        ## Root Website function
        $null = New-Item -Path "$workingDirectory/function/WebsiteRoot" -ItemType Directory
        $null = $script:Root_functionJson | Set-Content -Path "$workingDirectory/function/WebsiteRoot/function.json" -Force
        $null = $script:Root_runPs1 | Set-Content -Path "$workingDirectory/function/WebsiteRoot/run.ps1" -Force
        
        ## MTA-STS Policy function
        $null = New-Item -Path "$workingDirectory/function/MTASTS" -ItemType Directory
        $null = $script:PSMTASTS_functionJson | Set-Content -Path "$workingDirectory/function/MTASTS/function.json" -Force
        ### Adding PSMTASTS_runPs1 variable to local scope, so we can adjust it without changing the script variable
        $local:PSMTASTS_runPs1 = $script:PSMTASTS_runPs1
        if ($PolicyMode -ne "enforce") {
            $local:PSMTASTS_runPs1 = $local:PSMTASTS_runPs1.replace("mode: enforce", "mode: $($PolicyMode.ToLower())")
        }
        ### Add ExoHostName to run.ps1. We will add all specified hostnames to the MTA-STS policy.
        [string]$mxHostNames = "mx: *.mail.protection.outlook.com`n" # Add default MX record, which is always added
        foreach ($hostName in $ExoHostName) {
            $mxHostNames += "mx: $hostName`n" # Add MX record for each specified hostname
        }
        $local:PSMTASTS_runPs1 = $local:PSMTASTS_runPs1.replace("~mxRecords~", ($mxHostNames.TrimEnd("`n"))) # Replace placeholder with MX records
        $null = $local:PSMTASTS_runPs1 | Set-Content -Path "$workingDirectory/function/MTASTS/run.ps1" -Force
        
        ## Create Zip
        if ($PSCmdlet.ShouldProcess("Zip Function App", "Create")) {
            $null = Compress-Archive -Path "$workingDirectory/function/*" -DestinationPath "$workingDirectory/Function.zip" -Force
        }

        # Upload PowerShell code to Azure Function App
        Write-Verbose "Uploading PowerShell code to Azure Function App $($FunctionAppName)..."
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Update")) {
            $null = Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ArchivePath "$workingDirectory/Function.zip" -Confirm:$false -Force
        }
        
        # Clean up
        Write-Verbose "Cleanup Temp Folder"
        if (Test-Path -Path $workingDirectory) {
            $null = Get-ChildItem -Path $workingDirectory -Recurse | Remove-Item -Recurse -Force -Confirm:$false
        }
    }
}