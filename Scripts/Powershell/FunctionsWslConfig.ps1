$WslConfig = $null

Set-Variable NoSection '_'  # Variable Required by Get-IniContent.ps1 and Out-IniFile.ps1
. (Join-Path $PSScriptRoot 'Get-IniContent.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'Out-IniFile.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'FunctionsPrivateData.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve) | Out-Null

$IPNetworkModuleName = 'IPNetwork'
Import-Module (Join-Path $PSScriptRoot "..\..\SubModules\$IPNetworkModuleName.psm1" -Resolve) -Function Test-IsValidIpAddress, Get-IpNet | Out-Null

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

#region WSL Config Getter Writer
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
    if (($null -eq $script:WslConfig) -or $ForceReadFileFromDisk) {
        if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
            try {
                $ConfigPath = (Get-WslConfigPath -Resolve)
                Write-Debug "$(_@) Loading config from: $ConfigPath"
                $script:WslConfig = Get-IniContent $ConfigPath -Verbose:$false -Debug:$false
            }
            catch {
                Write-Debug "$(_@) No ConfigPath specified. Return empty Dictionary."
                $script:WslConfig = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        else {
            Write-Debug "$(_@) Loading config from: $ConfigPath"
            $script:WslConfig = Get-IniContent $ConfigPath -Verbose:$false -Debug:$false
        }
    }
    Write-Debug "$(_@) Returning Cached Config..."
    $WslConfig
}

function Write-WslConfig {
    [CmdletBinding()]
    param(
        [switch]$Backup
    )
    $configPath = Get-WslConfigPath

    if ($Backup) {
        $newName = Get-Date -Format 'yyyy.MM.dd-HH.mm.ss'
        $oldName = Split-Path -Leaf $configPath
        $folder = Split-Path -Parent $configPath
        $newPath = Join-Path $folder ($newName + $oldName)
        Copy-Item -Path $configPath -Destination $newPath -Force
    }

    $config = Get-WslConfig
    Write-Debug "$(_@) current config to write: $($config | ConvertTo-Json)"
    Write-Debug "$(_@) target path: $configPath"

    $emptySections = $config.Keys | Where-Object { $config.$_.Count -eq 0 }
    Write-Debug "$(_@) Empty Sections: $emptySections"

    $__ = $false
    $emptySections | Remove-WslConfigSection -Modified ([ref]$__) -OnlyIfEmpty:$true

    $outIniParams = @{
        FilePath    = $configPath
        InputObject = $config
        Force       = $true
        Loose       = $true
        Pretty      = $true
    }

    Write-Debug "$(_@) Invoking Out-IniFile with Parameters:`n$($outIniParams | Out-String)"
    Out-IniFile @outIniParams
}
#endregion WSL Config Getter Writer

#region Section Getter and Helpers
function Test-WslConfigSectionExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "$(_@) `$SectionName = '$SectionName'"

    if ($config.Contains($SectionName)) {
        Write-Debug "$(_@) Section '$SectionName' Exists!"
        $true
    }
    else {
        Write-Debug "$(_@) Section '$SectionName' Does NOT Exist!"
        $false
    }
}

function Get-WslConfigSection {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$SectionName = '$SectionName'"
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk

    if (-not (Test-WslConfigSectionExists $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk)) {
        Write-Debug "$(_@) Empty Section '$SectionName' Created!"
        $config[$SectionName] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
    }
    $config[$SectionName]
}

function Get-WslConfigSectionCount {
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$SectionName = '$SectionName'"

    if (Test-WslConfigSectionExists $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk) {
        (Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk).Count
    }
    else {
        -1
    }
}

function Remove-WslConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyCollection()][AllowNull()]
        [string[]]$SectionName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$OnlyIfEmpty,

        [switch]$ForceReadFileFromDisk
    )

    $array = @($input)
    if ($array.Count) { $SectionName = $array }
    if (!(Test-Path Variable:SectionName)) { $SectionName = @() }
    if ($null -eq $SectionName) { $SectionName = @() }
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "$(_@) `$SectionName = '$SectionName'"
    Write-Debug "$(_@) `$OnlyIfEmpty = $OnlyIfEmpty"
    Write-Debug "$(_@) `$Modified = $($Modified.Value)"
    Write-Debug "$(_@) `$ForceReadFileFromDisk = $ForceReadFileFromDisk"

    $SectionName | ForEach-Object {
        if ($config.Contains($_)) {
            if ($OnlyIfEmpty) {
                Write-Debug "$(_@) Only Remove Empty Section is specified."
                if ($config[$_].Count -eq 0) {
                    $config.Remove($_)
                    $Modified.Value = $true
                    Write-Debug "$(_@) Conditionally Removed Empty Section '$_'."
                }
            }
            else {
                $config.Remove($_)
                $Modified.Value = $true
                Write-Debug "$(_@) Unconditionally Removed Section '$_'."
            }
        }
    }
}
#endregion Section Getter and Helpers

