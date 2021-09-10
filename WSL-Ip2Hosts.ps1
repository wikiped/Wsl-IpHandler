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

function IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { $true }
    else { $false }
}

function EncodeCommand {
    param ($Command)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    [Convert]::ToBase64String($bytes)
}

function GetPowerShellExecutablePath {
    $psName = If ($PSVersionTable.PSVersion.Major -le 5) { 'powershell' } Else { 'pwsh' }
    $psexe = Join-Path $PSHOME "${psName}.exe"
    if (!(Test-Path -Path $psexe -PathType Leaf)) {
        Write-Error "PowerShell Executable Cannot be located: $psexe" -ErrorAction Stop
    }
    $psexe
}

function RunElevated {
    param($CommandToEncode)
    $encodedCommand = EncodeCommand $CommandToEncode
    $argList = '-WindowStyle', 'Hidden', '-EncodedCommand', $encodedCommand
    Write-Debug 'Requesting Administrator Permissions...'
    $psexe = (GetPowerShellExecutablePath)
    Start-Process $psexe -WindowStyle Hidden -Verb RunAs -ArgumentList $argList
}

function ContainsIpAddress {
    param ([string]$Line, [string]$regexIpAddress)
    $Line -match "^\s*$regexIpAddress"
}

function ContainsHost {
    param ([string]$Line, [string]$regexHostName)
    $Line -match ".*$regexHostName.*"
}

function HostAssignedToAnotherIpAddress {
    param ([string]$Line, [string]$regexIpAddress, [string]$regexHostName)
    $reIp = '^\s*(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))\.){3}(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))(\s|$))'
    ($Line -match $reIp) -and (ContainsHost $Line $regexHostName) -and -not (ContainsIpAddress $Line $regexIpAddress)
}

function GetIpHostsComment ($Line) {
    $Ip, $rest = $Line.Trim() -split ' ', 2
    $Hosts, $Comment = $rest.Trim() -split '#', 2
    $Ip.Trim(), $Hosts.Trim(), ('#' + $Comment)
}

function GetHostsCount ($Hosts) {
    $hostsArray = $Hosts -split ' '
    $hostsArray.Count
}

function CreateAssignment ($IpAddress, $HostName, $comment = '  # Added by WSL-Ip2Hosts.ps1') {
    $line = $IpAddress.PadRight(17, ' ')
    $line += $HostName
    $line + ($comment ? $comment.PadLeft(80 - $line.Length, ' ') : '')
}

function ProcessContent {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [array]$Lines,
        [string]$HostIpAddress,
        [string]$HostName,
        [ref][bool]$Modified,
        [switch]$KeepExistingHosts = $keepExistingHosts
    )
    $array = @($input)
    if ($array.Count) { $Lines = $array }
    if (!(Test-Path variable:Lines)) { $Lines = @() }

    $regexIpAddress = [Regex]::Escape($HostIpAddress)
    $regexHostName = [regex]::Escape($HostName)
    $AssignmentFound = $false

    $Lines = $Lines | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_ -match '^\s*#') {
            $_  # This line is a comment - keep it as is
        }
        elseif (ContainsIpAddress $_ $regexIpAddress) {
            if (ContainsHost $_ $regexHostName) {
                if (-not $AssignmentFound) {
                    $AssignmentFound = $true
                    $existingIp, $existingHosts, $comment = GetIpHostsComment $_
                    if ((GetHostsCount $existingHosts) -gt 1 -and -not $KeepExistingHosts) {
                        $Modified.Value = $true
                        CreateAssignment $existingIp $HostName $comment
                    }
                    else {
                        $_  # Line has Correct Ip and Correct Host -> Keep it as is
                    }
                }  # else Line has Correct Ip and Correct Host, but it's a duplicate -> Drop it
            }
            else {
                # Line has Correct Ip but does not have Correct Host -> Add host name
                $existingIp, $existingHosts, $comment = GetIpHostsComment $_
                $Modified.Value = $true
                $AssignmentFound = $true
                if ($KeepExistingHosts) {
                    $newHosts = $existingHosts + " $HostName"
                    CreateAssignment $existingIp $newHosts $comment
                }
                else {
                    CreateAssignment $existingIp $HostName $comment
                }
            }
        }
        else {
            if (ContainsHost $_ $regexHostName) {
                # Host is used for another IP - Remove host from this assignment
                $existingIp, $existingHosts, $comment = GetIpHostsComment $_
                $hostsArray = $existingHosts -split ' '
                $Modified.Value = $true  # host in use - we need to remove this host / assignment
                if ($hostsArray.Count -gt 1) {
                    # It is NOT the only host -> modify assignment
                    $newHosts = $hostsArray -notmatch $regexHostName
                    CreateAssignment $existingIp ($newHosts -join ' ') $comment
                }
                # else It is the only host -> Drop this assignment
            }
            else { $_ }  # This line is some other assignment - keep it as is
        }
    }
    if (-not $AssignmentFound) {
        $newAssignment = CreateAssignment $HostIpAddress $HostName
        $Lines += $newAssignment
        $Modified.Value = $true
    }
    $Lines
}

$errorMessage = ''
if ($null -eq $HostIpAddress) { $errorMessage += 'Host IP Address must be provided. ' }
if ($null -eq $HostName) { $errorMessage += 'Host Name(s) must be provided.' }
if ($errorMessage) { Write-Error $errorMessage -ErrorAction Stop }

$hostsFilePath = $Env:WinDir + '\system32\Drivers\etc\hosts'

$originalHostsContent = Get-Content $hostsFilePath
Write-Debug "Lines in Hosts File Before Processing: $($originalHostsContent.Count)"

$contentModified = $false

$newHostsContent = ProcessContent $originalHostsContent $HostIpAddress $HostName ([ref]$contentModified)
Write-Debug "Lines in Hosts File After Processing: $($newHostsContent.Count)"
Write-Debug "Was Hosts File modified?: $contentModified"

Write-Debug "$($newHostsContent | Out-String )"

if ($contentModified) {
    if (-not (IsElevated)) {
        $newHostsContent = $newHostsContent -join "`n"
        $command = "Set-Content -Path `"$hostsFilePath`" -Value `"$newHostsContent`" -Encoding ASCII"
        RunElevated $command
    }
    else {
        Set-Content -Path $hostsFilePath -Value $newHostsContent -Encoding ASCII
    }
}
exit $?
