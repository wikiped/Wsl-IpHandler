$script:WslConfig = $null
$script:WslIpHandlerConfig = $null

#region Imports
# . (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve) | Out-Null

if (-not ('ConfigType' -as [Type])) {
    . (Join-Path $PSScriptRoot 'Enums.ps1' -Resolve) | Out-Null
}

if (-not (Test-Path function:/Get-NetworkSectionName)) {
    . (Join-Path $PSScriptRoot 'FunctionsPrivateData.ps1' -Resolve) | Out-Null
}

if (-not (Test-Path function:/Read-IniFile)) {
    . (Join-Path $PSScriptRoot 'Ini-In.ps1' -Resolve) | Out-Null
}

if (-not (Test-Path function:/Write-IniFile)) {
    . (Join-Path $PSScriptRoot 'Ini-Out.ps1' -Resolve) | Out-Null
}

if (-not (Test-Path function:/Test-IsValidIpAddress)) {
    Import-Module (Join-Path $PSScriptRoot '..\..\SubModules\IPNetwork.psm1' -Resolve) -Verbose:$false -Debug:$false
}
#endregion Imports

#region Debug Functions
if (!(Test-Path function:/_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

#region Config Paths Getters
function Get-WslConfigPath {
    param(
        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [switch]$Resolve
    )
    Write-Debug "$(_@) ConfigType: $ConfigType"
    switch ($ConfigType.ToString()) {
        'Wsl' { Join-Path $HOME '.wslconfig' -Resolve:$Resolve }
        'WslIpHandler' { Join-Path $HOME '.wsl-iphandler-config' -Resolve:$Resolve }
    }
}

function Get-WslConfigCacheVariable {
    param(
        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler
    )
    Write-Debug "$(_@) ConfigType: $ConfigType"
    switch ($ConfigType.ToString()) {
        'Wsl' { Get-Variable 'WslConfig' -Scope Script }
        'WslIpHandler' { Get-Variable 'WslIpHandlerConfig' -Scope Script }
    }
}
#endregion Config Paths Getters

#region WSL Config Reader Writer
function Read-ConfigFile {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSVariable]$CacheVariable,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) BoundParameters: $(& { $args } @PSBoundParameters)"
    Write-Debug "$(_@) Current Cached Config: $($CacheVariable.Value | Out-String)"

    if (($null -eq $CacheVariable.Value) -or $ForceReadFileFromDisk) {
        if (Test-Path $ConfigPath -PathType Leaf) {
            try {
                Write-Debug "$(_@) Loading config from: $ConfigPath"
                $CacheVariable.Value = Read-IniFile $ConfigPath -Verbose:$false -Debug:$false
                Write-Debug "$(_@) Loaded config: $($CacheVariable.Value | Out-String)"
            }
            catch {
                Write-Error "$(_@) Error reading ConfigPath: '$ConfigPath':" -ErrorAction 'Continue'
                Throw
                # Write-Debug "$(_@) Error reading: '$ConfigPath'. Returning empty Dictionary"
                # $CacheVariable.Value = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        else {
            Write-Debug "$(_@) Config file not found: '$ConfigPath'. Returning empty Dictionary"
            $CacheVariable.Value = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
        }
    }
    else { Write-Debug "$(_@) Returning Cached Config: $($CacheVariable.Value | Out-String)" }
    $CacheVariable.Value
}

function Read-WslConfig {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ConfigType]$ConfigType,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) PSBoundParameters: $(& { $args } @PSBoundParameters)"

    $configPath = Get-WslConfigPath $ConfigType
    Write-Debug "$(_@) configPath: $configPath"

    $cacheVar = Get-WslConfigCacheVariable -ConfigType $ConfigType
    Write-Debug "$(_@) Cache variable: $($cacheVar.Name)"
    Read-ConfigFile -ConfigPath $configPath -CacheVariable $cacheVar -Force:$ForceReadFileFromDisk
}