#region Generic Value Getter Setter
function Get-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter()]
        [object]$DefaultValue,

        [Parameter()]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$SectionName = '$SectionName'"
    Write-Debug "$(_@) `$KeyName = '$KeyName'"
    Write-Debug "$(_@) `$DefaultValue = '$DefaultValue'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk

    if (-not $section.Contains($KeyName)) {
        Write-Debug "$(_@) Section '$SectionName' has no key: '$KeyName'!"
        if ($PSBoundParameters.ContainsKey('DefaultValue')) {
            if ($null -eq $DefaultValue) {
                Write-Debug "$(_@) Returning specified DefaultValue = `$null"
                return $DefaultValue
            }
            else {
                Write-Debug "$(_@) DefaultValue '$DefaultValue' will be assigned to '$KeyName'"
                $section[$KeyName] = $DefaultValue
                if ($PSBoundParameters.ContainsKey('Modified') -and $null -ne $Modified) {
                    Write-Debug "$(_@) Setting `$Modified to `$true"
                    $Modified.Value = $true
                }
            }
        }
        else {
            Write-Error "$(_@) Section '$SectionName' has no key: '$KeyName' and no DefaultValue is given!" -ErrorAction Stop
        }
    }
    Write-Debug "$(_@) Value of '$KeyName' in Section '$SectionName': $($section[$KeyName])"
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
    Write-Debug "$(_@) `$SectionName = '$SectionName'"
    Write-Debug "$(_@) `$KeyName = '$KeyName'"
    Write-Debug "$(_@) `$Value = '$Value'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "$(_@) Initial Section Content: $($section | Out-String)"

    if ($UniqueValue -and $Value -in $section.Values) {
        Write-Debug "$(_@) `$UniqueValue=$UniqueValue and value: '$Value' already exists."
        $usedOwner = ($Section.GetEnumerator() |
                Where-Object { $_.Value -eq $Value } |
                Select-Object -ExpandProperty Name)

        Write-Debug "$(_@) Value: '$Value' is already set to: $usedOwner"
        if ($usedOwner -eq $KeyName) {
            return
        }
        else {
            if ($RemoveOtherKeyWithUniqueValue) {
                Write-Debug "$(_@) Removing existing key: $usedOwner"
                ${section}.Remove($usedOwner)
                ${section}[$KeyName] = $Value
                Write-Debug "$(_@) Setting `$Modified to `$true"
                $Modified.Value = $true
            }
            else {
                Write-Error "$($MyInvocation.MyCommand.Name) Value: '$Value' is NOT Unique as it is already used by: $usedOwner" -ErrorAction Stop
            }
        }
    }

    if (${section}[$KeyName] -ne $Value) {
        Write-Debug "$(_@) Changing Value of '$KeyName':"
        Write-Debug "$(_@) From: '$(${section}[$KeyName])'"
        Write-Debug "$(_@) Of Type: '$(if ($null -ne ${section}[$KeyName]) {(${section}[$KeyName]).GetType()})'"
        Write-Debug "$(_@) To: '$Value'"
        Write-Debug "$(_@) Of Type: '$(if ($null -ne $Value) {$Value.GetType()})'"
        ${section}[$KeyName] = $Value
        Write-Debug "$(_@) Setting `$Modified to `$true"
        $Modified.Value = $true
    }
    Write-Debug "$(_@) Final Section Content: $($section | Out-String)"
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

    Write-Debug "$(_@) `$SectionName = '$SectionName''
    Write-Debug '$($MyInvocation.MyCommand.Name) `$KeyName = '$KeyName''
    Write-Debug '$($MyInvocation.MyCommand.Name) `$Modified = '$($Modified.Value)'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "$(_@) Initial Section Content: $($section | Out-String)"

    if (${section}.Contains($KeyName)) {
        Write-Debug "$(_@) Section Contains Key: $KeyName. Removing it."
        ${section}.Remove($KeyName)
        $Modified.Value = $true
        Write-Debug "$(_@) Set `$Modified = '$($Modified.Value)'"
        Remove-WslConfigSection $SectionName -OnlyIfEmpty:$true -Modified $Modified
    }
    Write-Debug "$(_@) Final Section Content: $($section | Out-String)'
    Write-Debug '$($MyInvocation.MyCommand.Name) Final `$Modified = '$($Modified.Value)'"
}
#endregion Generic Value Getter Setter

