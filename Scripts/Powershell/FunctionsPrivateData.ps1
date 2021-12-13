#region Helper Functions to work with PrivateData hashtable from Module's PSD1 file.

$WslPrivateData = $null

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

function Get-ModuleInfo {
    [CmdletBinding()]
    param($ModuleInfo)
    if ($PSBoundParameters.ContainsKey('ModuleInfo') -and $null -ne $ModuleInfo) {
        $ModuleInfo = [System.Management.Automation.PSModuleInfo]$ModuleInfo
        Write-Debug "$(_@) Using passed in ModuleInfo from Module: $($ModuleInfo.Name)"
    }
    else {
        $ModuleInfo = $MyInvocation.MyCommand.Module
        Write-Debug "$(_@) Using `$MyInvocation.MyCommand.Module.Name: $($ModuleInfo.Name)"
    }
    $ModuleInfo
}

function Get-PrivateData {
    [CmdletBinding()]
    param($ModuleInfo, [switch]$Force)
    if ($null -eq $script:WslPrivateData -or $Force) {
        Write-Debug "$(_@) PrivateData is null or -Force parameter has been set!"

        $ModuleInfo = Get-ModuleInfo $ModuleInfo

        if ($null -eq $ModuleInfo.PrivateData) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                ([System.ArgumentNullException]"ModuleInfo in $($MyInvocation.MyCommand.Name) does not have PrivateData!"),
                    'WSLIpHandler.PrivateDataNotFound',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $ModuleInfo
                )
            )
        }
        else {
            $script:WslPrivateData = $ModuleInfo.PrivateData.Clone()
            Write-Debug "$(_@) Cloned PrivateData - Count: $($script:WslPrivateData.Count)"
            $script:WslPrivateData.Remove('PSData')
            Write-Debug "$(_@) PsData removed from PrivateData"
            $script:WslPrivateData
        }
    }
    else {
        Write-Debug "$(_@) Returning Cached PrivateData: $($script:WslPrivateData | Out-String)"
        $script:WslPrivateData
    }
}

function Get-ScriptName {
    [CmdletBinding()]
    param($ScriptName, $ModuleInfo)
    $local:ScriptNames = (Get-PrivateData $ModuleInfo)['ScriptNames']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptNames.Keys | Out-String)"
    $local:ScriptNames.Contains($ScriptName) ? $local:ScriptNames[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-ScriptLocation {
    [CmdletBinding()]
    param($ScriptName, $ModuleInfo)
    $local:ScriptLocations = (Get-PrivateData $ModuleInfo)['ScriptLocations']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptLocations.Keys | Out-String)"
    $local:ScriptLocations.Contains($ScriptName) ? $local:ScriptLocations[$ScriptName] : (Write-Error "$errorMessage" -ErrorAction Stop)
}

function Get-SourcePath {
    [CmdletBinding()]
    param($ScriptName)
    $moduleRoot = Split-Path $MyInvocation.MyCommand.Module.Path
    Join-Path $moduleRoot (Get-ScriptName $ScriptName) -Resolve
}

function Get-TargetPath {
    [CmdletBinding()]
    param($ScriptName)
    $targetLocation = Get-ScriptLocation $ScriptName
    "$targetLocation/$(Get-ScriptName $ScriptName)"
}

function Get-NetworkSectionName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.NetworkSectionName
}

function Get-StaticIpAddressesSectionName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.StaticIpAddressesSectionName
}

function Get-IpOffsetSectionName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.IpOffsetSectionName
}

function Get-GatewayIpAddressKeyName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.GatewayIpAddressKeyName
}

function Get-PrefixLengthKeyName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.PrefixLengthKeyName
}

function Get-DnsServersKeyName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.DnsServersKeyName
}

function Get-WindowsHostNameKeyName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.WindowsHostNameKeyName
}

function Get-DynamicAdaptersKeyName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).WslConfig.DynamicAdaptersKeyName
}

function Get-ProfileContent {
    [CmdletBinding()]
    param($ModuleInfo)
    $ModuleInfo = Get-ModuleInfo $ModuleInfo
    $content = (Get-PrivateData $ModuleInfo).ProfileContent
    $modulePath = $ModuleInfo.ModuleBase
    Write-Debug "$(_@) modulePath: $modulePath"

    # If module was not installed in a standard location replace module name with module's path
    if (-not ($Env:PSModulePath -split ';' -contains $modulePath)) {
        Write-Debug "$(_@) modulePath is not in: $($Env:PSModulePath)"
        $content = $content -replace 'Import-Module WSL-IpHandler', "Import-Module '$modulePath'"
        Write-Debug "$(_@) handlerContent with modified path:`n$($content -join "`n")"
    }
    else {
        Write-Debug "$(_@) handlerContent:`n$($content -join "`n")"
    }
    $content
}

function Get-ScheduledTaskName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).ScheduledTask.TaskName
}

function Get-ScheduledTaskName {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).ScheduledTask.Name
}

function Get-ScheduledTaskPath {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).ScheduledTask.Path
}

function Get-ScheduledTaskDescription {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).ScheduledTask.Description
}

#endregion Helper Functions