function Write-WslConfig {
    param(
        [Parameter(Mandatory)]
        [ConfigType]$ConfigType,

        [Parameter()]
        [System.Collections.Specialized.OrderedDictionary]$Config,

        [Parameter()]
        [switch]$Backup
    )
    Write-Debug "$(_@) BoundParameters: $(& { $args } @PSBoundParameters)"

    $configPath = Get-WslConfigPath -ConfigType $ConfigType

    if ($null -eq $Config) {
        Write-Debug "$(_@) No Config passed. Invoke: Read-WslConfig -ConfigType $ConfigType"
        $Config = Read-WslConfig -ConfigType $ConfigType
    }

    if ($Backup) { Backup-WslConfigFile -ConfigType $ConfigType }

    Write-Debug "$(_@) Config path: $configPath"
    Write-Debug "$(_@) Config to write: $($Config | ConvertTo-Json)"

    $outIniParams = @{
        FilePath            = $configPath
        InputObject         = $Config
        Force               = $true
        Loose               = $true
        Pretty              = $true
        IgnoreEmptySections = $true
    }

    Write-Debug "$(_@) Invoking Write-IniFile $(& { $args } @outIniParams)"
    Write-IniFile @outIniParams
}

function Backup-WslConfigFile {
    param(
        [Parameter(Mandatory)]
        [ConfigType]$ConfigType
    )
    $configPath = Get-WslConfigPath -ConfigType $ConfigType

    if (-not (Test-Path $configPath -PathType Leaf)) {
        Write-Debug "$(_@) File not found: '$configPath'. Nothing to backup."
        return
    }
    $newName = Get-Date -Format 'yyyy.MM.dd-HH.mm.ss'
    $oldName = Split-Path -Leaf $configPath
    $folder = Split-Path -Parent $configPath
    $newPath = Join-Path $folder ($newName + $oldName)
    $msg = "Backing up '$configPath' to '$newPath'..."
    Write-Verbose "$msg"
    Write-Debug "$(_@) $msg"
    Copy-Item -Path $configPath -Destination $newPath -Force
}

function Remove-ModuleConfigFile {
    param([Parameter()][switch]$Backup)
    $type = [ConfigType]::WslIpHandler
    $filepath = Get-WslConfigPath -ConfigType $type
    if (Test-Path $filepath -PathType Leaf) {
        if ($Backup) { Backup-WslConfigFile -ConfigType $type }
        Remove-Item $filepath -Force
    }
}
#endregion WSL Config Reader Writer

#region Config File Checkers
function Test-WslConfigIsSafeToDelete {
    param(
        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [switch]$ExcludeNetworkSection
    )
    $modType = [ConfigType]::WslIpHandler
    $networkSectionCount = $ExcludeNetworkSection ? 0 : (Get-WslConfigSectionCount -SectionName (Get-NetworkSectionName -ConfigType $ConfigType) -ConfigType $ConfigType)
    $staticIpSectionCount = Get-WslConfigSectionCount -SectionName (Get-StaticIpAddressesSectionName -ConfigType $modType) -ConfigType $ConfigType
    $ipOffsetSectionCount = Get-WslConfigSectionCount -SectionName (Get-IpOffsetSectionName -ConfigType $modType) -ConfigType $ConfigType
    if ($ConfigType -eq $modType) {
        $networkSectionCount -eq 0 -and $staticIpSectionCount -eq 0 -and $ipOffsetSectionCount -eq 0
    }
    else {
        $staticIpSectionCount -eq 0 -and $ipOffsetSectionCount -eq 0
    }
}
#endregion Config File Checkers

#region Generic Section Getter and Helpers
function Test-WslConfigSectionExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) SectionName = [$SectionName]"
    Write-Debug "$(_@) ConfigType: $ConfigType"
    $config = Read-WslConfig -ConfigType $ConfigType -Force:$ForceReadFileFromDisk

    $output = $config.Contains($SectionName)
    Write-Debug "$(_@) Section [$SectionName] exists: $output"
    $output
}

function Get-WslConfigSection {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) SectionName = '$SectionName'"
    Write-Debug "$(_@) ConfigType: $ConfigType"
    $config = Read-WslConfig -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk

    if (-not (Test-WslConfigSectionExists $SectionName -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk)) {
        $value = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
        if ($ReadOnly) {
            Write-Debug "$(_@) ReadOnly is True, return empty section: [$SectionName]"
            return $value
        }
        else {
            Write-Debug "$(_@) Created Empty Section: [$SectionName]"
            $config[$SectionName] = $value
        }
    }
    else {
        Write-Debug "$(_@) Return existing section: [$SectionName]"
    }
    $config[$SectionName]
}

