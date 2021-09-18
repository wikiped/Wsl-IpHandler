function ContainsIpAddress {
    [CmdLetBinding()]
    param ([string]$Line, [string]$regexIpAddress)
    $Line -match "^\s*$regexIpAddress"
}

function ContainsHost {
    [CmdLetBinding()]
    param ([string]$Line, [string]$regexHostName)
    $Line -match ".*$regexHostName.*"
}

function HostAssignedToAnotherIpAddress {
    [CmdLetBinding()]
    param ([string]$Line, [string]$regexIpAddress, [string]$regexHostName)
    $ip_pattern = '^\s*(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))\.){3}(((25[0-5]|(2[0-4]|1\d|[1-9]|)\d))(\s|$))'
    ($Line -match $ip_pattern) -and (ContainsHost $Line $regexHostName) -and -not (ContainsIpAddress $Line $regexIpAddress)
}

function GetIpHostsComment {
    [CmdLetBinding()]
    param($Line)
    $Ip, $rest = $Line.Trim() -split ' ', 2
    $Hosts, $Comment = $rest.Trim() -split '#', 2
    $Ip.Trim(), $Hosts.Trim(), ('#' + $Comment)
}

function GetHostsCount {
    [CmdLetBinding()]
    param($Hosts)
    $hostsArray = $Hosts -split ' '
    $hostsArray.Count
}

function CreateAssignment {
    [CmdLetBinding()]
    param($IpAddress, $HostName, $comment = '  # Created by WSL-IpHandler PowerShell Module')
    $line = $IpAddress.PadRight(17, ' ')
    $line += $HostName
    $line + ($comment ? $comment.PadLeft(80 - $line.Length, ' ') : '')
}
