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
            foreach ($domain in $DomainName) { $domainList += $domain}
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
        $removeCustomDomains = @()
        foreach ($domain in $domainList) {
            
            Write-Host "Working on Domain: $Domain"
            # Check, if domain has correct format
            if ($domain -notmatch "^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$") {
                Write-Error -Message "Domain $($domain) has incorrect format. Please provide domain in format 'contoso.com'."
                return
            }

            #Check if CustomDomain is added as Custom Domain
            $MTASTSDomain = "mta-sts." + $domain
            If ($CustomDomainNames -match $MTASTSDomain)
            {
                #Custom Domain is present
                Write-Host "Adding Domain to Array" -ForegroundColor Green
                $removeCustomDomains += $MTASTSDomain 
            } else {
                #Custom Domain not present
                Write-Host "Custom Domain not present.Skipping..." -ForegroundColor Yellow
            }
        }


        # Check, if there are new domains to remove
        if ($removeCustomDomains.count -eq 0) {
            Write-Host "No domains to remove from Function App $FunctionAppName."
            return
        }

        # Add the current domains to the list of domains to remove
        $newCustomDomains = Compare-Object -ReferenceObject $CustomDomainNames -DifferenceObject $removeCustomDomains | Where-Object -FilterScript {$_.SideIndicator -eq "<="} | Select-Object -ExpandProperty InputObject

        # Remove domains from Function App
        Write-Host "Removing $($removeCustomDomains.count) domains from Function App $FunctionAppName : $($removeCustomDomains -join ", ")..." -ForegroundColor Green
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

		#Remove Managed Certificate if needed
		Write-Host "Remove Certificates" -ForegroundColor Green
		[Array]$WebAppCertificates = Get-AzWebAppCertificate -ResourceGroupName $ResourceGroupName
		Foreach ($Certificate in $WebAppCertificates)
		{
			$SubjectName = $Certificate.SubjectName
			If ($SubjectName -match $removeCustomDomains)
			{
				#Get Thumbprint of Certificate
				$Thumbprint = $Certificate.Thumbprint
				
				#Remove Managed Certificate
				Write-Host "Remove Managed Certificate: $SubjectName Thumbprint: $Thumbprint"
				Remove-AzWebAppCertificate -ResourceGroupName $ResourceGroupName -Thumbprint $Thumbprint
			}
		}

    }
}