function Get-WslConfigSectionCount {
    [OutputType([int])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) SectionName = '$SectionName'"
    Write-Debug "$(_@) ConfigType: $ConfigType"

    Get-WslConfigSection $SectionName -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk -ReadOnly | Select-Object -ExpandProperty Count
}

function Remove-WslConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][AllowEmptyCollection()][AllowNull()]
        [string[]]$SectionName,

        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [switch]$OnlyIfEmpty,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $array = @($input)
    if ($array.Count) { $SectionName = $array }
    if (!(Test-Path Variable:SectionName)) { $SectionName = @() }
    if ($null -eq $SectionName) { $SectionName = @() }
    $config = Read-WslConfig -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "$(_@) Input `$Modified = $($Modified.Value ?? '$null')"

    $SectionName | ForEach-Object {
        if ($config.Contains($_)) {
            if ($OnlyIfEmpty -and ($config[$_].Count -eq 0)) {
                Write-Debug "$(_@) Section [$_] is empty and OnlyIfEmpty = `$true"
                $config.Remove($_)
                if ($null -ne $Modified) { $Modified.Value = $true }
                Write-Debug "$(_@) Conditionally Removed Empty Section '$_'."
            }
            else {
                $config.Remove($_)
                if ($null -ne $Modified) { $Modified.Value = $true }
                Write-Debug "$(_@) Unconditionally Removed Section '$_'."
            }
        }
    }
    if ($null -ne $Modified) { Write-Debug "$(_@) Output Modified: $($Modified.Value)" }
}
#endregion Generic Section Getter and Helpers

#region Generic Value Getter Setter
function Get-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ConfigType]$ConfigType,

        [Parameter()]
        [object]$DefaultValue,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if (Test-WslConfigSectionExists -SectionName $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk) {
        $section = Get-WslConfigSection $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk -ReadOnly:$ReadOnly
        if ($section.Contains($KeyName)) {
            Write-Debug "$(_@) Value of '$KeyName' in Section [$SectionName]: $($section[$KeyName])"
            $output = $section[$KeyName]
        }
        else {
            Write-Debug "$(_@) Section [$SectionName] has no key: '$KeyName'!"
            if ($PSBoundParameters.ContainsKey('DefaultValue')) {
                if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
                    Write-Debug "$(_@) Returning `$DefaultValue: '$DefaultValue' without modifying the section: [$SectionName]"
                    $output = $DefaultValue
                }
                else {
                    if ($ReadOnly) {
                        Write-Debug "$(_@) ReadOnly is True returning DefaultValue: '$DefaultValue'"
                        $output = $DefaultValue
                    }
                    else {
                        Write-Debug "$(_@) DefaultValue '$DefaultValue' will be assigned to '$KeyName'"
                        $section[$KeyName] = $output = $DefaultValue
                        if ($null -ne $Modified) { $Modified.Value = $true }
                    }
                }
            }
            else {
                Write-Error "$(_@) Section [$SectionName] has no key: '$KeyName' and no DefaultValue is given!" -ErrorAction Stop
            }
        }
    }
    else {
        Write-Debug "$(_@) Section [$SectionName] does not exist!"
        if ($PSBoundParameters.ContainsKey('DefaultValue')) {
            if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
                Write-Debug "$(_@) Returning `$DefaultValue: '$DefaultValue' without modifying the section: [$SectionName]"
                $output = $DefaultValue
            }
            else {
                if ($ReadOnly) {
                    Write-Debug "$(_@) ReadOnly is True returning DefaultValue: '$DefaultValue'"
                    $output = $DefaultValue
                }
                else {
                    Write-Debug "$(_@) Create empty section [$SectionName]"
                    $section = Get-WslConfigSection $SectionName -ConfigType $ConfigType -ReadOnly:$ReadOnly
                    Write-Debug "$(_@) DefaultValue '$DefaultValue' will be assigned to '$KeyName'"
                    $section[$KeyName] = $output = $DefaultValue
                    if ($null -ne $Modified) { $Modified.Value = $true }

                }
            }
        }
        else {
            Write-Error "$(_@) Section [$SectionName] does not exist and no DefaultValue is given!" -ErrorAction Stop
        }
    }
    if ($null -ne $Modified) { Write-Debug "$(_@) Final Modified: $($Modified.Value)" }
    Write-Debug "$(_@) Output: $output"
    $output
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
        [ValidateNotNull()]
        [ConfigType]$ConfigType,

        [Parameter()]
        [ref]$Modified,

        [switch]$UniqueValue,

        [switch]$RemoveOtherKeyWithUniqueValue,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    if ($null -ne $Modified) { Write-Debug "$(_@) Input Modified: $($Modified.Value)" }

    # Setting $null or '' does not make sense in .wslconfig context
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Debug "$(_@) Ignoring `$Value of `$null or WhiteSpace. If the intention was to remove the value - use Remove-WslConfigValue command."
        return
    }
    $section = Get-WslConfigSection $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk
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
                if ($null -ne $Modified) { $Modified.Value = $true }
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
        if ($null -ne $Modified) { $Modified.Value = $true }
    }
    Write-Debug "$(_@) Final Section Content: $($section | Out-String)"
    if ($null -ne $Modified) { Write-Debug "$(_@) Output Modified: $($Modified.Value)" }
}

