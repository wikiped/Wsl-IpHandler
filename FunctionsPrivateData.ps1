#region Helper Functions to work with PrivateData hashtable from Module's PSD1 file.

$WslPrivateData = $null

function Get-PrivateData {
    [CmdletBinding()]
    param($ModuleInfo, [switch]$Force)


    if ($null -eq $script:WslPrivateData -or $Force) {
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: PrivateData is null or -Force parameter has been set!"

        if ($PSBoundParameters.ContainsKey('ModuleInfo') -and $null -ne $ModuleInfo) {
            $ModuleInfo = [System.Management.Automation.PSModuleInfo]$ModuleInfo
            Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Using passed in ModuleInfo: $($ModuleInfo.Name)"
        }
        else {
            $ModuleInfo = $MyInvocation.MyCommand.Module
            Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Using `$MyInvocation.MyCommand.Module: $($ModuleInfo.Name)"
        }

        if ($null -eq $ModuleInfo.PrivateData) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                ([System.ArgumentNullException]"ModuleInfo in ${fn} does not have PrivateData!"),
                    'WSLIpHandler.PrivateDataNotFound',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $ModuleInfo
                )
            )
        }
        else {
            $script:WslPrivateData = $ModuleInfo.PrivateData.Clone()
            Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Cloned PrivateData - Count: $($script:WslPrivateData.Count)"
            $script:WslPrivateData.Remove('PSData')
            Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: PsData removed from PrivateData"
            $script:WslPrivateData
        }
    }
    else {
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Returning Cached PrivateData: $($script:WslPrivateData | Out-String)"
        $script:WslPrivateData
    }
}

function Get-ScriptName {
    [CmdletBinding()]
    param($ScriptName, $ModuleInfo)
    $local:ScriptNames = (Get-PrivateData $ModuleInfo)['ScriptNames']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptNames.Keys | Out-String)"
    $local:ScriptNames.Contains($ScriptName) ? $local:ScriptNames[$ScriptName] : (Write-Error $errorMessage -ErrorAction Stop)
}

function Get-ScriptLocation {
    [CmdletBinding()]
    param($ScriptName, $ModuleInfo)
    $local:ScriptLocations = (Get-PrivateData $ModuleInfo)['ScriptLocations']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptLocations.Keys | Out-String)"
    $local:ScriptLocations.Contains($ScriptName) ? $local:ScriptLocations[$ScriptName] : (Write-Error $errorMessage -ErrorAction Stop)
}

function Get-SourcePath {
    [CmdletBinding()]
    param($ScriptName)
    Join-Path $PSScriptRoot (Get-ScriptName $ScriptName) -Resolve
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

function Get-WslIpOffsetSectionName {
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

function Get-ProfileContent {
    [CmdletBinding()]
    param($ModuleInfo)
    (Get-PrivateData $ModuleInfo).ProfileContent
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
