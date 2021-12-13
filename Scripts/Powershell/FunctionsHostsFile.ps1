#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

function Get-IpAddressPattern {
    '(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))\.){3}(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))(\s|$))'
}

Function Get-IpAddressFromString {
    [OutputType([ipaddress])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()][ValidateNotNull()]
        [array]$InputString
    )
    $array = @($input)
    if ($array.Count) { $InputString = $InputString }
    if (!(Test-Path variable:InputString)) { $InputString = @() }
    $IpPattern = Get-IpAddressPattern
    $InputString | ForEach-Object {
        [ipaddress](($_ -split ' ') -match $IpPattern | Select-Object -First 1)
    }
}

function Get-HostsFileContent {
    param (
        [Parameter()]
        [ValidateScript( { Test-Path $_ -PathType Leaf } )]
        [string]$FilePath
    )
    if (-not $PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath = Join-Path $Env:WinDir '\system32\Drivers\etc\hosts' -Resolve
    }
    Get-Content $FilePath
}

function Get-IpAddressHostRecords {
    param (
        [Parameter()]
        [ValidateScript( { Test-Path $_ -PathType Leaf } )]
        [string]$FilePath
    )
    if (-not $PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath = Join-Path $Env:WinDir '\system32\Drivers\etc\hosts' -Resolve
    }
    Get-Content $FilePath | Where-Object { -not (Test-RecordIsComment $_) }
}

function Write-HostsFileContent {
    param (
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][AllowNull()]
        [string[]]$Records,

        [Parameter()]
        [string]$FilePath
    )


    if (-not $PSBoundParameters.ContainsKey('FilePath')) {
        $FilePath = $Env:WinDir + '\system32\Drivers\etc\hosts'
    }

    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }
    if ($null -eq $Records) { $Records = @() }

    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null

    Write-Debug "$(_@) Setting $FilePath with $($Records.Count) records."

    if (-not (IsElevated)) {
        Write-Debug "$(_@) Invoking Elevated Permissions ..."
        $Records = $Records -join "`n"
        $command = "Set-Content -Path `"$FilePath`" -Value `"$Records`" -Encoding ASCII -Confirm:`$False"
        Invoke-CommandElevated $command -Encode
    }
    else {
        Set-Content -Path $FilePath -Value $Records -Encoding ASCII -Confirm:$false
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
    param ([string]$Record, [ipaddress]$IpAddress)
    $Record -match "^\s*$([regex]::Escape("$IpAddress"))\b"
}

function Test-RecordContainsHost {
    [CmdLetBinding()]
    param (
        [parameter(Mandatory)][AllowNull()][AllowEmptyString()]
        [string]$Record,

        [parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$HostName
    )
    if ([string]::IsNullOrWhiteSpace($Record)) { return $false }
    ($Record -replace '#.*' -replace '\s{2,}', ' ' -split ' ' |
        Where-Object { $_.Trim() -match "^$([regex]::Escape("$HostName"))$" } |
        Measure-Object).Count -gt 0
}

function Test-RecordContainsIpAddressAndHost {
    [CmdLetBinding()]
    param ([string]$Record, [ipaddress]$IpAddress, [string]$HostName)
    -not (Test-RecordIsComment $Record) -and (Test-RecordContainsHost $Record $HostName) -and (Test-RecordContainsIpAddress $Record $IpAddress)
}

function Get-IpAddressHostsCommentTuple {
    [CmdLetBinding()]
    param($Record)
    if (Test-RecordIsComment $Record) { return }
    $Ip, $rest = $Record.Trim() -split ' ', 2
    $Hosts, $Comment = $rest.Trim() -split '#', 2
    $Ip.Trim(), $Hosts.Trim(), ('#' + $Comment)
}

function Get-HostsCount {
    [CmdLetBinding()]
    param([Parameter(Mandatory)][string]$Hosts)
    ($Hosts -split ' ').Count
}

function Get-HostsCountFromRecord {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][AllowEmptyString()]
        [string]$Record
    )
    $_, $hosts, $_ = Get-IpAddressHostsCommentTuple $Record
    if ($null -eq $hosts) {
        0
    }
    else {
        ($hosts -split ' ').Count
    }
}

function Get-HostForIpAddress {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ipaddress]$IpAddress
    )
    Get-IpAddressHostRecords |
        Where-Object { Test-RecordContainsIpAddress $_ "$IpAddress" } |
        ForEach-Object { (Get-IpAddressHostsCommentTuple $_)[1] } |
        Select-Object -First 1
}

function New-IpAddressHostRecord {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IpAddress,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter()]
        [string]$Comment
    )
    if ($Comment) {
        if ($Comment.Contains('WSL-IpHandler')) {
            $Comment = '  # Modified by WSL-IpHandler PowerShell Module'
        }
        else {
            $Comment += ' Modified by WSL-IpHandler PowerShell Module'
        }
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
        [string]$Record,

        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ReplaceExistingHosts
    )
    Write-Debug "$(_@) `$Record: $($Record | Out-String)"
    Write-Debug "$(_@) `$Record: $($Record.GetType())"
    $existingIp, $existingHosts, $comment = Get-IpAddressHostsCommentTuple $Record

    if (Test-RecordContainsHost $_ $HostName) {
        if ((Get-HostsCount $existingHosts) -gt 1 -and $ReplaceExistingHosts) {
            $Modified.Value = $true
            New-IpAddressHostRecord $existingIp $HostName $comment
        }
        else {
            $Record  # Record has Correct Ip and Correct Host -> Keep it as is
        }
    }
    else {
        $Modified.Value = $true
        if (-not $ReplaceExistingHosts) {
            # Record has Correct Ip but does not have Correct Host -> Add host name
            $HostName = $existingHosts + " $HostName"
        }
        New-IpAddressHostRecord $existingIp $HostName $comment
    }
}