function Remove-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ConfigType]$ConfigType,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    if ($null -ne $Modified) { Write-Debug "$(_@) Initial Modified = $($Modified.Value)" }

    # Test if section exists first to avoid creating non-existing section when we get it
    if (Test-WslConfigSectionExists -SectionName $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk) {
        $section = Get-WslConfigSection $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk
        Write-Debug "$(_@) Initial Section Content: $($section | Out-String)"
        if (${section}.Contains($KeyName)) {
            Write-Debug "$(_@) Section Contains Key: $KeyName. Removing it."
            ${section}.Remove($KeyName)
            if ($null -ne $Modified) {
                $Modified.Value = $true
            }
            $params = @{
                SectionName = $SectionName
                ConfigType  = $ConfigType
                OnlyIfEmpty = $true
            }
            if ($null -ne $Modified) { $params.Modified = $Modified }
            Remove-WslConfigSection @params
        }
        Write-Debug "$(_@) Final Section Content: $($section | Out-String)"
    }
    else {
        Write-Debug "$(_@) Section [$SectionName] does not exists - nothing to remove"
    }
    if ($null -ne $Modified) { Write-Debug "$(_@) Final Modified = '$($Modified.Value)'" }

}
#endregion Generic Value Getter Setter

#region Static IP Address Getter Setter Helpers
function Test-IsValidStaticIpAddress {
    [CmdletBinding(DefaultParameterSetName = 'Automatic')]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Automatic')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Manual')]
        [ValidateNotNull()]
        [ipaddress]$IpAddress,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Manual')]
        [ipaddress]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Manual')]
        [int]$PrefixLength = 24,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if ($PSCmdlet.ParameterSetName -eq 'Automatic') {
        $warnMsg = "You are setting Static IP Address: $IpAddress "

        $GatewayIpAddress = Get-WslConfigGatewayIpAddress -ReadOnly

        $usingWslConfig = $null -ne $GatewayIpAddress

        $PrefixLength = Get-WslConfigValue (Get-NetworkSectionName -ConfigType $ConfigType) (Get-PrefixLengthKeyName -ConfigType $ConfigType) -ConfigType $ConfigType -DefaultValue $PrefixLength -ReadOnly

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
            $GatewayIpObject = (Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength)
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
        $GatewayIPObject = (Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength)
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

function Get-WslConfigStaticIpSection {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()][ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()][switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $sectionName = Get-StaticIpAddressesSectionName -ConfigType $ConfigType
    Get-WslConfigSection -SectionName $sectionName -ConfigType $ConfigType -ReadOnly:$ReadOnly
}

function Get-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $sectionName = Get-StaticIpAddressesSectionName -ConfigType $ConfigType
    $existingIp = Get-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -ConfigType $ConfigType -DefaultValue $null
    [ipaddress]$existingIp
}