#region Static IP Address Getter Setter Helpers
function Test-IsValidStaticIpAddress {
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

    Write-Debug "$(_@) `$IpAddress=$IpAddress of type: $($IpAddress.Gettype())"

    if ($PSCmdlet.ParameterSetName -eq 'Automatic') {
        $warnMsg = "You are setting Static IP Address: $IpAddress "

        $GatewayIpAddress = Get-WslConfigGatewayIpAddress

        $usingWslConfig = $null -ne $GatewayIpAddress

        $PrefixLength = Get-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) -DefaultValue $PrefixLength

        if ($null -eq $GatewayIpAddress) {
            $MSFT_NetIPAddress = Get-NetIPAddress -InterfaceAlias $vEthernetWsl -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $GatewayIpAddress = [ipaddress]$MSFT_NetIPAddress.IPv4Address
            $PrefixLength = $MSFT_NetIPAddress.PrefixLength
        }

        Write-Debug "$(_@) `$GatewayIpAddress=$GatewayIpAddress of type: $($GatewayIpAddress.Gettype())"

        Write-Debug "$(_@) `$PrefixLength=$PrefixLength"

        if ($null -eq $GatewayIpAddress) {
            $warnMsg += 'within currently Unknown WSL SubNet that will be set by Windows OS and might have different SubNet!'
        }
        else {
            $GatewayIpObject = (Get-IpNet -IpAddress $GatewayIpAddress.IPAddressToString -PrefixLength $PrefixLength)
            if ($GatewayIpObject.Contains($IpAddress)) {
                Write-Debug "$(_@) $IpAddress is within $($GatewayIpObject.CIDR) when `$usingWslConfig=$usingWslConfig"
                if ($usingWslConfig) {
                    $true
                }
                else {
                    $warnMsg += "within the WSL SubNet: $($GatewayIpObject.CIDR), but which is set by Windows OS and might change after system restarts!"
                }
            }
            else {
                Write-Debug "$(_@) $IpAddress is NOT within $($GatewayIpObject.CIDR) when `$usingWslConfig=$usingWslConfig"
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
        Write-Debug "$(_@) `$GatewayIpAddress=$GatewayIpAddress of type: $($GatewayIpAddress.Gettype())"
        Write-Debug "$(_@) `$PrefixLength=$PrefixLength"
        $GatewayIPObject = (Get-IpNet -IpAddress $GatewayIpAddress.IPAddressToString -PrefixLength $PrefixLength)
        Write-Debug "$(_@) `$GatewayIPObject: $($GatewayIPObject | Out-String)"
        if ($GatewayIPObject.Contains($IpAddress)) {
            Write-Debug "$(_@) $IpAddress is VALID and is within $($GatewayIPObject.CIDR) SubNet."
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

function Get-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName
    )
    $sectionName = Get-StaticIpAddressesSectionName
    $existingIp = Get-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -DefaultValue $null
    [ipaddress]$existingIp
}

function Get-WslConfigStaticIpSection {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param()
    $sectionName = Get-StaticIpAddressesSectionName
    Get-WslConfigSection -SectionName $sectionName
}

function Set-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Alias('IpAddress')]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [ipaddress]$WslInstanceIpAddress,

        [ref]$Modified
    )
    $sectionName = Get-StaticIpAddressesSectionName
    Set-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -Value $WslInstanceIpAddress.IPAddressToString -Modified $Modified -UniqueValue
}

function Remove-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [ref]$Modified
    )
    $sectionName = Get-StaticIpAddressesSectionName
    Remove-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -Modified $Modified
}

