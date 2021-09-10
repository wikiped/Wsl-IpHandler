[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('Gateway')]
    [ipaddress]$GatewayIpAddress,

    [Parameter()][Alias('Prefix')]
    [int]$IpAddressPrefixLength = 24,

    [Parameter()][Alias('DNS')]
    [string]$DNSServerList  # Comma separated ipaddresses/hosts
)

if ([string]::IsNullOrWhiteSpace($IpAddressPrefixLength)) {
    $IpAddressPrefixLength = 24
}

if (-not $PSBoundParameters.ContainsKey('DNSServerList')) {
    $DNSServerList = $GatewayIpAddress
}

if ([string]::IsNullOrWhiteSpace($DNSServerList)) {
    $DNSServerList = $GatewayIpAddress
}

$NHSsource = (Join-Path $PSScriptRoot 'HNS-Functions.ps1' -Resolve)
source $NHSsource

$ipcalc = (Join-Path $PSScriptRoot 'IP-Calc.ps1')
$ipPrefix = (. $ipcalc "${$GatewayIpAddress}/$IpAddressPrefixLength")

$network = @"
{
        "Name" : "WSL",
        "Flags": 9,
        "Type": "ICS",
        "IPv6": false,
        "IsolateSwitch": true,
        "MaxConcurrentEndpoints": 1,
        "Subnets" : [
            {
                "ID" : "FC437E99-2063-4433-A1FA-F4D17BD55C92",
                "ObjectType": 5,
                "AddressPrefix" : "$($ipPrefix.CIDR)",
                "GatewayAddress" : "$GatewayIpAddress",
                "IpSubnets" : [
                    {
                        "ID" : "4D120505-4143-4CB2-8C53-DC0F70049696",
                        "Flags": 3,
                        "IpAddressPrefix": "$($ipPrefix.CIDR)",
                        "ObjectType": 6
                    }
                ]
            }
        ],
        "MacPools":  [
            {
                "EndMacAddress":  "00-15-5D-52-CF-FF",
                "StartMacAddress":  "00-15-5D-52-C0-00"
            }
        ],
        "DNSServerList" : "$DNSServerList"
}
"@

Get-HnsNetworkEx | Where-Object { $_.Name -Eq 'WSL' } | Remove-HnsNetworkEx
New-HnsNetworkEx -Id B95D0C5E-57D4-412B-B571-18A81A16E005 -JsonString $network