function Set-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [Alias('IpAddress')]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [ipaddress]$WslInstanceIpAddress,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName = Get-StaticIpAddressesSectionName -ConfigType $ConfigType
        KeyName     = $WslInstanceName
        Value       = $WslInstanceIpAddress.IPAddressToString
        ConfigType  = $ConfigType
        UniqueValue = $true
    }
    if ($null -ne $Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigStaticIpAddress {
    [OutputType([ipaddress])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName = Get-StaticIpAddressesSectionName -ConfigType $ConfigType
        KeyName     = $WslInstanceName
        ConfigType  = $ConfigType
    }
    if ($null -ne $Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}

function Get-WslConfigAvailableStaticIpAddress {
    [OutputType([ipaddress])]
    param(
        [Parameter()]
        [ipaddress]$GatewayIpAddress,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $GatewayIpAddress ??= Get-WslConfigGatewayIpAddress -ConfigType $ConfigType
    $PrefixLength = (Get-WslConfigPrefixLength -ConfigType $ConfigType) ?? 24

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

        $SectionName = Get-StaticIpAddressesSectionName -ConfigType $ConfigType

        if ((Get-WslConfigSectionCount $SectionName) -gt 0) {
            $section = Get-WslConfigSection -SectionName $SectionName -ConfigType $ConfigType -ReadOnly
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
    param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    if ([string]::IsNullOrWhiteSpace($SectionName)) { $SectionName = Get-IpOffsetSectionName -ConfigType $ConfigType }
    Write-Debug "$(_@) `$SectionName: '$SectionName'"

    Get-WslConfigSection -SectionName $SectionName -ConfigType $ConfigType -Force:$ForceReadFileFromDisk -ReadOnly:$ReadOnly
}

function Get-WslConfigIpOffset {
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $Section = (Get-WslConfigIpOffsetSection -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk)

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

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $Section = (Get-WslConfigIpOffsetSection -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk)
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

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [switch]$BackupWslConfig
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $Section = (Get-WslConfigIpOffsetSection -ConfigType $ConfigType -ForceReadFileFromDisk:$ForceReadFileFromDisk)
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
        if ($null -ne $Modified) { $Modified.Value = $true }
    }
    Write-Debug "$(_@) Final Section Content: $($Section | Out-String)"
}

function Remove-WslConfigIpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-IpOffsetSectionName -ConfigType $ConfigType
        KeyName               = $WslInstanceName
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion IP Offset Getter Setter Helper

#region Windows Host Name Getter Setter
function Get-WslConfigWindowsHostName {
    [OutputType([string])]
    param(
        [Parameter()]
        [object]$DefaultValue = $null,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-WindowsHostNameKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        DefaultValue          = [string]::IsNullOrWhiteSpace($DefaultValue) ? $null : $DefaultValue.ToString()
        ForceReadFileFromDisk = $ForceReadFileFromDisk
        ReadOnly              = $ReadOnly
    }
    if ($Modified) { $params.Modified = $Modified }
    Get-WslConfigValue @params
}

function Set-WslConfigWindowsHostName {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-WindowsHostNameKeyName -ConfigType $ConfigType
        Value                 = $Value
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigWindowsHostName {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-WindowsHostNameKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion Windows Host Name Getter Setter

#region Gateway IP Address Getter Setter
function Get-WslConfigGatewayIpAddress {
    [OutputType([ipaddress])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-GatewayIpAddressKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        DefaultValue          = $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
        ReadOnly              = $ReadOnly
    }
    if ($null -ne $Modified) { $params.Modified = $Modified }
    [ipaddress](Get-WslConfigValue @params)
}

function Set-WslConfigGatewayIpAddress {
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [ipaddress]$Value,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-GatewayIpAddressKeyName -ConfigType $ConfigType
        Value                 = $Value.IPAddressToString
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($null -ne $Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigGatewayIpAddress {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-GatewayIpAddressKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($null -ne $Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
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
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-PrefixLengthKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        DefaultValue          = $DefaultValue
        ForceReadFileFromDisk = $ForceReadFileFromDisk
        ReadOnly              = $ReadOnly
    }
    if ($Modified) { $params.Modified = $Modified }
    $value = Get-WslConfigValue @params
    if ($value) { [int]$value }
    else { $null -eq $DefaultValue ? $null : [int]$DefaultValue }
}

function Set-WslConfigPrefixLength {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ValidateRange(0, 32)]
        [int]$Value,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-PrefixLengthKeyName -ConfigType $ConfigType
        Value                 = $Value
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigPrefixLength {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-PrefixLengthKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion PrefixLength Getter Setter

#region DNS Servers Getter Setter
function Get-WslConfigDnsServers {
    [OutputType([string[]])]
    param(
        [Parameter()]
        [object]$DefaultValue = @(),

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DnsServersKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        DefaultValue          = $DefaultValue ? $DefaultValue : $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
        ReadOnly              = $ReadOnly
    }
    if ($Modified) { $params.Modified = $Modified }
    $value = Get-WslConfigValue @params
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

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    switch ($Value) {
        { $_ -is [string] } { $array = $Value -split ',' }
        { $_ -is [array] } { $array = $Value }
        Default { Throw "Unexpected Type: $_ in $($MyInvocation.MyCommand.Name). Expected Types: {String | Array}" }
    }
    $stringValue = $array -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$' -join ', '
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DnsServersKeyName -ConfigType $ConfigType
        Value                 = $stringValue
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigDnsServers {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DnsServersKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion DNS Servers Getter Setter

#region Dynamic Adapters Getter Setter
function Get-WslConfigDynamicAdapters {
    [OutputType([string[]])]
    param(
        [Parameter()]
        [object]$DefaultValue = @(),

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk,

        [Parameter()]
        [switch]$ReadOnly
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DynamicAdaptersKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        DefaultValue          = $DefaultValue ? $DefaultValue : $null
        ForceReadFileFromDisk = $ForceReadFileFromDisk
        ReadOnly              = $ReadOnly
    }
    if ($Modified) { $params.Modified = $Modified }
    $value = Get-WslConfigValue @params
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

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    switch ($Value) {
        { $_ -is [string] } { $array = $Value -split ',' }
        { $_ -is [array] } { $array = $Value }
        Default { Throw "Unexpected Type: $_ in $($MyInvocation.MyCommand.Name). Expected Types: {String | Array}" }
    }
    $stringValue = $array -replace '^\s+' -replace '\s+$' -replace "^\s*'\s*" -replace '^\s*"\s*' -replace "\s*'\s*$" -replace '\s*"\s*$' -join ', '
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DynamicAdaptersKeyName -ConfigType $ConfigType
        Value                 = $stringValue
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigDynamicAdapters {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::WslIpHandler,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-DynamicAdaptersKeyName -ConfigType $ConfigType
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion Dynamic Adapters Getter Setter

#region SwapSize Getter Setter
function Get-WslConfigSwapSize {
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$DefaultValue,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-GlobalSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapSizeKeyName
        ConfigType            = $ConfigType
        DefaultValue          = $DefaultValue
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Get-WslConfigValue @params
}

function Set-WslConfigSwapSize {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-GlobalSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapSizeKeyName
        Value                 = $Value
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigSwapSize {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-IpOffsetSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapSizeKeyName
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion SwapSize Getter Setter

#region SwapFile Getter Setter
function Get-WslConfigSwapFile {
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$DefaultValue,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [switch]$ExpandEnvironmentVariables,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-GlobalSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapFileKeyName
        ConfigType            = $ConfigType
        DefaultValue          = $DefaultValue
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    $value = Get-WslConfigValue @params
    if ($ExpandEnvironmentVariables) {
        $ExecutionContext.InvokeCommand.ExpandString(($value -replace '%([^=\s]+)%', '${env:$1}'))
    }
    else { $value }
}

function Set-WslConfigSwapFile {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [object]$Value,

        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapFileKeyName
        Value                 = $Value
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Set-WslConfigValue @params
}

function Remove-WslConfigSwapFile {
    param(
        [Parameter()]
        [ValidateNotNull()]
        [ConfigType]$ConfigType = [ConfigType]::Wsl,

        [Parameter()]
        [ref]$Modified,

        [Parameter()]
        [Alias('Force')]
        [switch]$ForceReadFileFromDisk
    )
    $params = @{
        SectionName           = Get-NetworkSectionName -ConfigType $ConfigType
        KeyName               = Get-SwapFileKeyName
        ConfigType            = $ConfigType
        ForceReadFileFromDisk = $ForceReadFileFromDisk
    }
    if ($Modified) { $params.Modified = $Modified }
    Remove-WslConfigValue @params
}
#endregion SwapFile Getter Setter