function Remove-HostFromRecords {
    param (
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][AllowEmptyString()]
        [string[]]$Records,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [Parameter()]
        [switch]$RemoveAllOtherHosts
    )

    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }
    if ($null -eq $Records) { $Records = @() }

    Write-Debug "$(_@) Before processing: `$Records.Count=$($Records.Count)"

    $Records = $Records | ForEach-Object {
        if (Test-RecordIsComment $_) {
            $_  # This line is a comment - keep it as is
        }
        else {
            $existingIp, $existingHosts, $comment = Get-IpAddressHostsCommentTuple $_

            if (Test-RecordContainsHost $existingHosts $HostName) {
                # Host is used for another IP - Remove host from this record
                $hostsArray = $existingHosts -split ' '
                $Modified.Value = $true  # host in use - we need to remove this host / record

                if ($hostsArray.Count -gt 1) {
                    # It is NOT the only host -> modify record
                    $newHosts = $hostsArray | Where-Object { -not (Test-RecordContainsHost $_ $HostName) }
                    New-IpAddressHostRecord $existingIp ($newHosts -join ' ') $comment
                } # else It is the only host -> Don't return anythin -> Drop this record
            }
            else {
                # This Record is for some other host - keep it as is
                $_
            }
        }
    }
    Write-Debug "$(_@) After processing: `$Records.Count=$($Records.Count)"
    Write-Debug "$(_@) After processing: `$Modified=$($Modified.Value)"
    $Records
}

function Add-IpAddressHostRecord {
    param (
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][AllowNull()]
        [string[]]$Records,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ipaddress]$HostIpAddress,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [Parameter()]
        [switch]$ReplaceExistingHosts
    )
    $array = @($input)
    if ($array.Count) { $Records = $array }
    if (!(Test-Path variable:Records)) { $Records = @() }
    if ($null -eq $Records) { $Records = @() }

    $RecordFound = $false

    $newRecords = $Records | ForEach-Object {
        if (Test-RecordIsComment $_) {
            $_  # This line is a comment - keep it as is
        }
        elseif (Test-RecordContainsIpAddress $_ $HostIpAddress) {
            Write-Debug "$(_@) $HostIpAddress was found in existing record: $_"
            if (-not $RecordFound) {
                Add-HostToRecord -Record $_ -HostName $HostName -Modified $Modified -ReplaceExistingHosts:$ReplaceExistingHosts
                Write-Debug "$(_@) $HostName was added to existing record: $_"
                $RecordFound = $true
            }  # else Record has Correct Ip and Correct Host, but it's a duplicate -> Drop it
            else {
                Write-Debug "$(_@) Dropping duplicate record: $_"
            }
        }
        else {
            Write-Debug "$(_@) Removing $HostName from record: $_"
            Remove-HostFromRecords -Record $_ -HostName $HostName -Modified $Modified -RemoveAllOtherHosts:$ReplaceExistingHosts
        }
    }
    if (-not $RecordFound) {
        $newRecord = New-IpAddressHostRecord $HostIpAddress $HostName
        $newRecords += $newRecord
        Write-Debug "$(_@) Created new record: $newRecord"
        $Modified.Value = $true
    }
    $newRecords
}
