[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve)

if (-not (IsElevated)) { Invoke-ScriptElevated $MyInvocation.MyCommand.Path }

. (Join-Path $PSScriptRoot 'FunctionsHNS.ps1' -Resolve)

Get-HnsNetworkEx | Where-Object { $_.Name -Eq 'WSL' } | Remove-HnsNetworkEx

$msgRemoved = 'Removed Hyper-V Network Adpater: WSL.'
Write-Debug "$($MyInvocation.MyCommand.Name): $msgRemoved"
Write-Host $msgRemoved
