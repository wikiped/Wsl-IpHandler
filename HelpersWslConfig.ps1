$WslConfigPath = Join-Path $HOME '.wslconfig'
$WslConfig = $null

$script:NoSection = '_'  # Variable Required by Get-IniContent.ps1 and Out-IniFile.ps1
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

function Get-WslConfigSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $name = $MyInvocation.MyCommand.Name
    $config = Get-WslConfig -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${name}: `$SectionName = '$SectionName'"

    if (-not $config.ContainsKey($SectionName)) {
        Write-Debug "${name}: Section '$SectionName' not found in Wsl Config. Empty Section Created!"
        $config[$SectionName] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
    }
    $config[$SectionName]
}

function Get-WslConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$KeyName,

        [Parameter()]
        [object]$DefaultValue = $null,

        [switch]$ForceReadFileFromDisk
    )
    $name = $MyInvocation.MyCommand.Name
    Write-Debug "${name}: `$SectionName = '$SectionName'"
    Write-Debug "${name}: `$KeyName = '$KeyName'"
    Write-Debug "${name}: `$DefaultValue = '$DefaultValue'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk

    if (-not $section.ContainsKey($KeyName)) {
        Write-Debug "${name}: Section '$SectionName' has no key: '$KeyName'!"
        if ($null -ne $DefaultValue) {
            Write-Debug "${name}: DefaultValue '$DefaultValue' will be assigned to '$KeyName'"
            $section[$KeyName] = $DefaultValue
        }
        else {
            Write-Error "${name}: Section '$SectionName' has no key: '$KeyName' and DefaultValue is `$null!" -ErrorAction Stop
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

        [switch]$UniqueValue,

        [switch]$ForceReadFileFromDisk,

        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$SectionName = '$SectionName'"
    Write-Debug "${fn}: `$KeyName = '$KeyName'"
    Write-Debug "${fn}: `$Value = '$Value'"

    $section = Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
    Write-Debug "${fn}: Initial Section Content: $($section | Out-String)"

    if ($UniqueValue) {
        if ($Value -in $section.Values) {
            Write-Debug "${fn}: with `$UniqueValue=$UniqueValue found existing value: '$Value'"
            $usedOwner = ($Section.GetEnumerator() |
                    Where-Object { $_.Value -eq $Value } |
                    Select-Object -ExpandProperty Name)
            if ($usedOwner -ne $KeyName) {
                Write-Error "${fn}: Value: '$Value' is already used by: $usedOwner" -ErrorAction Stop
            }
            return
        }
    }
    ${section}[$KeyName] = $Value

    Write-Debug "${fn}: '$KeyName' = '$Value'"
    Write-Debug "${fn}: Final Section Content: $($section | Out-String)"

    Write-WslConfig -Backup:$BackupWslConfig
}

function Get-IpOffsetSection {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$SectionName,

        [switch]$ForceReadFileFromDisk
    )
    $name = $MyInvocation.MyCommand.Name

    if ([string]::IsNullOrWhiteSpace($SectionName)) { $SectionName = (Get-IpOffsetSectionName) }
    Write-Debug "${name}: `$SectionName: '$SectionName'"

    Get-WslConfigSection $SectionName -ForceReadFileFromDisk:$ForceReadFileFromDisk
}

function Get-IpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter()][ValidateRange(1, 254)]
        [int]$DefaultOffset = 1,

        [switch]$ForceReadFileFromDisk
    )
    $Section = (Get-IpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    $offset = $DefaultOffset
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "$fn Initial Section Content: $($Section | Out-String)"
    if ($Section.ContainsKey($WslInstanceName)) {
        $offset = [int]($Section[$WslInstanceName])
        Write-Debug "$fn Got Existing Offset for ${WslInstanceName}: '$offset'"
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
        Write-Debug "$fn Generated New IP Offset: '$offset' for ${WslInstanceName}"
        # Set-IpOffset $WslInstanceName $local:offset
    }
    Write-Output $offset
}

function Set-IpOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName,

        [Parameter(Mandatory)][ValidateRange(1, 254)]
        [int]$IpOffset,

        [switch]$ForceReadFileFromDisk,

        [switch]$BackupWslConfig
    )
    $name = $MyInvocation.MyCommand.Name
    $Section = (Get-IpOffsetSection -ForceReadFileFromDisk:$ForceReadFileFromDisk)
    Write-Debug "$Name for $WslInstanceName to: $IpOffset."
    Write-Debug "$Name Initial Section Content: $($Section | Out-String)"
    if ($IpOffset -in $Section.Values) {
        Write-Debug "$name Found that offset: $IpOffset is already in use."
        $usedIPOwner = ($Section.GetEnumerator() |
                Where-Object { [int]$_.Value -eq $IpOffset } |
                Select-Object -ExpandProperty Name)
        if ($usedIPOwner -ne $WslInstanceName) {
            Write-Error "IP Offset: $IpOffset is already used by: $usedIPOwner" -ErrorAction Stop
        }
        return
    }
    ${Section}[$WslInstanceName] = [string]$IpOffset
    Write-Debug "$name Final Section Content: $($Section | Out-String)"
    Write-WslConfig -Backup:$BackupWslConfig
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
