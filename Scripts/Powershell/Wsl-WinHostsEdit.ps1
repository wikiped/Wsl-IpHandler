[CmdletBinding()]
param(
    [Parameter(Mandatory)][ipaddress]
    $HostIpAddress,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $HostName,

    [Parameter()]
    [switch]
    $KeepExistingHosts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest

. (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve) | Out-Null

$errorMessage = ''
if ($null -eq $HostIpAddress) { $errorMessage += 'Host IP Address must be provided. ' }
if ($null -eq $HostName) { $errorMessage += 'Host Name(s) must be provided.' }
if ($errorMessage) { Write-Error "$errorMessage" -ErrorAction Stop }

$originalHostsContent = Get-HostsFileContent
Write-Debug "$(_@) Lines in Hosts File Before Processing: $(@($originalHostsContent).Count)"

$contentModified = $false

$newHostsContent = Add-IpAddressHostRecord -Records $originalHostsContent -HostIpAddress $HostIpAddress -HostName $HostName -Modified ([ref]$contentModified) -ReplaceExistingHosts
Write-Debug "$(_@) Lines in Hosts File After Processing: $(@($newHostsContent).Count)"
Write-Debug "$(_@) Was Hosts File modified?: $contentModified"


if ($contentModified) {
    Write-Debug "$(_@) Modified Hosts File: $($newHostsContent | Out-String )"
    Write-HostsFileContent $newHostsContent
}
exit $?