function Get-WslConfigAvailableStaticIpAddress {
    [OutputType([ipaddress])]
    param(
        [Parameter()]
        [ipaddress]$GatewayIpAddress
    )
    $GatewayIpAddress ??= Get-WslConfigGatewayIpAddress
    $PrefixLength = (Get-WslConfigPrefixLength) ?? 24

    if ($null -eq $GatewayIpAddress) {
        Write-Debug "$(_@) GatewayIpAddress was not specified and is not configured in .wslconfig -> Trying System WSL adapter."
        $wslIpObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias $vEthernetWsl -ErrorAction SilentlyContinue
        if ($null -eq $wslIpObj) {
            Throw "$($MyInvocation.MyCommand.Name) Cannot proceed when GatewayIpAddress parameter is neither specified, nor found in .wslconfig and no existing WSL adapter to take it from."
        }
        else {
            $GatewayIpAddress = $wslIpObj.IPAddress
            $PrefixLength = $wslIpObj.PrefixLength
        }
    }
    else {
        Write-Debug "$(_@) `$GatewayIpAddress=$GatewayIpAddress"
        Write-Debug "$(_@) `$PrefixLength=$PrefixLength"

        $SectionName = (Get-StaticIpAddressesSectionName)

        if ((Get-WslConfigSectionCount $SectionName) -gt 0) {
            $section = Get-WslConfigSection -SectionName $SectionName
            Write-Debug "$(_@) Count of Static IP addresses section: $($section.Count)."
            Write-Debug "$(_@) Selecting available IP address for WSL GatewayIpAddress: $GatewayIpAddress."

            $ipObj = Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            foreach ($i in (1..$ipObj.IPcount)) {
                $_ip = $ipObj.Add($i).IpAddress
                if ($_ip -notin $section.Values) {
                    $newIP = [ipaddress]($_ip)
                    break
                }
            }
        }
        else {
            $ipObj = Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            $newIP = $ipObj.Add(1).IpAddress
        }

        if ($null -eq $newIP) {
            Throw "$(_@) could not find available IP Address with GatewayIpAddress: $GatewayIpAddress and PrefixLength: $PrefixLength"
        }
        Write-Debug "$(_@) Returning IP: $newIP"
        [ipaddress]$newIP
    }
}
#endregion Static IP Address Getter Setter Helpers

#region IP Offset Getter Setter Helper
function Get-WslConfigIpOffsetSection {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    if ([string]::IsNullOrWhiteSpace($SectionName)) { $SectionName = (Get-IpOffsetSectionName) }
    Write-Debug "$(_@) `$SectionName: '$SectionName'"

    Get-WslConfigSection -SectionName $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
}

function Get-WslConfigIpOffset {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $Section = (Get-WslConfigIpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)

    if ($Section.Contains($WslInstanceName)) {
        $offset = [int]($Section[$WslInstanceName])
        Write-Debug "$(_@) Found IP Offset for ${WslInstanceName}: '$offset'"
        $offset
    }
    else {
        Write-Debug "$(_@) IP Offset not found for ${WslInstanceName}"
        $null
    }
}

