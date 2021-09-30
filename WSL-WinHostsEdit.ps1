[CmdletBinding()]
param(
    [Parameter(Mandatory)][ipaddress]
    $HostIpAddress,

    [string]
    $HostName,

    [switch]
    $KeepExistingHosts
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve)

$errorMessage = ''
if ($null -eq $HostIpAddress) { $errorMessage += 'Host IP Address must be provided. ' }
if ($null -eq $HostName) { $errorMessage += 'Host Name(s) must be provided.' }
if ($errorMessage) { Write-Error $errorMessage -ErrorAction Stop }

$originalHostsContent = (Get-HostsFileContent)
Write-Debug "Lines in Hosts File Before Processing: $($originalHostsContent.Count)"

$contentModified = $false

$newHostsContent = Add-IpAddressHostToRecords -Records $originalHostsContent -HostIpAddress $HostIpAddress -HostName $HostName -Modified ([ref]$contentModified)
Write-Debug "Lines in Hosts File After Processing: $($newHostsContent.Count)"
Write-Debug "Was Hosts File modified?: $contentModified"

Write-Debug "$($newHostsContent | Out-String )"

if ($contentModified) { Write-HostsFileContent $newHostsContent }
exit $?
