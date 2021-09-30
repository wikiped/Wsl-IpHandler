﻿#region Helper Functions to work with PrivateData hashtable from Module's PSD1 file.

$script:PrivateData = $null

function Get-PrivateData {
    [CmdletBinding()]
    param()
    $fn = $MyInvocation.MyCommand.Name

    if ($null -eq $script:PrivateData) {
        Write-Debug "${fn}: PrivateData does not exist!"
        try {
            $script:PrivateData = $MyInvocation.MyCommand.Module.PrivateData.Clone()
        }
        catch {
            # Write-Host "MyInvocation: $($MyInvocation | Out-String)"
            Write-Error "${fn}: MyInvocation: $($MyInvocation | Out-String)`nError Cloning PrivateData: $($_.Exception.Message | Out-String)"
        }
        Write-Debug "${fn}: Cloned PrivateData - Count: $($script:PrivateData.Count)"
        $script:PrivateData.Remove('PSData')
        Write-Debug "${fn}: PsData removed from PrivateData"
    }
    Write-Debug "${fn}: Returning PrivateData: $($script:PrivateData | Out-String)"
    $script:PrivateData
}

function Get-ScriptName {
    [CmdletBinding()]
    param($ScriptName)
    $local:ScriptNames = (Get-PrivateData)['ScriptNames']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptNames.Keys | Out-String)"
    $local:ScriptNames.Contains($ScriptName) ? `
        $local:ScriptNames[$ScriptName] : (Write-Error $errorMessage -ErrorAction Stop)
}

function Get-ScriptLocation {
    [CmdletBinding()]
    param($ScriptName)
    $local:ScriptLocations = (Get-PrivateData)['ScriptLocations']
    $errorMessage = "Wrong ScriptName: '$ScriptName'. Valid names:`n$($ScriptLocations.Keys | Out-String)"
    $local:ScriptLocations.Contains($ScriptName) ? `
        $local:ScriptLocations[$ScriptName] : (Write-Error $errorMessage -ErrorAction Stop)
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
    param()
    (Get-PrivateData).WslConfig.NetworkSectionName
}

function Get-StaticIpAddressesSectionName {
    [CmdletBinding()]
    param()
    (Get-PrivateData).WslConfig.StaticIpAddressesSectionName
}

function Get-WslIpOffsetSectionName {
    [CmdletBinding()]
    param()
    (Get-PrivateData).WslConfig.IpOffsetSectionName
}

function Get-GatewayIpAddressKeyName {
    [CmdletBinding()]
    param()
    (Get-PrivateData).WslConfig.GatewayIpAddressKeyName
}

function Get-PrefixLengthKeyName {
    [CmdletBinding()]
    param()
    (Get-PrivateData).WslConfig.PrefixLengthKeyName
}

function Get-DnsServersKeyName {
    [CmdletBinding()]
    param()
    (Get-PrivateData).WslConfig.DnsServersKeyName
}

function Get-ProfileContent {
    [CmdletBinding()]
    param()
    (Get-PrivateData).ProfileContent
}

#endregion Helper Functions