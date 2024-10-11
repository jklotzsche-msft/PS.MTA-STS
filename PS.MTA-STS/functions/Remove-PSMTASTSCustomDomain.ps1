function Remove-PSMTASTSCustomDomain {
    <#
        .SYNOPSIS
        Remove-PSMTASTSCustomDomain removes custom domains from MTA-STS Function App.

        .DESCRIPTION
        Remove-PSMTASTSCustomDomain removes custom domains from MTA-STS Function App. It does not remove AzWebAppCertificates, as they could be used elsewhere.

        .PARAMETER CsvPath
        Provide path to csv file with accepted domains. Csv file should have one column with header "DomainName" and list of domains in each row.

        .PARAMETER DomainName
        Provide list of domains.

        .PARAMETER ResourceGroupName
        Provide name of Resource Group where Function App is located.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .PARAMETER CsvEncoding
        Provide encoding of csv file. Default is "UTF8".

        .PARAMETER CsvDelimiter
        Provide delimiter of csv file. Default is ";".

        .PARAMETER WhatIf
        Switch to run the command in a WhatIf mode.

        .PARAMETER Confirm
        Switch to run the command in a Confirm mode.

        .EXAMPLE
        Remove-PSMTASTSCustomDomain -CsvPath "C:\temp\accepted-domains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "func-MTA-STS"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and removes them from Function App "func-MTA-STS" in Resource Group "MTA-STS".

        .EXAMPLE
        Remove-PSMTASTSCustomDomain -DomainName "contoso.com", "fabrikam.com" -ResourceGroupName "MTA-STS" -FunctionAppName "func-MTA-STS"

        Removes domains "contoso.com" and "fabrikam.com" from Function App "func-MTA-STS" in Resource Group "MTA-STS".

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Csv")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "Csv")]
        [string]
        $CsvPath,

        [Parameter(Mandatory = $true, ParameterSetName = "Manual")]
        [string[]]
        $DomainName,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]
        $FunctionAppName,

        [Parameter(ParameterSetName = "Csv")]
        [string]
        $CsvEncoding = "UTF8",

        [Parameter(ParameterSetName = "Csv")]
        [string]
        $CsvDelimiter = ";"
    )
    
    begin {
        # Trap errors
        trap {
            throw $_
        }

        # Preset ActionPreference to Stop, if not set by user through common parameters
        if (-not $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ErrorAction')) { $local:ErrorActionPreference = "Stop" }

        # Check, if we are connected to Azure
        if ($null -eq (Get-AzContext)) {
            Write-Warning "Connecting to Azure service"
            $null = Connect-AzAccount
        }

        # Import csv file with accepted domains
        if ($CsvPath) {
            Write-Verbose "Importing csv file from $CsvPath"
            $domainList = Import-Csv -Path $CsvPath -Encoding $CsvEncoding -Delimiter $CsvDelimiter | Select-Object -ExpandProperty DomainName
        }

        # Import domains from input parameter
        if ($DomainName) {
            Write-Verbose "Creating array of domains from input parameter"
            $domainList = @()
            foreach ($domain in $DomainName) { $domainList += $domain }
        }

        # Check, if domains have correct format
        foreach ($domain in $domainList) {
            if ($domain -notmatch "^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$") {
                throw -Message "Domain $domain has incorrect format. Please provide domain in format 'contoso.com'."
            }
        }
    }

    process {
        #Check FunctionApp
        Write-Verbose "Get Azure Function App $FunctionAppName in Resource Group $ResourceGroupName"
        $FunctionAppResult = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($null -eq $FunctionAppResult) {
            #Function App not found
            throw "FunctionApp $FunctionAppName not found"
        }

        #Get CustomDomain Names
        Write-Verbose "Get CustomDomainNames from Azure Function App $FunctionAppName"
        $customDomainNames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName

        # Prepare new domains
        $removeCustomDomains = @()
        foreach ($domain in $domainList) {
            #Check if CustomDomain is added as Custom Domain
            $mtaStsDomain = "mta-sts." + $domain
            if ($mtaStsDomain -in $CustomDomainNames.CustomDomains) {
                #Custom Domain is present
                Write-Verbose "Adding Domain to Array of Domains to remove: $mtaStsDomain"
                $removeCustomDomains += $mtaStsDomain
            }
        }

        # Check, if there are new domains to remove
        if ($removeCustomDomains.count -eq 0) {
            Write-Warning "No domains to remove from Function App $FunctionAppName. Stopping here."
            return
        }

        # Add the current domains to the list of domains to remove
        $newCustomDomains = Compare-Object -ReferenceObject $CustomDomainNames.CustomDomains -DifferenceObject $removeCustomDomains | Where-Object -FilterScript { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject
        $customDomainsToSet = @()
        $customDomainsToSet += $customDomainNames.DefaultDomain # Add default domain
        $customDomainsToSet += $newCustomDomains # Add custom domains to keep

        # Remove domains from Function App
        Write-Verbose "Removing $($removeCustomDomains.count) domains from Function App $FunctionAppName : $($removeCustomDomains -join ", ")..."
        $setAzWebApp = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $FunctionAppName
            HostNames         = $customDomainsToSet
        }
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Remove custom domains")) {
            $null = Set-AzWebApp @setAzWebApp -WarningAction SilentlyContinue
        }

        #Remove Managed Certificate if needed
        Write-Verbose "Remove Certificates"
        [Array]$webAppCertificates = Get-AzWebAppCertificate -ResourceGroupName $ResourceGroupName
        foreach ($certificate in $webAppCertificates) {
            $subjectName = $certificate.SubjectName
            if ($subjectName -in $removeCustomDomains) {
                #Get Thumbprint of Certificate
                $thumbprint = $certificate.Thumbprint
				
                #Remove Managed Certificate
                Write-Verbose "Remove Managed Certificate: $subjectName Thumbprint: $thumbprint"
                if ($PSCmdlet.ShouldProcess("Subject: $subjectName, Thumbprint: $thumbprint", "Remove managed certificate")) {
                    # If an error occurs during certificate removal, continue with the next certificate removal as the certificate might be used elsewhere
                    # If we do not continue anyways, users would have to remove the certificate manually for next domains
                    $null = Remove-AzWebAppCertificate -ResourceGroupName $ResourceGroupName -ThumbPrint $thumbprint -Confirm:$false -ErrorAction Continue
                }
            }
        }
    }
}