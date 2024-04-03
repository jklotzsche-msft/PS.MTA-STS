function Add-PSMTASTSCustomDomain {
    <#
        .SYNOPSIS
        Add-PSMTASTSCustomDomain adds custom domains to MTA-STS Function App.

        .DESCRIPTION
        Add-PSMTASTSCustomDomain adds custom domains to MTA-STS Function App. It also creates new certificate for each domain and adds binding to Function App.

        .PARAMETER CsvPath
        Provide path to csv file with accepted domains. Csv file should have one column with header "DomainName" and list of domains in each row.

        .PARAMETER DomainName
        Provide list of domains.

        .PARAMETER ResourceGroupName
        Provide name of Resource Group where Function App is located.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .PARAMETER DoNotAddManagedCertificate
        Switch to not add managed certificate to Function App. This is useful, if you want to use your own certificate.

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
        Add-PSMTASTSCustomDomain -CsvPath "C:\temp\accepted-domains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and adds them to Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS". It also creates new certificate for each domain and adds binding to Function App.

        .EXAMPLE
        Add-PSMTASTSCustomDomain -DomainName "contoso.com", "fabrikam.com" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Adds domains "contoso.com" and "fabrikam.com" to Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS". It also creates new certificate for each domain and adds binding to Function App.

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

        [switch]
        $DoNotAddManagedCertificate,

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
        $newCustomDomains = @()
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
            if ($domain.DomainName -notin $newCustomDomains) {
                Write-Verbose "Adding domain $($domain.DomainName) to list of domains..."
                $newCustomDomains += $domain.DomainName
            }
        }

        # Check, if a domain name is already used in our Function App
        $currentHostnames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -ErrorAction Stop
        $customDomainsToAdd = @()
        foreach ($newDomain in $newCustomDomains) {
            if ($newDomain -in $currentHostnames) {
                Write-Verbose "Domain $newDomain already exists in Function App $FunctionAppName. Skipping..."
                continue
            }

            Write-Verbose "Adding domain $newDomain to list of domains, which should be added to Function App $FunctionAppName..."
            $customDomainsToAdd += $newDomain
        }

        # Check, if there are new domains to add
        if ($customDomainsToAdd.count -eq 0) {
            Write-Verbose "No new domains to add to Function App $FunctionAppName."
            return
        }

        # Add the current domains to the list of new domains
        # forcing currentHostnames to be an array, it could be a string if only single name is present.
        $newCustomDomains = @($currentHostnames) + $customDomainsToAdd
    }
    
    process {
        # Add new domains to Function App
        Write-Verbose "Adding $($customDomainsToAdd.count) domains to Function App $FunctionAppName : $($customDomainsToAdd -join ", ")..."
        $setAzWebApp = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $FunctionAppName
            HostNames         = $newCustomDomains
            ErrorAction       = "Stop"
            WarningAction     = "Stop"
        }

        try {
            if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Add custom domains")) {
                $null = Set-AzWebApp @setAzWebApp
            }
        }
        catch {
            if ($_.Exception.Message -like "*A TXT record pointing from*was not found*") {
                Write-Warning -Message $_.Exception.Message
            }
            else {
                Write-Error -Message $_.Exception.Message
                return
            }
        }

        # Stop here, if we should not add managed certificate
        if ($DoNotAddManagedCertificate) {
            Write-Verbose "Managed certificate will not be added to Function App $FunctionAppName."
            return
        }

        # Add managed certificate to Function App
        foreach ($customDomainToAdd in $customDomainsToAdd) {
            Write-Verbose "Adding certificate for $customDomainToAdd..."
            $newAzWebAppCertificate = @{
                ResourceGroupName = $ResourceGroupName
                WebAppName        = $FunctionAppName
                Name              = "mtasts-cert-$($customDomainToAdd.replace(".", "-"))"
                HostName          = $customDomainToAdd
                AddBinding        = $true
                SslState          = "SniEnabled"
            }

            try {
                if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Add certificate for $customDomainToAdd")) {
                    $null = New-AzWebAppCertificate @newAzWebAppCertificate
                }
            }
            catch {
                Write-Error -Message $_.Exception.Message
                return
            }
        }
    }
}