function ConvertFrom-PSMTASTSTxtRecord {
    <#
        .SYNOPSIS
        Converts DNS TXT records to their logical text values.

        .DESCRIPTION
        Joins the character strings within each classic DNS or Google DNS-over-HTTPS TXT record.
        Non-TXT answers are ignored. Quoted DNS presentation strings and escaped characters are decoded.
        Unquoted DNS-over-HTTPS values are already logical text and are preserved unchanged.

        .PARAMETER InputObject
        A classic DNS record or an individual DNS-over-HTTPS answer record.

        .EXAMPLE
        [pscustomobject]@{ Type = 16; Data = '"v=STSv1; " "id=20261111000000Z;"' } | ConvertFrom-PSMTASTSTxtRecord

        Returns one logical TXT value without presentation quotes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [object]
        $InputObject
    )

    process {
        if ($null -ne $InputObject) {
            if ($null -ne $InputObject.Strings) {
                $InputObject.Strings -join ''
            }
            elseif ($InputObject.Type -eq 16) {
                $data = [string]$InputObject.Data
                if ($data.StartsWith('"')) {
                    $pattern = '"((?:\\.|[^"\\])*)"'
                    $segments = [regex]::Matches($data, $pattern)
                    if ($segments.Count -eq 0 -or [regex]::Replace($data, $pattern, '').Trim().Length -gt 0) {
                        throw 'Malformed DNS TXT presentation data: expected quoted character strings.'
                    }

                    # All quoted segments belong to this one TXT record.
                    $parts = foreach ($segment in $segments) {
                        [regex]::Replace($segment.Groups[1].Value, '\\([0-9]{3}|.)', {
                            param($match)
                            $escaped = $match.Groups[1].Value
                            if ($escaped -match '^[0-9]{3}$') {
                                $value = [int]$escaped
                                if ($value -gt 255) {
                                    throw 'Malformed DNS TXT escape: decimal values must be between 000 and 255.'
                                }
                                [string][char]$value
                            }
                            else {
                                $escaped
                            }
                        })
                    }
                    $parts -join ''
                }
                else {
                    $data
                }
            }
        }
    }
}
