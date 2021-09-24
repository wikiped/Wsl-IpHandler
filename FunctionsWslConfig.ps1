$WslConfigPath = Join-Path $HOME '.wslconfig'
$WslConfig = $null

$script:NoSection = '_'  # Variable Required by Get-IniContent.ps1 and Out-IniFile.ps1
. (Join-Path $PSScriptRoot 'FunctionsPrivateData.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'Get-IniContent.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'Out-IniFile.ps1' -Resolve)

function Get-WslConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][AllowNull()]
        [string]$ConfigPath = $WslConfigPath,

        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "Get-WslConfig loads config from: $ConfigPath"
    if (($null -eq $WslConfig) -or $ForceReadFileFromDisk) {
        $script:WslConfig = Get-IniContent $ConfigPath
    }
    $WslConfig
}

function Test-WslConfigSectionExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: `$SectionName = '$SectionName'"

    if ($config.Contains($SectionName)) {
        Write-Debug "${fn}: Section '$SectionName' Exists!"
        $true
    }
    else {
        Write-Debug "${fn}: Section '$SectionName' Does NOT Exist!"
        $false
    }
}

function Get-WslConfigSectionCount {
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$SectionName = '$SectionName'"

    if (Test-WslConfigSectionExists $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk) {
        (Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk).Count
    }
    else {
        -1
    }
}

function Get-WslConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: `$SectionName = '$SectionName'"

    if (-not (Test-WslConfigSectionExists $SectionName)) {
        Write-Debug "${fn}: Empty Section '$SectionName' Created!"
        $config[$SectionName] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
    }
    $config[$SectionName]
}

function Remove-WslConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$OnlyIfEmpty,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: `$SectionName = '$SectionName'"

    if ($config.Contains($SectionName)) {
        if ($OnlyIfEmpty.IsPresent) {
            Write-Debug "${fn}: Only Remove Empty Section is specified."
            if ($config[$SectionName].Count -eq 0) {
                $config.Remove($SectionName)
                $Modified.Value = $true
                Write-Debug "${fn}: Conditionally Removed Empty Section '$SectionName'."
            }
        }
        else {
            $config.Remove($SectionName)
            $Modified.Value = $true
            Write-Debug "${fn}: Unconditionally Removed Section '$SectionName'."
        }
    }
}

function Get-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter()]
        [object]$DefaultValue,

        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    $name = $MyInvocation.MyCommand.Name
    Write-Debug "${name}: `$SectionName = '$SectionName'"
    Write-Debug "${name}: `$KeyName = '$KeyName'"
    Write-Debug "${name}: `$DefaultValue = '$DefaultValue'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk

    if (-not $section.Contains($KeyName)) {
        Write-Debug "${name}: Section '$SectionName' has no key: '$KeyName'!"
        if ($PSBoundParameters.ContainsKey('DefaultValue')) {
            Write-Debug "${name}: DefaultValue '$DefaultValue' will be assigned to '$KeyName'"
            $section[$KeyName] = $DefaultValue
            if ($PSBoundParameters.ContainsKey('Modified') -and $null -ne $Modified) {
                $Modified.Value = $true
            }
        }
        else {
            Write-Error "${name}: Section '$SectionName' has no key: '$KeyName' and no DefaultValue is given!" -ErrorAction Stop
        }
    }
    Write-Debug "${name}: Value of '$KeyName' in Section '$SectionName': $($section[$KeyName])"
    $section[$KeyName]
}

