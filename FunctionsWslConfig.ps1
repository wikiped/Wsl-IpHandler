$WslConfig = $null

Set-Variable NoSection '_'  # Variable Required by Get-IniContent.ps1 and Out-IniFile.ps1
. (Join-Path $PSScriptRoot 'Get-IniContent.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'Out-IniFile.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'FunctionsPrivateData.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve)

function Get-WslConfigPath {
    [CmdletBinding()]param([switch]$Resolve)
    Join-Path $HOME '.wslconfig' -Resolve:$Resolve
}

function Get-WslConfig {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][AllowNull()]
        [string]$ConfigPath,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name

    if (($null -eq $script:WslConfig) -or $ForceReadFileFromDisk) {
        if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            try {
                $ConfigPath = (Get-WslConfigPath -Resolve)
                Write-Debug "${fn}: Loading config from: $ConfigPath"
                $script:WslConfig = Get-IniContent $ConfigPath -Verbose:$false -Debug:$false
            }
            catch {
                Write-Debug "${fn}: No ConfigPath specified. Return empty hashtable."
                $script:WslConfig = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        else {
            Write-Debug "${fn}: Loading config from: $ConfigPath"
            $script:WslConfig = Get-IniContent $ConfigPath -Verbose:$false -Debug:$false
        }
    }
    Write-Debug "${fn}: Returning Cached Config..."
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
    Write-Debug "${fn}: `$SectionName = '$SectionName'"
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk

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
    Write-Debug "${fn}: `$OnlyIfEmpty = $OnlyIfEmpty"
    Write-Debug "${fn}: `$Modified = $($Modified.Value)"
    Write-Debug "${fn}: `$ForceReadFileFromDisk = $ForceReadFileFromDisk"

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

        [switch]$RemoveOtherKeyWithUniqueValue,

        [switch]$ForceReadFileFromDisk
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$SectionName = '$SectionName'"
    Write-Debug "${fn}: `$KeyName = '$KeyName'"
    Write-Debug "${fn}: `$Value = '$Value'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: Initial Section Content: $($section | Out-String)"

    if ($UniqueValue -and $Value -in $section.Values) {
        Write-Debug "${fn}: `$UniqueValue=$UniqueValue and value: '$Value' already exists."
        $usedOwner = ($Section.GetEnumerator() |
                Where-Object { $_.Value -eq $Value } |
                Select-Object -ExpandProperty Name)

        Write-Debug "${fn}: Value: '$Value' is already set to: $usedOwner"
        if ($usedOwner -eq $KeyName) {
            return
        }
        else {
            if ($RemoveOtherKeyWithUniqueValue) {
                Write-Debug "${fn}: Removing existing key: $usedOwner"
                ${section}.Remove($usedOwner)
                ${section}[$KeyName] = $Value
                $Modified.Value = $true
            }
            else {
                Write-Error "${fn}: Value: '$Value' is NOT Unique as it is already used by: $usedOwner" -ErrorAction Stop
            }
        }
    }

    if (${section}[$KeyName] -ne $Value) {
        Write-Debug "${fn}: Setting '$KeyName' = '$Value'"
        ${section}[$KeyName] = $Value
        $Modified.Value = $true
    }
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
    Write-Debug "${fn}: `$Modified = '$($Modified.Value)'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: Initial Section Content: $($section | Out-String)"

    if (${section}.Contains($KeyName)) {
        Write-Debug "${fn}: Section Contains Key: $KeyName. Removing it."
        ${section}.Remove($KeyName)
        $Modified.Value = $true
        Write-Debug "${fn}: Set `$Modified = '$($Modified.Value)'"
        Remove-WslConfigSection $SectionName -OnlyIfEmpty:$true -Modified $Modified
    }
    Write-Debug "${fn}: Final Section Content: $($section | Out-String)"
    Write-Debug "${fn}: Final `$Modified = '$($Modified.Value)'"
}

function Get-AvailableStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [ipaddress]$GatewayIpAddress,
        [switch]$RequireGatewayIpAddress
    )

    $fn = $MyInvocation.MyCommand.Name
    $GatewayIpAddress ??= Get-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) -DefaultValue $null
    $PrefixLength = Get-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) -DefaultValue 24

    if ($null -eq $GatewayIpAddress) {
        Write-Debug "${fn}: GatewayIpAddress was not specified and is not configured in .wslconfig -> Trying System WSL adapter."
        $wslIpObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'vEthernet (WSL)' -ErrorAction SilentlyContinue
        if (-not $null -eq $wslIpObj) {
            $GatewayIpAddress = $wslIpObj.IPAddress
            $PrefixLength = $wslIpObj.PrefixLength
        }
        else {
            if ($RequireGatewayIpAddress.IsPresent) {
                Throw "${fn}: Cannot proceed when GatewayIpAddress parameter is neither specified, nor found in .wslconfig and no existing WSL adapter to take it from."
            }
        }
    }

    Write-Debug "${fn}: `$GatewayIpAddress=$GatewayIpAddress"
    Write-Debug "${fn}: `$PrefixLength=$PrefixLength"

    $ipcalc = Join-Path $PSScriptRoot 'IP-Calc.ps1' -Resolve

    $SectionName = (Get-StaticIpAddressesSectionName)

    if ((Get-WslConfigSectionCount $SectionName) -gt 0) {
        $section = Get-WslConfigSection -SectionName $SectionName
        Write-Debug "${fn}: Count of Static IP addresses section: $($section.Count)."
        if ($null -eq $GatewayIpAddress) {
            Write-Warning 'Without Gateway IP address for WSL SubNet available Static IP address will be based on simple sorting algorithm, without any guaranties.'
            $maxIP = $section.Values | Get-IpAddressFromString |
                Sort-Object { $_.IPAddressToString -as [Version] } -Bottom 1

            Write-Debug "${fn}: Max IP address: $maxIP"
            $maxIPobj = & $ipcalc -IpAddress $maxIP -PrefixLength $PrefixLength
            $newIP = $maxIPobj.Add(1).IpAddress
        }
        else {
            Write-Debug "${fn}: Selecting available IP address for WSL GatewayIpAddress: $GatewayIpAddress."

            $ipObj = & $ipcalc -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            foreach ($i in 1..$ipObj.IPcount) {
                $_ip = $ipObj.Add($i).IpAddress
                if ($_ip -notin $section.Values) {
                    $newIP = [ipaddress]($_ip)
                    break
                }
            }

            # [ipaddress]($ipObj.GetIParray() | # .GetIParray() can be very long/expensive
            #         ForEach-Object { [ipaddress]$_ } |
            #         Where-Object {
            #             $i = $_.IPAddressToString
            #             ($i -notin $section.Values) -and ([version]$i -ne [version]$ipObj.IP)
            #         } |
            #         Select-Object -First 1
            # )
        }
    }
    else {
        if ($null -eq $GatewayIpAddress) {
            Write-Warning 'Cannot Find available IP address without Gateway IP address for WSL SubNet and without any Static IP addresses in .wslconfig.'
            Write-Error "GatewayIpAddress in ${fn} is `$null and not found in .wslconfig and no WSL Network Adapter!"
        }
        else {
            $ipObj = & $ipcalc -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            $newIP = $ipObj.Add(1).IpAddress
        }
    }

    if ($null -eq $newIP) {
        Throw "${fn} could not find available IP Address with GatewayIpAddress: $GatewayIpAddress and PrefixLength: $PrefixLength"
    }

    Write-Debug "${fn}: Returning IP: $newIP"
    [ipaddress]$newIP
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
        [Parameter(Mandatory)][ValidateNotNull()]
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
            $warnMsg += 'within currently Unknown WSL SubNet that will be set by Windows OS and might have different SubNet!'
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
            Write-Debug "${fn}: $IpAddress is VALID and is within $($GatewayIPObject.CIDR) SubNet."
            $true
        }
        else {
            Write-Warning "You are setting Static IP Address: $IpAddress which does not match Static Subnet: $($GatewayIPObject.CIDR)!`nEither change IpAddress or redefine SubNet in -GatewayIpAddress Parameter of 'Install-WslHandler' or 'Set-WslNetworkParameters' commands!"
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("$IpAddress is NOT Valid as it is outside of $($GatewayIPObject.CIDR) SubNet.", 'IpAddress'),
                    'WSLIpHandler.StaticIpAddressValidationError',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $IpAddress
                )
            )
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
    $fn = $MyInvocation.MyCommand.Name
    $configPath = Get-WslConfigPath

    if ($Backup) {
        $newName = Get-Date -Format 'yyyy.MM.dd-HH.mm.ss'
        $oldName = Split-Path -Leaf $configPath
        $folder = Split-Path -Parent $configPath
        $newPath = Join-Path $folder ($newName + $oldName)
        Copy-Item -Path $configPath -Destination $newPath -Force
    }
    Write-Debug "${fn}: current config to write: $(Get-WslConfig | ConvertTo-Json)"
    Write-Debug "${fn}: target path: $configPath"
    $outIniParams = @{
        FilePath    = $configPath
        InputObject = (Get-WslConfig)
        Force       = $true
        Loose       = $true
        Pretty      = $true
    }

    Write-Debug "${fn}: Invoking Out-IniFile with Parameters:`n$($outIniParams | Out-String)"
    Out-IniFile @outIniParams
}
