[CmdletBinding()]
param(
    [Parameter()]
    [Alias('Name')]
    [string]$VirtualAdapterName = 'WSL'
)

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null

if (-not (IsElevated)) {
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ScriptCommonParameters $MyInvocation.BoundParameters
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fn = $MyInvocation.MyCommand.Name

$hnsModule = Join-Path $PSScriptRoot 'HNS.psm1' -Resolve
Import-Module $hnsModule -Function 'Get-HnsNetworkId', 'Get-HnsNetworkEx', 'Remove-HnsNetworkEx' -Verbose:$false -Debug:$false | Out-Null

$networkId = [guid](Get-HnsNetworkId $VirtualAdapterName)

Write-Debug "${fn}: HNS Network '$VirtualAdapterName' with Id: $networkId"

$existingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

if ($existingAdapter) {
    Write-Debug "${fn}: Existing Adapter`n$($existingAdapter | Out-String)"

    Write-Verbose "Removing existing Hyper-V Network Adapter '$VirtualAdapterName' ..."
    $existingAdapter.ID | Remove-HnsNetworkEx -ErrorAction SilentlyContinue | Out-Null

    Write-Debug "${fn}: Checking if Hyper-V Network Adapter '$VirtualAdapterName' with Id: $networkId has been removed..."
    $remainingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

    if ($remainingAdapter) {
        Write-Debug "${fn}: Failed to remove existing adapter: '$VirtualAdapterName' with ID: $networkId"
        Write-Error "Cannot remove existing Hyper-V VM Adapter: '$VirtualAdapterName'. Try restarting Windows."
    }
    else {
        Write-Verbose "Removed Existing Hyper-V Network Adapter: '$VirtualAdapterName'!"
    }
}
else {
    Write-Verbose "Hyper-V Network Adapter: '$VirtualAdapterName' not found. Nothing to remove."
}