function Set-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter(Mandatory)][ValidateNotNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$UniqueValue,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$SectionName = '$SectionName'"
    Write-Debug "${fn}: `$KeyName = '$KeyName'"
    Write-Debug "${fn}: `$Value = '$Value'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: Initial Section Content: $($section | Out-String)"

    if ($UniqueValue -and $Value -in $section.Values) {
        Write-Debug "${fn}: with `$UniqueValue=$UniqueValue found existing value: '$Value'"
        $usedOwner = ($Section.GetEnumerator() |
                Where-Object { $_.Value -eq $Value } |
                Select-Object -ExpandProperty Name)
        if ($usedOwner -ne $KeyName) {
            Write-Error "${fn}: Value: '$Value' is already used by: $usedOwner" -ErrorAction Stop
        }
        Write-Error "${fn}: Value: '$Value' is already set to: $usedOwner" -ErrorAction Stop
        return
    }

    if (${section}[$KeyName] -ne $Value) {
        ${section}[$KeyName] = $Value
        $Modified.Value = $true
    }

    Write-Debug "${fn}: '$KeyName' = '$Value'"
    Write-Debug "${fn}: Final Section Content: $($section | Out-String)"
}

function Remove-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$SectionName = '$SectionName'"
    Write-Debug "${fn}: `$KeyName = '$KeyName'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: Initial Section Content: $($section | Out-String)"

    if (${section}.Contains($KeyName)) {
        ${section}.Remove($KeyName)
        $Modified.Value = $true
    }

    Write-Debug "${fn}: Final Section Content: $($section | Out-String)"

    Remove-WslConfigSection $SectionName -OnlyIfEmpty:$true -Modified $Modified
}

function Get-AvailableStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param( [ipaddress]$GatewayIpAddress )

    $fn = $MyInvocation.MyCommand.Name
    $GatewayIpAddress ??= Get-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) -DefaultValue $null
    $PrefixLength = Get-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) -DefaultValue 24

    if ($null -eq $GatewayIpAddress) {
        Write-Debug "${fn}: GatewayIpAddress is not configured in .wslconfig -> Trying System WSL adapter."
        $wslIpObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'vEthernet (WSL)' -ErrorAction SilentlyContinue
        if (-not $null -eq $wslIpObj) {
            $GatewayIpAddress = $wslIpObj.IPAddress
            $PrefixLength = $wslIpObj.PrefixLength
        }
    }

    Write-Debug "${fn}: `$GatewayIpAddress=$GatewayIpAddress"
    Write-Debug "${fn}: `$PrefixLength=$PrefixLength"

    $ipcalc = Join-Path $PSScriptRoot 'IP-Calc.ps1' -Resolve

    $SectionName = (Get-StaticIpAddressesSectionName)

    if (Get-WslConfigSectionCount -gt 0) {
        $secion = Get-WslConfigSection -SectionName $SectionName
        Write-Debug "${fn}: There are $($secion.Count) in Static IP addresses section."
        if ($null -eq $GatewayIpAddress) {
            Write-Warning 'Without Gateway IP address for WSL SubNet available Static IP address will be based on simple sorting algorithm, without any guaranties.'
            $maxIP = $secion.Values |
                Sort-Object { ([ipaddress]$_).IPAddressToString -as [Version] } -Bottom 1

            Write-Debug "${fn}: Max IP address: $maxIP"
            $maxIPobj = & $ipcalc -IpAddress $maxIP -PrefixLength $PrefixLength
            $newIP = [ipaddress]$maxIPobj.Add(1).IpAddress
            Write-Debug "${fn}: Returning IP: $newIP"
            $newIP
        }
        else {
            Write-Debug "${fn}: Selecting available IP address for defined WSL Gateway."
            $ipobj = & $ipcalc -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            $newIP = [ipaddress]($ipobj.GetIParray() |
                    ForEach-Object { [ipaddress]$_ } |
                    Where-Object {
                        $i = $_.IPAddressToString
                        ($i -notin $secion.Values) -and ([version]$i -ne [version]$ipobj.IP)
                    } |
                    Select-Object -First 1
            )
            Write-Debug "${fn}: Returning IP: $newIP"
        }
    }
    else {
        if ($null -eq $GatewayIpAddress) {
            Write-Warning 'Cannot Find available IP address without Gateway IP address for WSL SubNet and without any Static IP addresses in .wslconfig.'
            $null
        }
        else {
            $ipobj = & $ipcalc -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            [ipaddress]$ipobj.Add(1).IpAddress
        }
    }
}

