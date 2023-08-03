function Add-PSMTASTSCustomDomain {
    <#
        .SYNOPSIS
        Add-PSMTASTSCustomDomain adds custom domains to MTA-STS Function App.

        .DESCRIPTION
        Add-PSMTASTSCustomDomain adds custom domains to MTA-STS Function App. It also creates new certificate for each domain and adds binding to Function App.

        .PARAMETER CsvPath
        Provide path to csv file with accepted domains. Csv file should have one column with header "DomainName" and list of domains in each row.

        .PARAMETER ResourceGroupName
        Provide name of Resource Group where Function App is located.

        .PARAMETER FunctionAppName
        Provide name of Function App.

        .PARAMETER WhatIf
        Switch to run the command in a WhatIf mode.

        .PARAMETER Confirm
        Switch to run the command in a Confirm mode.

        .EXAMPLE
        Add-PSMTASTSCustomDomain -CsvPath "C:\temp\accepted-domains.csv" -ResourceGroupName "MTA-STS" -FunctionAppName "MTA-STS-FunctionApp"

        Reads list of accepted domains from "C:\temp\accepted-domains.csv" and adds them to Function App "MTA-STS-FunctionApp" in Resource Group "MTA-STS". It also creates new certificate for each domain and adds binding to Function App.

        .LINK
        https://github.com/jklotzsche-msft/PS.MTA-STS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $CsvPath,

        [Parameter(Mandatory = $true)]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]
        $FunctionAppName
    )
    
    begin {
        if ($null -eq (Get-AzContext)) {
            Write-Warning "Connecting to Azure service..."
            $null = Connect-AzAccount -ErrorAction Stop
        }

        # Import csv file with accepted domains
        Write-Verbose "Importing csv file from $CsvPath..."
        $acceptedDomains = Import-Csv -Path $CsvPath -Encoding UTF8 -Delimiter ";" -ErrorAction Stop
    }
    
    process {
        trap {
            Write-Error $_
            return
        }
        
        $newHostNames = @()
        $currentHostnames = Get-PSMTASTSCustomDomain -ResourceGroupName $ResourceGroupName -FunctionAppName $FunctionAppName
        $newHostNames += $currentHostnames
        foreach ($acceptedDomain in $acceptedDomains) {
            # Prepare new domain
            $newDomain = "mta-sts.$($acceptedDomain.DomainName)"
            if ($newDomain -notin $newHostNames) {
                $newHostNames += $newDomain
            }
        }

        # Try to add all domains to Function App
        if (Compare-Object -ReferenceObject $currentHostnames -DifferenceObject $newHostNames) {
            Write-Verbose "Adding $($newHostNames.count - $currentHostnames.count) domains to Function App $FunctionAppName..."
            try {
                $null = Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -HostNames $newHostNames -ErrorAction Stop -WarningAction Stop
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
        }

        # Create new certificate and add binding, if needed
        $domainsWithoutCert = Get-azwebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName | Select-Object -ExpandProperty HostNameSslStates | Where-Object -FilterScript { $_.SslState -eq "Disabled" -and $_.Name -notlike "*azurewebsites.net" } | Select-Object -ExpandProperty Name
        foreach ($domainWithoutCert in $domainsWithoutCert) {
            $checkCertificate = Get-AzWebAppCertificate -ResourceGroupName $ResourceGroupName  -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_.SubjectName -eq $domainWithoutCert }
            if ($checkCertificate) {
                Write-Verbose "Removing old certificate for $domainWithoutCert..."
                foreach ($thumbprint in $checkCertificate.Thumbprint) {
                    Remove-AzWebAppCertificate -ResourceGroupName $ResourceGroupName -ThumbPrint $thumbprint
                }
            }

            Write-Verbose "Adding certificate for $domainWithoutCert..."
            $newAzWebAppCertificate = @{
                ResourceGroupName = $ResourceGroupName
                WebAppName        = $FunctionAppName
                Name              = "mtasts-cert-$($domainWithoutCert.replace(".", "-"))"
                HostName          = $domainWithoutCert
                AddBinding        = $true
                SslState          = "SniEnabled"
            }
            $null = New-AzWebAppCertificate @newAzWebAppCertificate
        }
    }
}