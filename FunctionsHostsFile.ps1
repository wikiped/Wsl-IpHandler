function Get-HostsFileContent {
    param (
        [Parameter()]
        [ValidateScript( { Test-Path $_ -PathType Leaf } )]
        [string]$FilePath
    )
    if (-not $PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath = $Env:WinDir + '\system32\Drivers\etc\hosts'
    }
    Get-Content $FilePath
}

function Write-HostsFileContent {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [ValidateNotNull()]
        [string[]]$Records,

        [Parameter()]
        [string]$FilePath
    )
    $fn = $MyInvocation.MyCommand.Name

    if (-not $PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath = $Env:WinDir + '\system32\Drivers\etc\hosts'
    }

    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }

    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve)

    Write-Debug "${fn}: Setting $FilePath with $($Records.Count) records."

    if (-not (IsElevated)) {
        Write-Debug "${fn}: Invoking Elevated Permissions ..."
        $Records = $Records -join "`n"
        $command = "Set-Content -Path `"$FilePath`" -Value `"$Records`" -Encoding ASCII"
        Invoke-CommandEncodedElevated $command
    }
    else {
        Set-Content -Path $FilePath -Value $Records -Encoding ASCII
    }
}

function Test-RecordIsComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][ValidateNotNull()]
        [string]$Record
    )
    [string]::IsNullOrWhiteSpace($Record) -or $Record -match '^\s*#'
}

function Test-RecordContainsIpAddress {
    [CmdLetBinding()]
    param ([string]$Record, [string]$regexIpAddress)
    $Record -match "^\s*$regexIpAddress"
}

function Test-RecordContainsHost {
    [CmdLetBinding()]
    param ([string]$Record, [string]$regexHostName)
    $Record -match ".*$regexHostName.*"
}

function Test-IsHostAssignedToIpAddress {
    [CmdLetBinding()]
    param ([string]$Record, [string]$regexIpAddress, [string]$regexHostName)
    $ip_pattern = '^\s*(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))\.){3}(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))(\s|$))'
    ($Record -match $ip_pattern) -and (Test-RecordContainsHost $Record $regexHostName) -and -not (Test-RecordContainsIpAddress $Record $regexIpAddress)
}

function Get-IpAddressHostsCommentTuple {
    [CmdLetBinding()]
    param($Record)
    if (Test-RecordIsComment $Record) { return $null }
    $Ip, $rest = $Record.Trim() -split ' ', 2
    $Hosts, $Comment = $rest.Trim() -split '#', 2
    $Ip.Trim(), $Hosts.Trim(), ('#' + $Comment)
}

function Get-HostsCount {
    [CmdLetBinding()]
    param([Parameter(Mandatory)][array]$Hosts)
    ($Hosts -split ' ').Count
}

function Get-HostsCountFromRecord {
    [CmdLetBinding()]
    param([Parameter(Mandatory)][ValidateNotNull()][string]$Record)
    $_, $hosts, $_ = Get-IpAddressHostsCommentTuple $Record
    if ($null -eq $hosts) {
        0
    }
    else {
        ($hosts -split ' ').Count
    }
}

function New-IpAddressHostRecord {
    [CmdLetBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$IpAddress,

        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [string]$Comment
    )
    if ($PSBoundParameters.ContainsKey('Comment')) {
        $Comment += '  # Modified by WSL-IpHandler PowerShell Module'
    }
    else {
        $Comment = '  # Created by WSL-IpHandler PowerShell Module'
    }
    $line = $IpAddress.PadRight(17, ' ')
    $line += $HostName
    $line + ($comment ? $comment.PadLeft(80 - $line.Length, ' ') : '')
}

function Add-HostToRecord {
    param (
        [Parameter(Mandatory)]
        [array]$Record,

        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ReplaceExistingHosts
    )

    $regexHostName = [regex]::Escape($HostName)

    $existingIp, $existingHosts, $comment = Get-IpAddressHostsCommentTuple $Record

    if (Test-RecordContainsHost $_ $regexHostName) {
        if ((Get-HostsCount $existingHosts) -gt 1 -and $ReplaceExistingHosts.IsPresent) {
            $Modified.Value = $true
            New-IpAddressHostRecord $existingIp $HostName $comment
        }
        else {
            $Record  # Record has Correct Ip and Correct Host -> Keep it as is
        }
    }
    else {
        $Modified.Value = $true
        if (-not $ReplaceExistingHosts.IsPresent) {
            # Record has Correct Ip but does not have Correct Host -> Add host name
            $HostName = $existingHosts + " $HostName"
        }
        New-IpAddressHostRecord $existingIp $HostName $comment
    }
}

function Remove-HostFromRecords {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [array]$Records,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [Parameter()]
        [switch]$RemoveAllOtherHosts
    )
    $fn = $MyInvocation.MyCommand.Name
    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }
    Write-Debug "${fn}: Before processing: `$Records.Count=$($Records.Count)"

    $Records = $Records | ForEach-Object {
        if (Test-RecordIsComment $_) {
            $_  # This line is a comment - keep it as is
        }
        else {
            $regexHostName = [regex]::Escape($HostName)

            if (Test-RecordContainsHost $_ $regexHostName) {
                # Host is used for another IP - Remove host from this record
                $existingIp, $existingHosts, $comment = Get-IpAddressHostsCommentTuple $_
                $hostsArray = $existingHosts -split ' '
                $Modified.Value = $true  # host in use - we need to remove this host / record

                if ($hostsArray.Count -gt 1) {
                    # It is NOT the only host -> modify record
                    $newHosts = $hostsArray -notmatch $regexHostName
                    New-IpAddressHostRecord $existingIp ($newHosts -join ' ') $comment
                } # else It is the only host -> Don't return anythin -> Drop this record
            }
            else {
                # This Record is for some other host - keep it as is
                $_
            }
        }
    }
    Write-Debug "${fn}: After processing: `$Records.Count=$($Records.Count)"
    Write-Debug "${fn}: After processing: `$Modified=$($Modified.Value)"
    $Records
}

function Add-IpAddressHostToRecords {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [array]$Records,

        [ValidateNotNullOrEmpty()]
        [string]$HostIpAddress,

        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ReplaceExistingHosts
    )

    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }

    $regexIpAddress = [Regex]::Escape($HostIpAddress)
    $RecordFound = $false

    $Records = $Records | ForEach-Object {
        if (Test-RecordIsComment $_) {
            $_  # This line is a comment - keep it as is
        }
        elseif (Test-RecordContainsIpAddress $_ $regexIpAddress) {
            $RecordFound = $true
            if (-not $RecordFound) {
                Add-HostToRecord -Record $_ -HostName $HostName -Modified $Modified -ReplaceExistingHosts:$ReplaceExistingHosts
                $RecordFound = $true
            }  # else Record has Correct Ip and Correct Host, but it's a duplicate -> Drop it
        }
        else {
            Remove-HostFromRecords -Record $_ -HostName $HostName -Modified $Modified -RemoveAllOtherHosts:$ReplaceExistingHosts
        }
    }
    if (-not $RecordFound) {
        $newRecord = New-IpAddressHostRecord $HostIpAddress $HostName
        $Records += $newRecord
        $Modified.Value = $true
    }
    $Records
}
