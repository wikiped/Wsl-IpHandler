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

function Get-ModuleInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Management.Automation.PSModuleInfo]
        $ModuleInfo,

        [Parameter()]
        [switch]$Throw
    )
    if ($null -eq $ModuleInfo) {
        $ModuleInfo = $MyInvocation.MyCommand.Module
        Write-Debug "$(_@) Using `$MyInvocation.MyCommand.Module.Name: $($ModuleInfo.Name)"
    }
    else {
        $ModuleInfo = [System.Management.Automation.PSModuleInfo]$ModuleInfo
        Write-Debug "$(_@) Using passed in ModuleInfo from Module: $($ModuleInfo.Name)"
    }
    if ($null -eq $ModuleInfo -and $Throw) { Throw 'ModuleInfo is not available!' }
    else { $ModuleInfo }
}

function Get-PrivateData {
    param([Parameter()][switch]$Force)
    if ($Force -or $null -eq $script:WslPrivateData) {
        Write-Debug "$(_@) `$WslPrivateData is null or -Force parameter has been set!"
        $ModuleInfo = Get-ModuleInfo
        Write-Debug "$(_@) `$ModuleInfo: $($ModuleInfo | Out-String)"
        $errorMessage = $null
        if ($null -eq $ModuleInfo) {
            $modulePsdFile = Join-Path $PSScriptRoot '..\..\Wsl-IpHandler.psd1' -Resolve
            Write-Debug "$(_@) `$modulePsdFile: $($modulePsdFile | Out-String)"
            $modulePsd = Import-Psd $modulePsdFile -ErrorAction Stop
            $privateData = $modulePsd | Select-Object -ExpandProperty PrivateData -ErrorAction Ignore
            if ($null -eq $privateData) {
                $errorMessage = "$($MyInvocation.MyCommand.Name) Could not find PrivateData in file: '$modulePsdFile'"
                $errorObject = $modulePsd
            }
        }
        else {
            $privateData = $ModuleInfo | Select-Object -ExpandProperty PrivateData -ErrorAction Ignore
            if ($null -eq $privateData) {
                $errorMessage = "$($MyInvocation.MyCommand.Name) Could not find PrivateData in Module: '$($ModuleInfo.Name)'"
                $errorObject = $ModuleInfo
            }
        }
        if ($errorMessage) {
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

function Get-ScriptName {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )
    $local:ScriptNames = (Get-PrivateData)['ScriptNames']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptNames.Keys | Out-String)"
    $local:ScriptNames.Contains($ScriptName) ? $local:ScriptNames[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-ScriptLocation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptName)
    $local:ScriptLocations = (Get-PrivateData)['ScriptLocations']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptLocations.Keys | Out-String)"
    $local:ScriptLocations.Contains($ScriptName) ? $local:ScriptLocations[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-SourcePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptName)
    $moduleInfo = Get-ModuleInfo -Throw
    Join-Path $moduleInfo.ModuleBase (Get-ScriptName $ScriptName) -Resolve
}

function Get-TargetPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptName)
    $targetLocation = Get-ScriptLocation -ScriptName $ScriptName
    "$targetLocation/$(Get-ScriptName -ScriptName $ScriptName)"
}

function Get-GlobalSectionName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.GlobalSectionName
}

function Get-NetworkSectionName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.NetworkSectionName
}

function Get-StaticIpAddressesSectionName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.StaticIpAddressesSectionName
}

function Get-IpOffsetSectionName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.IpOffsetSectionName
}

function Get-SwapSizeKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.SwapSizeKeyName
}

function Get-SwapFileKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.SwapFileKeyName
}

function Get-GatewayIpAddressKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.GatewayIpAddressKeyName
}

function Get-PrefixLengthKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.PrefixLengthKeyName
}

function Get-DnsServersKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.DnsServersKeyName
}

function Get-WindowsHostNameKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.WindowsHostNameKeyName
}

function Get-DynamicAdaptersKeyName {
    [CmdletBinding()]param()
    (Get-PrivateData).WslConfig.DynamicAdaptersKeyName
}

function Get-ProfileContentTemplate {
    [CmdletBinding()]param()
    $content = (Get-PrivateData).ProfileContent
    $modulePath = (Get-ModuleInfo -Throw).ModuleBase
    Write-Debug "$(_@) modulePath: $modulePath"

    # If module was not installed in a standard location replace module name with module's path
    $paths = $Env:PSModulePath -split ';'
    $onPath = $false
    foreach ($path in $paths) { if ($modulePath.Contains($path)) { $onPath = $true; break } }
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

function Get-ScheduledTaskName {
    [CmdletBinding()]param()
    (Get-PrivateData).ScheduledTask.TaskName
}

function Get-ScheduledTaskName {
    [CmdletBinding()]param()
    (Get-PrivateData).ScheduledTask.Name
}

function Get-ScheduledTaskPath {
    [CmdletBinding()]param()
    (Get-PrivateData).ScheduledTask.Path
}

function Get-ScheduledTaskDescription {
    [CmdletBinding()]param()
    (Get-PrivateData).ScheduledTask.Description
}

#endregion Helper Functions
