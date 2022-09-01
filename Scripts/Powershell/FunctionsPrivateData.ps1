#region Helper Functions to work with PrivateData hashtable from Module's PSD1 file.

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

$WslPrivateData = $null

#region Imports
if (-not ('ConfigType' -as [Type])) {
    . (Join-Path $PSScriptRoot 'Enums.ps1' -Resolve) | Out-Null
}
#endregion Imports

#region PrivateData Getter
function Get-ModuleInfo {
    [CmdletBinding()]
    param()
    $ModuleInfo = $MyInvocation.MyCommand.Module
    if ($null -eq $ModuleInfo) {
        Write-Debug "$(_@) `$MyInvocation has no Module: $($MyInvocation | Out-String)"
        Throw "$(Split-Path $MyInvocation.ScriptName -Leaf) has no ModuleInfo!"
    }
    else {
        Write-Debug "$(_@) `$MyInvocation.MyCommand.Module.Name: $($ModuleInfo.Name)"
        $ModuleInfo
    }
}

function Get-ModulePath {
    [CmdletBinding()]
    param()
    try {
        Get-ModuleInfo | Select-Object -ExpandProperty ModuleBase -ErrorAction Stop
    }
    catch {
        $PSScriptRoot | Split-Path | Split-Path
    }
}

function Get-PrivateData {
    param([Parameter()][switch]$Force)
    if ($Force -or $null -eq $script:WslPrivateData) {
        Write-Debug "$(_@) `$WslPrivateData is null or -Force parameter has been set!"
        $errorMessage = $null
        try {
            $ModuleInfo = Get-ModuleInfo
            $privateData = $ModuleInfo | Select-Object -ExpandProperty PrivateData -ErrorAction Ignore
            $errorMessage = "$($MyInvocation.MyCommand.Name) Could not find PrivateData in Module"
            $errorObject = $MyInvocation
        }
        catch {
            Write-Debug "$(_@) Error getting ModuleInfo: $($_.Exception.Message)"
            $modulePath = Get-ModulePath
            $modulePsdFile = Join-Path $modulePath "$(Split-Path $modulePath -Leaf).psd1" -Resolve
            Write-Debug "$(_@) `$modulePsdFile: $($modulePsdFile | Out-String)"
            $modulePsd = Import-LocalizedData -BaseDirectory $modulePath -FileName (Split-Path $modulePath -Leaf) -ErrorAction Stop
            Write-Debug "$(_@) `$modulePsd: $($modulePsd | Out-String)"
            $privateData = $modulePsd | Select-Object -ExpandProperty PrivateData -ErrorAction Ignore
            $errorMessage = "$($MyInvocation.MyCommand.Name) Could not find PrivateData in file: '$modulePsdFile'"
            $errorObject = $modulePsd
        }
        if ($null -eq $privateData) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    ([System.ArgumentNullException]$errorMessage),
                    'WSLIpHandler.PrivateDataNotFound',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $errorObject
                )
            )
        }
        else {
            $script:WslPrivateData = $privateData.Clone()
            Write-Debug "$(_@) Cloned PrivateData - Count: $($script:WslPrivateData.Count)"
            $script:WslPrivateData.Remove('PSData')
            Write-Debug "$(_@) PsData removed from WslPrivateData"
            $script:WslPrivateData
            Write-Debug "$(_@) Returning New WslPrivateData: $($script:WslPrivateData | Out-String)"
        }
    }
    else {
        Write-Debug "$(_@) Returning Cached WslPrivateData.Count: $($script:WslPrivateData.Count)"
        $script:WslPrivateData
    }
}
#endregion PrivateData Getter

