param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Alias('Name')]
    [string]$VirtualAdapterName
)

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null

if (-not (IsElevated)) {
    Write-Debug "Invoking: Invoke-ScriptElevated $($MyInvocation.MyCommand.Path) -ScriptParameters $(& {$args} @PSBoundParameters)"
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ScriptParameters $PSBoundParameters
    exit
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

$hnsModule = Join-Path $PSScriptRoot '..\..\SubModules\HNS.psm1' -Resolve
Import-Module $hnsModule -Verbose:$false -Debug:$false

$networkId = Get-HnsNetworkId -Name $VirtualAdapterName

if ($networkId) {
    if (@($networkId).Count -gt 1) {
        Throw "$_ Hyper-V Network Adapters IDs found, when expected no more than 1."
    }
}
else {
    Write-Verbose "No ID found for Hyper-V Network Adapter: '$VirtualAdapterName'. Nothing to remove."
    exit
}

Write-Debug "$(_@): HNS Network '$VirtualAdapterName' with ID: $networkId"

$existingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue
Write-Debug "$(_@) Found Adapter: $($existingAdapter ?? 'None Found' | Out-String)"

if ($null -ne $existingAdapter -and $existingAdapter.Count -eq 1) {

    Write-Verbose "Removing existing Hyper-V Network Adapter '$VirtualAdapterName' ..."
    $existingAdapter.ID | Remove-HnsNetworkEx -ErrorAction SilentlyContinue | Out-Null

    Write-Debug "$(_@) Checking if Hyper-V Network Adapter '$VirtualAdapterName' with Id: $networkId has been removed..."
    $remainingAdapter = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

    if ($remainingAdapter) {
        Write-Debug "$(_@) Failed to remove existing adapter: '$VirtualAdapterName' with ID: $networkId"
        Write-Error "Cannot remove existing Hyper-V VM Adapter: '$VirtualAdapterName'. Try restarting Windows."
    }
    else {
        Write-Verbose "Removed Existing Hyper-V Network Adapter: '$VirtualAdapterName'!"
    }
}
else {
    Write-Debug "Hyper-V Network Adapter: '$VirtualAdapterName' not found. Nothing to remove."
}
