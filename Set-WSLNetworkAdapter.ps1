[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][Alias('Gateway')]
    [ipaddress]$GatewayIpAddress,

    [Parameter(Position = 1)][Alias('Prefix')]
    [int]$PrefixLength = 24,

    [Parameter(Position = 2)][Alias('DNS')]
    [string]$DNSServerList, # Comma separated ipaddresses/hosts

    [Parameter()][Alias('Name')]
    [string]$VirtualAdapterName = 'WSL'
)

. (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null

if (-not (IsElevated)) {
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ArgumentList @($GatewayIpAddress, $PrefixLength, $DNSServerList, $VirtualAdapterName)
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$removeNetworkScript = Join-Path $PSScriptRoot 'Remove-WslNetworkAdapter.ps1' -Resolve

& $removeNetworkScript $VirtualAdapterName

if ([string]::IsNullOrWhiteSpace($VirtualAdapterName)) {
    $VirtualAdapterName = 'WSL'
}

if ([string]::IsNullOrWhiteSpace($PrefixLength)) {
    $PrefixLength = 24
}

if (-not $PSBoundParameters.ContainsKey('DNSServerList')) {
    $DNSServerList = $GatewayIpAddress
}

if ([string]::IsNullOrWhiteSpace($DNSServerList)) {
    $DNSServerList = $GatewayIpAddress
}

$fn = $MyInvocation.MyCommand.Name

Import-Module (Join-Path $PSScriptRoot 'IP-Calc.psm1' -Resolve) -Function Get-IpCalcResult -Verbose:$false -Debug:$false | Out-Null
$ipObj = Get-IpCalcResult -IPAddress $GatewayIpAddress -PrefixLength $PrefixLength

$networkParameters = @{
    AddressPrefix  = $ipObj.CIDR
    GatewayAddress = $GatewayIpAddress
    DNSServerList  = $DNSServerList
}

$networkParametersAsString = ($networkParameters.GetEnumerator() |
        ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '

$hnsModuleName = 'HNS'
$hnsModule = Join-Path $PSScriptRoot "$hnsModuleName.psm1" -Resolve

Import-Module $hnsModule -Function 'New-HnsNetworkEx', 'Get-HnsNetworkEx', 'Get-HnsNetworkId', 'New-HnsNetworkSettings', 'Get-HnsNetworkSubnets' -Verbose:$false -Debug:$false | Out-Null

$existingHnsNetworks = Get-HnsNetworkSubnets
Write-Debug 'Existing Hyper-V adapters:'
Write-Debug "$($existingHnsNetworks | Out-String)"

foreach ($hnsNetwork in $existingHnsNetworks) {
    if ($hnsNetwork.Name -ne $VirtualAdapterName -and $hnsNetwork.AddressPrefix) {
        Write-Debug "Checking if new subnet $($ipObj.CIDR) will overlap with $($hnsNetwork.AddressPrefix)"
        if ($ipObj.Overlaps($hnsNetwork.AddressPrefix)) {
            Throw "Cannot create Hyper-V VM Adapter '$VirtualAdapterName' with $networkParametersAsString, because it's subnet $($ipObj.CIDR) overlaps with existing subnet of '$($hnsNetwork.Name)': $($hnsNetwork.AddressPrefix)"
        }
    }
}

Write-Verbose "Creating new Hyper-V VM Adapter: '$VirtualAdapterName' with $networkParametersAsString"

switch ($VirtualAdapterName) {
    'WSL' {
        $Flags = 9  # Cannot be 11 - nameserver will not be assigned in WSL instances
    }
    'Default Switch' {
        $Flags = 11  # "EnableDnsProxy" (1), "EnableDhcpServer" (2), "IsolateVSwitch" (8)
    }
    Default { ThrowTerminatingError "Parameter 'VirtualAdapterName' in $fn can be one of { 'WSL' | 'Default Switch' }, not '$VirtualAdapterName'." }
}

$networkSetting = New-HnsNetworkSettings -Json `
    -Name $VirtualAdapterName `
    -GatewayIpAddress $networkParameters.GatewayAddress `
    -AddressPrefix $networkParameters.AddressPrefix `
    -DNSServerList $networkParameters.DNSServerList `
    -Flags $Flags

$networkId = Get-HnsNetworkId $VirtualAdapterName

New-HnsNetworkEx -Id $NetworkId -JsonString $networkSetting | Out-Null

$hnsNetwork = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

Remove-Module $hnsModuleName -Verbose:$false -Debug:$false

if ($null -eq $hnsNetwork) {
    ThrowTerminatingError "Failed to create Hyper-V VM Adapter: '$VirtualAdapterName': $networkParametersAsString"
}
else {
    $originalErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $hnsNetworkSubnet = $hnsNetwork.Subnets[0]

    if ($hnsNetworkSubnet.GatewayAddress -ne $networkParameters.GatewayAddress) {
        ThrowTerminatingError "New Hyper-V VM Adapter: '$VirtualAdapterName' was created, but actual GatewayAddress: $($hnsNetworkSubnet.GatewayAddress) is different from required: $($networkParameters.GatewayAddress)"
    }

    if ($hnsNetworkSubnet.AddressPrefix -ne $networkParameters.AddressPrefix) {
        ThrowTerminatingError "New Hyper-V VM Adapter: '$VirtualAdapterName' was created, but actual AddressPrefix: $($hnsNetworkSubnet.AddressPrefix) is different from required: $($networkParameters.AddressPrefix)"
    }

    if ($hnsNetwork.DNSServerList -ne $networkParameters.DNSServerList) {
        ThrowTerminatingError "New Hyper-V VM Adapter: '$VirtualAdapterName' was created, but actual DNSServerList: $($hnsNetwork.DNSServerList) is different from required: $($networkParameters.DNSServerList)"
    }

    $vEthernetName = "vEthernet ($VirtualAdapterName)"

    $networkAdapter = Get-NetAdapter -Name $vEthernetName

    if ($null -eq $networkAdapter) {
        ThrowTerminatingError "Network Adapter: '$vEthernetName' was not created as expected!"
    }

    if ($networkAdapter.Status -ne 'Up') {
        ThrowTerminatingError "Network Adapter: '$vEthernetName' was created, but is not active!"
    }

    $netIpAddress = Get-NetIPAddress -InterfaceAlias $vEthernetName -AddressFamily IPv4
    if ($GatewayIpAddress -ne $netIpAddress.IPAddress) {
        ThrowTerminatingError "Actual IP Address of Network Adapter: '$vEthernetName': $($netIpAddress.IPAddress) is different from required: $GatewayIpAddress"
    }

    $ErrorActionPreference = $originalErrorActionPreference

    if ($PrefixLength -ne $netIpAddress.PrefixLength) {
        ThrowTerminatingError "Actual PrefixLength of Network Adapter: '$vEthernetName': $($netIpAddress.PrefixLength) is different from required: $PrefixLength"
    }

    $msgCreated = "Created New Hyper-V VM Adapter: '$VirtualAdapterName'"
    Write-Verbose "${msgCreated} with $networkParametersAsString"
}
