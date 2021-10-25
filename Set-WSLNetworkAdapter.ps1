[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('Gateway')]
    [ipaddress]$GatewayIpAddress,

    [Parameter()][Alias('Prefix')]
    [int]$IpAddressPrefixLength = 24,

    [Parameter()][Alias('DNS')]
    [string]$DNSServerList  # Comma separated ipaddresses/hosts
)

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve)

if (-not (IsElevated)) {
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ArgumentList @($GatewayIpAddress, $IpAddressPrefixLength, $DNSServerList)
}

. (Join-Path $PSScriptRoot 'FunctionsHNS.ps1' -Resolve)

if ([string]::IsNullOrWhiteSpace($IpAddressPrefixLength)) {
    $IpAddressPrefixLength = 24
}

if (-not $PSBoundParameters.ContainsKey('DNSServerList')) {
    $DNSServerList = $GatewayIpAddress
}

if ([string]::IsNullOrWhiteSpace($DNSServerList)) {
    $DNSServerList = $GatewayIpAddress
}

$name = $MyInvocation.MyCommand.Name
$ipcalc = (Join-Path $PSScriptRoot 'IP-Calc.ps1' -Resolve)
$ipObj = (& $ipcalc -IPAddress $GatewayIpAddress -PrefixLength $IpAddressPrefixLength)

$networkParameters = @{
    AddressPrefix  = $ipObj.CIDR
    GatewayAddress = $GatewayIpAddress
    DNSServerList  = $DNSServerList
}

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
                "AddressPrefix" : "$($networkParameters.AddressPrefix)",
                "GatewayAddress" : "$($networkParameters.GatewayAddress)",
                "IpSubnets" : [
                    {
                        "ID" : "4D120505-4143-4CB2-8C53-DC0F70049696",
                        "Flags": 3,
                        "IpAddressPrefix": "$($networkParameters.AddressPrefix)",
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
        "DNSServerList" : "$($networkParameters.DNSServerList)"
}
"@

Get-HnsNetworkEx | Where-Object { $_.Name -Eq 'WSL' } | Remove-HnsNetworkEx | Out-Null

New-HnsNetworkEx -Id B95D0C5E-57D4-412B-B571-18A81A16E005 -JsonString $network | Out-Null

$msgCreated = 'Created New WSL Hyper-V VM Adapter with: '
$msgCreated += ($networkParameters.GetEnumerator() |
        ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
Write-Debug "${name}: $msgCreated"
Write-Verbose $msgCreated
