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

        .PARAMETER Verbose
        Switch to run the command in a Verbose mode.

        .EXAMPLE
        Remove-PSMTASTSCustomDomain -CsvPath "C:\temp\accepted-domains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and removes them from Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS".

        .EXAMPLE
        Remove-PSMTASTSCustomDomain -DomainName "contoso.com", "fabrikam.com" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Removes domains "contoso.com" and "fabrikam.com" from Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS".

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
        if ($null -eq (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }

        if ($CsvPath) {
            # Import csv file with accepted domains
            Write-Verbose "Importing csv file from $CsvPath..."
            $domainList = Import-Csv -Path $CsvPath -Encoding $CsvEncoding -Delimiter $CsvDelimiter -ErrorAction Stop
        }

        if ($DomainName) {
            $domainList = @()
            foreach ($domain in $DomainName) { $domainList += @{DomainName = $domain } }
        }

        # Prepare new domains
        $removeCustomDomains = @()
        foreach ($domain in $domainList) {
            # Check, if domain has correct format
            if ($domain.DomainName -notmatch "^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$") {
                Write-Error -Message "Domain $($domain.DomainName) has incorrect format. Please provide domain in format 'contoso.com'."
                return
            }

            # Prepare new domain
            if ($domain.DomainName -notlike "mta-sts.*") {
                Write-Verbose "Adding prefix 'mta-sts.' to domain $($domain.DomainName)..."
                $domain.DomainName = "mta-sts.$($domain.DomainName)"
            }

            # Add new domain to list of domains
            if ($domain.DomainName -notin $removeCustomDomains) {
                Write-Verbose "Adding domain $($domain.DomainName) to list of domains..."
                $removeCustomDomains += $domain.DomainName
            }
        }

        # Check, if a domain name is already used in our Function App
        $currentHostnames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -ErrorAction Stop
        $customDomainsToRemove = @()
        foreach ($newDomain in $removeCustomDomains) {
            if ($newDomain -notin $currentHostnames) {
                Write-Verbose "Domain $newDomain does not exists in Function App $FunctionAppName. Skipping..."
                continue
            }

            Write-Verbose "Adding domain $newDomain to list of domains, which should be removed from Function App $FunctionAppName..."
            $customDomainsToRemove += $newDomain
        }

        # Add the current domains to the list of domains to remove
        $newCustomDomains = Compare-Object -ReferenceObject $currentHostnames -DifferenceObject $customDomainsToRemove | Where-Object -FilterScript {$_.SideIndicator -eq "<="} | Select-Object -ExpandProperty InputObject
    }
    
    process {
        # Check, if there are new domains to remove
        if ($customDomainsToRemove.count -eq 0) {
            Write-Verbose "No domains to remove from Function App $FunctionAppName."
            return
        }

        # Remove domains from Function App
        Write-Verbose "Removing $($customDomainsToRemove.count) domains from Function App $FunctionAppName : $($customDomainsToRemove -join ", ")..."
        $setAzWebApp = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $FunctionAppName
            HostNames         = $newCustomDomains
            ErrorAction       = "Stop"
            WarningAction     = "Stop"
        }

        try {
            if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Remove custom domains")) {
                $null = Set-AzWebApp @setAzWebApp
            }
        }
        catch {
            Write-Error -Message $_.Exception.Message
            return
        }
    }
}