function Get-WslIpOffsetSection {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    $name = $MyInvocation.MyCommand.Name

    if ([string]::IsNullOrWhiteSpace($SectionName)) { $SectionName = (Get-WslIpOffsetSectionName) }
    Write-Debug "${name}: `$SectionName: '$SectionName'"

    Get-WslConfigSection -SectionName $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
}

function Test-ValidStaticIpAddress {
    [CmdletBinding(DefaultParameterSetName = 'Automatic')]
    param (
        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'Automatic')]
        [Parameter(ParameterSetName = 'Manual')]
        [ipaddress]$IpAddress,

        [Parameter(Mandatory)]
        [Parameter(ParameterSetName = 'Manual')]
        [ipaddress]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Manual')]
        [int]$PrefixLength = 24
    )
    $fn = $MyInvocation.MyCommand.Name
    $ipcalc = Join-Path $PSScriptRoot 'IP-Calc.ps1' -Resolve
    Write-Debug "${fn}: `$IpAddress=$IpAddress of type: $($IpAddress.Gettype())"

    if ($PSCmdlet.ParameterSetName -eq 'Automatic') {
        $warnMsg = "You are setting Static IP Address: $IpAddress "

        $GatewayIpAddress = Get-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) -DefaultValue $null

        $usingWslConfig = $null -ne $GatewayIpAddress

        $PrefixLength = Get-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) -DefaultValue $PrefixLength

        if ($null -eq $GatewayIpAddress) {
            $MSFT_NetIPAddress = Get-NetIPAddress -InterfaceAlias 'vEthernet (WSL)' -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $GatewayIpAddress = [ipaddress]$MSFT_NetIPAddress.IPv4Address
            $PrefixLength = $MSFT_NetIPAddress.PrefixLength
        }

        Write-Debug "${fn}: `$GatewayIpAddress=$GatewayIpAddress of type: $($GatewayIpAddress.Gettype())"

        Write-Debug "${fn}: `$PrefixLength=$PrefixLength"

        if ($null -eq $GatewayIpAddress) {
            $warnMsg += 'within currently UnKnownn WSL SubNet that will be set by Windows OS and might have different SubNet!'
        }
        else {
            $GatewayIpObject = (& $ipcalc -IpAddress $GatewayIpAddress.IPAddressToString -PrefixLength $PrefixLength)
            if ($GatewayIpObject.Compare($IpAddress)) {
                Write-Debug "${fn}: $IpAddress is within $($GatewayIpObject.CIDR) when `$usingWslConfig=$usingWslConfig"
                if ($usingWslConfig) {
                    $true
                }
                else {
                    $warnMsg += "within the WSL SubNet: $($GatewayIpObject.CIDR), but which is set by Windows OS and might change after system restarts!"
                }
            }
            else {
                Write-Debug "${fn}: $IpAddress is NOT within $($GatewayIpObject.CIDR) when `$usingWslConfig=$usingWslConfig"
                if ($usingWslConfig) {
                    $warnMsg += "within DIFFERENT Static WSL SubNet: $($GatewayIpObject.CIDR)!"
                }
                else {
                    $warnMsg += "within DIFFERENT Non Static WSL SubNet: $($GatewayIpObject.CIDR) which is set by Windows OS and might change after system restarts!"
                }
            }
            Write-Warning "$warnMsg`nTo avoid this warning either change IP Address to be within the SubNet or set Static Gateway IP Address of WSL SubNet in -GatewayIpAddress Parameter of 'Install-WslHandler' or 'Set-WslNetworkParameters' commands!"
            $false
        }
    }
    else {
        Write-Debug "${fn}: `$GatewayIpAddress=$GatewayIpAddress of type: $($GatewayIpAddress.Gettype())"
        Write-Debug "${fn}: `$PrefixLength=$PrefixLength"
        $GatewayIPObject = (& $ipcalc -IpAddress $GatewayIpAddress.IPAddressToString -PrefixLength $PrefixLength)
        Write-Debug "${fn}: `$GatewayIPObject: $($GatewayIPObject | Out-String)"
        if ($GatewayIPObject.Compare($IpAddress)) {
            Write-Debug "${fn}: $IpAddress is within $($GatewayIPObject.CIDR)"
            $true
        }
        else {
            Write-Debug "${fn}: $IpAddress is NOT within $($GatewayIPObject.CIDR)"
            Write-Error "You are setting Static IP Address: $IpAddress which does not match Static Subnet: $($GatewayIPObject.CIDR)!`nEiter change IpAddress or redefine SubNet in -GatewayIpAddress Parameter of 'Install-WslHandler' or 'Set-WslNetworkParameters' commands!" -ErrorAction Stop
        }
    }
}

