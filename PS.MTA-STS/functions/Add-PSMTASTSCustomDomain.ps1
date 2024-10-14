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

        .PARAMETER SkipCAACheck
        Switch to skip the Certification Authority Authorization (CAA) check.

        .PARAMETER CsvEncoding
        Provide encoding of csv file. Default is "UTF8".

        .PARAMETER CsvDelimiter
        Provide delimiter of csv file. Default is ";".

        .PARAMETER DnsServer
        Provide a String containing the IP address of the DNS server, which should be used to query the MX record. Default is 8.8.8.8 (Google DNS).

        .PARAMETER WhatIf
        Switch to run the command in a WhatIf mode.

        .PARAMETER Confirm
        Switch to run the command in a Confirm mode.

        .EXAMPLE
        Add-PSMTASTSCustomDomain -CsvPath "C:\temp\accepted-domains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "func-MTA-STS"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and adds them to Function App "func-MTA-STS" in Resource Group "MTA-STS". It also creates new certificate for each domain and adds binding to Function App.

        .EXAMPLE
        Add-PSMTASTSCustomDomain -DomainName "contoso.com", "fabrikam.com" -ResourceGroupName "MTA-STS" -FunctionAppName "func-MTA-STS"

        Adds domains "contoso.com" and "fabrikam.com" to Function App "func-MTA-STS" in Resource Group "MTA-STS". It also creates new certificate for each domain and adds binding to Function App.

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

        [switch]
        $SkipCAACheck,

        [Parameter(ParameterSetName = "Csv")]
        [string]
        $CsvEncoding = "UTF8",

        [Parameter(ParameterSetName = "Csv")]
        [string]
        $CsvDelimiter = ";",

        [String]
        $DnsServer = "8.8.8.8"
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
            Write-Verbose "Connecting to Azure service"
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
                throw "Domain $domain has incorrect format. Please provide domain in format 'contoso.com'."
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
        $newCustomDomainsToAdd = @()
        foreach ($domain in $domainList) {
            Write-Verbose "Working on Domain: $Domain"

            #Check if mta-sts.domain.tld CNAME $FunctionAppName.azurewebsites.net exists
            $mtaStsDomain = "mta-sts." + $domain
            $mtaStsCName = Resolve-PSMTASTSDnsName -Name $mtaStsDomain -Server $DnsServer -Type CNAME | Where-Object { $_.NameHost -like "*.azurewebsites.net" } | Select-Object -ExpandProperty NameHost

            # Check, if CNAME record exists
            if ($Null -eq $mtaStsCName -or $mtaStsCName -ne "$FunctionAppName.azurewebsites.net") {
                Write-Warning "CNAME record not found for $mtaStsDomain with value $FunctionAppName.azurewebsites.net. Found value: $mtaStsCName - Please create/update it and try again with this domain. Continuing with next domain."
                continue
            }

            #Check if CAA record exists and contains digicert.com
            If ($SkipCAACheck -ne $true) {
                $json = Invoke-RestMethod -Uri "https://dns.google/resolve?name=$Domain&type=CAA"
                If ($Null -ne $json.Answer.Data) {
                    if (($json.Answer.Data -notcontains '0 issue "digicert.com"') -eq $True) {
                        Write-Warning "Missing digicert.com in Certification Authority Authorization (CAA) Record for $Domain"
                        continue
                    }
                }
            }

            # Add domain to list, if it is not already added
            if ($mtaStsDomain -notin $customDomainNames.CustomDomains) {
                $newCustomDomainsToAdd += $mtaStsDomain
            }
        }

        # Check, if there are new domains to add
        if ($newCustomDomainsToAdd.count -eq 0) {
            Write-Warning "No new domains to add to Function App $FunctionAppName. Stopping here."
            return
        }

        # Add new domains to Function App
        $customDomainsToSet = @()
        $customDomainsToSet += $customDomainNames.DefaultDomain # Add default domain
        $customDomainsToSet += $newCustomDomainsToAdd # Add new custom domains
        if ($null -ne $customDomainNames.CustomDomains) {
            $customDomainsToSet += $customDomainNames.CustomDomains # Add existing custom domains, if any exist
        }
        Write-Verbose "Setting $($customDomainsToSet.count) domains for Function App $FunctionAppName : $($customDomainsToSet -join ", ")"
        $setAzWebApp = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $FunctionAppName
            HostNames         = $customDomainsToSet
        }
        if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Add custom domains")) {
            $null = Set-AzWebApp @setAzWebApp -WarningAction SilentlyContinue
        }

        # Stop here, if we should not add managed certificate
        if ($DoNotAddManagedCertificate) {
            Write-Verbose "Managed certificate will not be added to Function App $FunctionAppName."
            return
        }

        # Add managed certificate to Function App
        Write-Verbose "Add Managed Certificate to Function App"
        foreach ($newCustomDomainToAdd in $newCustomDomainsToAdd) {
            Write-Verbose "Adding certificate for $newCustomDomainToAdd"
            $newAzWebAppCertificate = @{
                ResourceGroupName = $ResourceGroupName
                WebAppName        = $FunctionAppName
                Name              = "mtasts-cert-$($newCustomDomainToAdd.replace(".", "-"))"
                HostName          = $newCustomDomainToAdd
                AddBinding        = $true
                SslState          = "SniEnabled"
            }
            if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Add certificate for $newCustomDomainToAdd")) {
                $null = New-AzWebAppCertificate @newAzWebAppCertificate -WarningAction SilentlyContinue
            }
        }
    }
}