function Get-WslConfigAvailableIpOffset {
    [OutputType()]
    param(
        [Parameter()][ValidateRange(1, 254)]
        [int]$DefaultOffset = 1,

        [switch]$ForceReadFileFromDisk
    )
    $Section = (Get-WslConfigIpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    Write-Debug "$(_@) Initial Section Content: $($Section | Out-String)"

    switch ($Section.Count) {
        0 { $offset = $DefaultOffset }
        1 { $offset = [int]($Section.Values | Select-Object -First 1) + 1 }
        Default {
            $offset = (
                [int]($Section.Values | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)
            ) + 1
        }
    }
    Write-Debug "$(_@) Returning IP Offset: '$offset'"
    [int]$offset
}

function Set-WslConfigIpOffset {
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
    $Section = (Get-WslConfigIpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    Write-Debug "$(_@) for $WslInstanceName to: $IpOffset."
    Write-Debug "$(_@) Initial Section Content: $($Section | Out-String)"

    if ($IpOffset -in $Section.Values) {
        Write-Debug "$(_@) Found that offset: $IpOffset is already in use."
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
    Write-Debug "$(_@) Final Section Content: $($Section | Out-String)"
}

function Remove-WslConfigIpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk,

        [switch]$BackupWslConfig
    )
    Write-Debug "$(_@) `$WslInstanceName: $WslInstanceName."
    $sectionName = Get-IpOffsetSectionName
    Remove-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -Modified $Modified
}
#endregion IP Offset Getter Setter Helper

#region Windows Host Name Getter Setter
function Get-WslConfigWindowsHostName {
    [OutputType([string])]
    param(
        [Parameter()]
        [object]$DefaultValue = $null,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $getParams = @{
        SectionName           = Get-NetworkSectionName
        KeyName               = Get-WindowsHostNameKeyName
        DefaultValue          = [string]::IsNullOrWhiteSpace($DefaultValue) ? $null : $DefaultValue.ToString()
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $getParams.Modified = $Modified }
    Get-WslConfigValue @getParams
}

function Set-WslConfigWindowsHostName {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    Set-WslConfigValue (Get-NetworkSectionName) (Get-WindowsHostNameKeyName) $Value -Modified $Modified
}

function Remove-WslConfigWindowsHostName {
    param(
        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-WindowsHostNameKeyName) -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}
#endregion Windows Host Name Getter Setter

#region Gateway IP Address Getter Setter
function Get-WslConfigGatewayIpAddress {
    [OutputType([ipaddress])]
    param(
        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-NetworkSectionName
        KeyName               = Get-GatewayIpAddressKeyName
        DefaultValue          = $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    [ipaddress](Get-WslConfigValue @params)
}

function Set-WslConfigGatewayIpAddress {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ipaddress]$Value,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    Set-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) $Value.IPAddressToString -Modified $Modified
}

function Remove-WslConfigGatewayIpAddress {
    param(
        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}
#endregion Gateway IP Address Getter Setter

#region PrefixLength Getter Setter
function Get-WslConfigPrefixLength {
    [OutputType([int])]
    param(
        [Parameter()]
        [ValidateScript({ ($null -eq $null) -or ([int]$_ -in 0..32) })]
        [object]$DefaultValue = $null,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $getParams = @{
        SectionName           = Get-NetworkSectionName
        KeyName               = Get-PrefixLengthKeyName
        DefaultValue          = $DefaultValue
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $getParams.Modified = $Modified }
    $value = Get-WslConfigValue @getParams
    if ($value) { [int]$value }
    else { $DefaultValue }
}

function Set-WslConfigPrefixLength {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ValidateRange(0, 32)]
        [int]$Value,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    Set-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) $Value -Modified $Modified
}

function Remove-WslConfigPrefixLength {
    param(
        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}
#endregion PrefixLength Getter Setter

#region DNS Servers Getter Setter
function Get-WslConfigDnsServers {
    [OutputType([string[]])]
    param(
        [Parameter()]
        [object]$DefaultValue = @(),

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $getParams = @{
        SectionName           = Get-NetworkSectionName
        KeyName               = Get-DnsServersKeyName
        DefaultValue          = $DefaultValue ? $DefaultValue : $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $getParams.Modified = $Modified }
    $value = Get-WslConfigValue @getParams
    if ($value) {
        $value -split ',' -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$'
    }
    else {
        $DefaultValue
    }
}

function Set-WslConfigDnsServers {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    switch ($Value) {
        { $_ -is [string] } { $array = $Value -split ',' }
        { $_ -is [array] } { $array = $Value }
        Default { Throw "Unexpected Type: $_ in $($MyInvocation.MyCommand.Name). Expected Types: {String | Array}" }
    }
    $stringValue = $array -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$' -join ', '
    Set-WslConfigValue (Get-NetworkSectionName) (Get-DnsServersKeyName) $stringValue -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}

function Remove-WslConfigDnsServers {
    param(
        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-DnsServersKeyName) -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}
#endregion DNS Servers Getter Setter

#region Dynamic Adapters Getter Setter
function Get-WslConfigDynamicAdapters {
    [OutputType([string[]])]
    param(
        [Parameter()]
        [object]$DefaultValue = @(),

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ForceReadFileFromDisk
    )
    $getParams = @{
        SectionName           = Get-NetworkSectionName
        KeyName               = Get-DynamicAdaptersKeyName
        DefaultValue          = $DefaultValue ? $DefaultValue : $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $getParams.Modified = $Modified }
    $value = Get-WslConfigValue @getParams
    if ($value) {
        $value -split ',' -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$'
    }
    else {
        $DefaultValue
    }
}

function Set-WslConfigDynamicAdapters {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [object]$Value,

        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    switch ($Value) {
        { $_ -is [string] } { $array = $Value -split ',' }
        { $_ -is [array] } { $array = $Value }
        Default { Throw "Unexpected Type: $_ in $($MyInvocation.MyCommand.Name). Expected Types: {String | Array}" }
    }
    $stringValue = $array -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$' -join ', '
    Set-WslConfigValue (Get-NetworkSectionName) (Get-DynamicAdaptersKeyName) $stringValue -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}

function Remove-WslConfigDynamicAdapters {
    param(
        [Parameter(Mandatory)]
        [ref]$Modified,

        [switch]$ForceReadFileFromDisk
    )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-DynamicAdaptersKeyName) -Modified $Modified -ForceReadFileFromDisk:$ForceReadFileFromDisk
}
#endregion Dynamic Adapters Getter Setter