function Get-WslIpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter()][ValidateRange(1, 254)]
        [int]$DefaultOffset = 1,

        [switch]$ForceReadFileFromDisk
    )
    $Section = (Get-WslIpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    $offset = $DefaultOffset
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: Initial Section Content: $($Section | Out-String)"
    if ($Section.Contains($WslInstanceName)) {
        $offset = [int]($Section[$WslInstanceName])
        Write-Debug "${fn}: Got Existing Offset for ${WslInstanceName}: '$offset'"
    }
    else {
        switch ($Section.Count) {
            0 { $offset = $DefaultOffset }
            1 { $offset = [int]($Section.Values | Select-Object -First 1) + 1 }
            Default {
                $offset = (
                    [int]($Section.Values | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)
                ) + 1
            }
        }
        Write-Debug "${fn}: Generated New IP Offset: '$offset' for ${WslInstanceName}"
        # Set-WslIpOffset $WslInstanceName $local:offset
    }
    Write-Output $offset
}

function Set-WslIpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter(Mandatory)][ValidateRange(1, 254)]
        [int]$IpOffset,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk,

        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name

    $Section = (Get-WslIpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    Write-Debug "${fn}: for $WslInstanceName to: $IpOffset."
    Write-Debug "${fn}: Initial Section Content: $($Section | Out-String)"

    if ($IpOffset -in $Section.Values) {
        Write-Debug "${fn}: Found that offset: $IpOffset is already in use."
        $usedIPOwner = ($Section.GetEnumerator() |
                Where-Object { [int]$_.Value -eq $IpOffset } |
                Select-Object -ExpandProperty Name)
        if ($usedIPOwner -ne $WslInstanceName) {
            Write-Error "IP Offset: $IpOffset is already used by: $usedIPOwner" -ErrorAction Stop
        }
        return
    }

    if ([string]${Section}[$WslInstanceName] -ne [string]$IpOffset) {
        ${Section}[$WslInstanceName] = [string]$IpOffset
        $Modified.Value = $true
    }
    Write-Debug "${fn}: Final Section Content: $($Section | Out-String)"
}

function Write-WslConfig {
    [CmdletBinding()]
    param(
        [switch]$Backup
    )
    if ($Backup) {
        $newName = Get-Date -Format 'yyyy.MM.dd-HH.mm.ss'
        $oldName = Split-Path -Leaf $WslConfigPath
        $folder = Split-Path -Parent $WslConfigPath
        $newPath = Join-Path $folder ($newName + $oldName)
        Copy-Item -Path $WslConfigPath -Destination $newPath -Force
    }
    $local:name = $MyInvocation.MyCommand.Name
    Write-Debug "$name current to write: $(Get-WslConfig | ConvertTo-Json)"
    Write-Debug "$name target path: $WslConfigPath"
    Out-IniFile -FilePath $WslConfigPath -InputObject (Get-WslConfig) -Force -Loose -Pretty
}