#region Files Names and Paths
function Get-ScriptName {
    param([Parameter(Mandatory)][string]$ScriptName)
    $ScriptNames = Get-PrivateData | Select-Object -ExpandProperty ScriptNames -ErrorAction Stop
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptNames.Keys | Out-String)"
    $ScriptNames.Contains($ScriptName) ? $ScriptNames[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-ScriptLocation {
    param([Parameter(Mandatory)][string]$ScriptName)
    $ScriptLocations = Get-PrivateData | Select-Object -ExpandProperty ScriptLocations -ErrorAction Stop
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptLocations.Keys | Out-String)"
    $ScriptLocations.Contains($ScriptName) ? $ScriptLocations[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-SourcePath {
    param([Parameter(Mandatory)][string]$ScriptName)
    Join-Path (Get-ModulePath) (Get-ScriptName $ScriptName) -Resolve
}

function Get-TargetPath {
    param([Parameter(Mandatory)][string]$ScriptName)
    $targetLocation = Get-ScriptLocation -ScriptName $ScriptName
    "$targetLocation/$(Get-ScriptName -ScriptName $ScriptName | Split-Path -Leaf)"
}
#endregion Files Names and Paths

#region Common Accessors
function Get-SectionFromPrivateData {
    [CmdletBinding(DefaultParameterSetName = 'ConfigType')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ConfigType')]
        [ConfigType]$ConfigType,

        [Parameter(Mandatory, ParameterSetName = 'SectionName')]
        [string]$SectionName
    )
    if ($PSCmdlet.ParameterSetName -eq 'ConfigType') {
        $SectionName = switch ($ConfigType) {
            "$([ConfigType]::Wsl)" { 'WslConfig' }
            "$([ConfigType]::WslIpHandler)" { 'WslIpHandlerConfig' }
            Default {
                Write-Error "$_ is not one of supported ConfigTypes: $([ConfigType].GetEnumNames())"
            }
        }
    }
    Get-PrivateData | Select-Object -ExpandProperty $SectionName
}

function Get-GlobalSectionName {
    param([Parameter(Mandatory)][ConfigType]$ConfigType)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty GlobalSectionName
}

function Get-NetworkSectionName {
    param([Parameter(Mandatory)][ConfigType]$ConfigType)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty NetworkSectionName
}

function Get-BashConfigFilePath {
    param([Parameter()][ConfigType]$ConfigType)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty FilePath
}
#endregion Common Accessors

#region WslConfig Accessors
function Get-SwapSizeKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::Wsl)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty SwapSizeKeyName
}

function Get-SwapFileKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::Wsl)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty SwapFileKeyName
}
#endregion WslConfig Accessors

#region WslIpHandler Accessors
function Get-StaticIpAddressesSectionName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty StaticIpAddressesSectionName
}

function Get-IpOffsetSectionName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty IpOffsetSectionName
}

function Get-GatewayIpAddressKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty GatewayIpAddressKeyName
}

function Get-PrefixLengthKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty PrefixLengthKeyName
}

function Get-DnsServersKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty DnsServersKeyName
}

function Get-WindowsHostNameKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty WindowsHostNameKeyName
}

function Get-DynamicAdaptersKeyName {
    param([Parameter()][ConfigType]$ConfigType = [ConfigType]::WslIpHandler)
    Get-SectionFromPrivateData $ConfigType | Select-Object -ExpandProperty DynamicAdaptersKeyName
}

function Get-ProfileContentTemplate {
    [CmdletBinding()]param()
    $content = Get-SectionFromPrivateData -SectionName ProfileContent
    $modulePath = Get-ModulePath
    Write-Debug "$(_@) modulePath: $modulePath"

    # If module was not installed in a standard location replace module name with module's path
    $paths = $Env:PSModulePath -split ';'
    $onPath = $false
    foreach ($path in $paths) { if ($modulePath.ToLower().Contains($path.ToLower())) { $onPath = $true; break } }
    if (-not $onPath) {
        Write-Debug "$(_@) modulePath is not in: $($Env:PSModulePath)"
        $content = $content -replace 'Import-Module Wsl-IpHandler', "Import-Module '$modulePath'"
        Write-Debug "$(_@) handlerContent with modified path:`n$($content -join "`n")"
    }
    else {
        Write-Debug "$(_@) handlerContent:`n$($content -join "`n")"
    }
    $content
}

function Get-ScheduledTaskHashTable {
    [CmdletBinding()]param()
    Get-SectionFromPrivateData -SectionName ScheduledTask
}

function Get-ScheduledTaskName {
    [CmdletBinding()]param()
    Get-ScheduledTaskHashTable | Select-Object -ExpandProperty Name
}

function Get-ScheduledTaskPath {
    [CmdletBinding()]param()
    Get-ScheduledTaskHashTable | Select-Object -ExpandProperty Path
}

function Get-ScheduledTaskDescription {
    [CmdletBinding()]param()
    Get-ScheduledTaskHashTable | Select-Object -ExpandProperty Description
}
#endregion WslIpHandler Accessors

#endregion Helper Functions
