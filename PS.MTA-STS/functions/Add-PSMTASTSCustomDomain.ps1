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
        $CsvDelimiter = ";",

        [String]
        $DnsServerToQuery = "8.8.8.8"
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

        if ($DomainName) 
        {
            $domainList = @()
            #foreach ($domain in $DomainName) { $domainList += @{DomainName = $domain } }
            foreach ($domain in $DomainName) { $domainList += $domain } 
        }
    }

    process {

        #Check FunctionApp
        Write-Host "Get Azure Function App"
        $FunctionAppResult = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -WarningAction SilentlyContinue
        If ($Null -eq $FunctionAppResult)
        {
            #Function App not found
            Write-Host "FunctionApp $FunctionAppName not found"
            Break
        }

        #Get CustomDomain Names
        Write-Host "Get CustomDomainNames from Azure Function App"
        [Array]$CustomDomainNames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName -ErrorAction Stop

        # Prepare new domains
        #$newCustomDomains = @()
        $customDomainsToAdd = @()
        foreach ($domain in $domainList) 
        {
            Write-Host "Working on Domain: $Domain"
            # Check, if domain has correct format
            if ($domain -notmatch "^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$") {
                Write-Error -Message "Domain $domain has incorrect format. Please provide domain in format 'contoso.com'."
                return
            }

            #Check if mta-sts.domain.tld CNAME $FunctionAppName.azurewebsites.net
            Write-Host "Checking CNAME: mta-sts.$Domain CNAME $FunctionAppName.azurewebsites.net"
            $MTASTSDomain = "mta-sts." + $domain
            #Write-Host "Debug: MTASTSDomain: $MTASTSDomain"
            $MTASTS_CNAME = Resolve-DnsName -Name $MTASTSDomain -Server $DnsServerToQuery -Type CNAME -ErrorAction SilentlyContinue | Where-Object {$_.NameHost -eq "$FunctionAppName.azurewebsites.net"} | Select-Object NameHost
            #Write-Host "Debug: MTASTS_CNAME: $MTASTS_CNAME"
            If ($Null -eq $MTASTS_CNAME)
            {
                Write-Host "CNAME not found"
            } else {
                If ($MTASTS_CNAME.NameHost -ne $("$FunctionAppName.azurewebsites.net"))
                {
                    Write-Host "CNAME does not match FunctionApp"
                } else {
                    #CNAME Matches
                    #Check if CustomDomain is already added as Custom Domain
                    If ($CustomDomainNames -match $MTASTSDomain)
                    {
                        #Custom Domain already present
                        Write-Host "Custom Domain already present" -ForegroundColor Yellow
                    } else {
                        #Custom Domain not present
                        Write-Host "Adding Domain to Array" -ForegroundColor Green
                        $customDomainsToAdd += $MTASTSDomain 
                    }
                }
            }
        }

        # Check, if there are new domains to add
        if ($customDomainsToAdd.count -eq 0) {
            Write-Host "No new domains to add to Function App $FunctionAppName."
            return
        }

        # Add new domains to Function App
        $customDomainsToAdd += $CustomDomainNames
        Write-Host "Add CustomDomains to Function App" -ForegroundColor Green
        #Write-Verbose "Adding $($customDomainsToAdd.count) domains to Function App $FunctionAppName : $($customDomainsToAdd -join ", ")..."
        $setAzWebApp = @{
            ResourceGroupName = $ResourceGroupName
            Name              = $FunctionAppName
            HostNames         = $customDomainsToAdd
            ErrorAction       = "Stop"
            WarningAction     = "Stop"
        }

        try {
            if ($PSCmdlet.ShouldProcess("Function App $FunctionAppName", "Add custom domains")) {
                $null = Set-AzWebApp @setAzWebApp
            }
        } catch {
            Write-Error -Message $_.Exception.Message
            return
        }

        # Stop here, if we should not add managed certificate
        if ($DoNotAddManagedCertificate) {
            Write-Verbose "Managed certificate will not be added to Function App $FunctionAppName."
            return
        }

        # Add managed certificate to Function App
        Write-Host "Add Managed Certificate to Function App" -ForegroundColor Green
        foreach ($customDomainToAdd in $customDomainsToAdd) 
        {
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