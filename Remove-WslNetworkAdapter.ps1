[CmdletBinding()]
param(
    [Parameter()]
    [Alias('Name')]
    [string]$VirtualAdapterName = 'WSL'
)

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null

if (-not (IsElevated)) {
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ScriptParameters $PSBoundParameters
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hnsModule = Join-Path $PSScriptRoot 'HNS.psm1' -Resolve
Import-Module $hnsModule -Function 'Get-HnsNetworkId', 'Get-HnsNetworkEx', 'Remove-HnsNetworkEx' -Verbose:$false -Debug:$false | Out-Null

$networkId = Get-HnsNetworkId -Name $VirtualAdapterName

if ($networkId) {
    if (@($networkId).Count -gt 1) {
        Throw "$_ Hyper-V Network Adapters IDs found, when expected no more than 1."
    }
}
else {
    Write-Verbose "No ID found for Hyper-V Network Adapter: '$VirtualAdapterName'. Nothing to remove."
    return
}

Write-Debug "$($MyInvocation.MyCommand.Name): HNS Network '$VirtualAdapterName' with ID: $networkId"

$existingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

if (@($existingAdapter).Count -eq 1) {
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Existing Adapter`n$($existingAdapter | Out-String)"

    Write-Verbose "Removing existing Hyper-V Network Adapter '$VirtualAdapterName' ..."
    $existingAdapter.ID | Remove-HnsNetworkEx -ErrorAction SilentlyContinue | Out-Null

    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Checking if Hyper-V Network Adapter '$VirtualAdapterName' with Id: $networkId has been removed..."
    $remainingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

    if ($remainingAdapter) {
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Failed to remove existing adapter: '$VirtualAdapterName' with ID: $networkId"
        Write-Error "Cannot remove existing Hyper-V VM Adapter: '$VirtualAdapterName'. Try restarting Windows."
        return
    }
    else {
        Write-Verbose "Removed Existing Hyper-V Network Adapter: '$VirtualAdapterName'!"
        return
    }
}
else {
    Write-Verbose "Hyper-V Network Adapter: '$VirtualAdapterName' not found. Nothing to remove."
}
