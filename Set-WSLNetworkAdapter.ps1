[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][Alias('Gateway')]
    [ipaddress]$GatewayIpAddress,

    [Parameter(Position = 1)][Alias('Prefix')]
    [int]$PrefixLength = 24,

    [Parameter(Position = 2)][Alias('DNS')]
    [string]$DNSServerList, # Comma separated ipaddresses/hosts

    [Parameter()][Alias('Name')]
    [string]$VirtualAdapterName = 'WSL',

    [Parameter()]
    [string[]]$DynamicAdapters = @('Ethernet', 'Default Switch')
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

$ipNetModuleName = 'IPNetwork'
$ipNetModule = Join-Path $PSScriptRoot "$ipNetModuleName.psm1" -Resolve
Import-Module $ipNetModule -Verbose:$false -Debug:$false | Out-Null

function Get-OverlappingNetworkConnectionsSplit {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AdapterName,

        [Parameter(Mandatory, ParameterSetName = 'Cidr')]
        [ValidateScript( { Test-IsValidCidr $_ })]
        [string]$Cidr,

        [Parameter(Mandatory, ParameterSetName = 'Ip')]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [ipaddress]$IpAddress,

        [Parameter(Mandatory, ParameterSetName = 'Ip')]
        [ValidateRange(0, 32)]
        [int]$PrefixLength,

        [string[]]$DynamicAdapters = $DynamicAdapters
    )
    if ($PSCmdlet.ParameterSetName -eq 'Cidr') {
        $IpAddress, $PrefixLength = Get-CidrParts $Cidr
    }

    $existingConnections = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object IPAddress -NE '127.0.0.1' |
        Where-Object InterfaceAlias -NotMatch "vEthernet \($AdapterName\).*" |
        Select-Object InterfaceAlias, IPAddress, PrefixLength

    $ipObj = Get-IpNet -IPAddress $IpAddress -PrefixLength $PrefixLength

    $result = @{ Dynamic = @(); Static = @() }

    if ($existingConnections) {
        $existingConnections |
            ForEach-Object {
                if ($ipObj.Overlaps($_.IPAddress, $_.PrefixLength)) {
                    $alias = $_.InterfaceAlias
                    if ($DynamicAdapters | Where-Object { $alias -match "vEthernet \($_\).*" }) {
                        $result.Dynamic += $_
                    }
                    else {
                        $result.Static += $_
                    }
                }
            }
    }

    $result
}

function Get-MatchingAdapterForInterfaceAlias {
    param (
        [Parameter()]
        [string]$InterfaceAlias,
        [string[]]$DynamicAdapters = $DynamicAdapters
    )
    $DynamicAdapters | Where-Object { $InterfaceAlias -match "vEthernet \($_\).*" }
}

$fn = $MyInvocation.MyCommand.Name

$ipObj = Get-IpNet -IPAddress $GatewayIpAddress -PrefixLength $PrefixLength

$networkParameters = @{
    AddressPrefix  = $ipObj.CIDR
    GatewayAddress = $GatewayIpAddress
    DNSServerList  = $DNSServerList
}

$networkParametersAsString = ($networkParameters.GetEnumerator() |
        ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '

$errorMessage = @("Cannot create Hyper-V VM Adapter '$VirtualAdapterName' with $networkParametersAsString, because it's subnet $($ipObj.CIDR) overlaps with the following Network Connection(s):")

$hnsModuleName = 'HNS'
$hnsModule = Join-Path $PSScriptRoot "$hnsModuleName.psm1" -Resolve
Import-Module $hnsModule -Verbose:$false -Debug:$false | Out-Null

$overlappingConnections = Get-OverlappingNetworkConnectionsSplit -AdapterName $VirtualAdapterName -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength

if ($overlappingConnections.Dynamic) {
    Write-Debug "${fn}: Overlapping Dynamic Connections: $($overlappingConnections.Dynamic.InterfaceAlias -join '; ')"
    foreach ($connection in $overlappingConnections.Dynamic) {
        if ($connection.InterfaceAlias -match 'vEthernet \((?<adapter_name>.*)\).*') {
            $adapterName = $matches.adapter_name
            if ($adapterName) {
                $adapterId = Get-HnsNetworkId $adapterName
                if ($adapterId) {
                    Write-Debug "${fn}: Overlapping adapter to reallocate: '$adapterName' with Id: $adapterId."
                    $adapter = Get-HnsNetworkEx -Id $adapterId
                    Write-Debug "${fn}: Overlapping adapter properties:`n$($adapter | Out-String)"
                    $currentAddressPrefix = Get-IpNet -CIDR $adapter.Subnets[0].AddressPrefix

                    #TODO The subnetsToFitIn array ideally should be updated here to reflect the reallocation that might have happened before
                    $subnetsToFitIn = @($overlappingConnections.Dynamic |
                            ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" } |
                            Select-Object -Unique)
                    Write-Debug "${fn}: Subnets to find free space within: '$($subnetsToFitIn -join '; ')'."

                    $newAddressPrefix = $currentAddressPrefix.FindFreeSubnet($subnetsToFitIn)
                    Write-Debug "${fn}: New Subnet AddressPrefix: $newAddressPrefix for adapter: '$adapterName'."
                    Write-Debug "${fn}: Properties of existing adapter:`n$($adapter | Out-String)"

                    $newIpNet = Get-IpNet -CIDR $newAddressPrefix

                    $params = @{
                        GatewayIpAddress = $newIpNet.IPAddress.Add()
                        AddressPrefix    = $newAddressPrefix
                    }
                    Write-Debug "${fn}: Modified parameters of '$adapterName' Adapter to Re-Create:`n$($params | Out-String)"

                    $reCreatedAdapter = Set-HnsNetworkEx -Id $adapterId @params

                    Write-Debug "${fn}: Created Adapter: '$adapterName' with Id: $adapterId. with modified parameters:`n$($reCreatedAdapter | Out-String)"
                }
                else {
                    $errorMessage += "'$($connection.InterfaceAlias)' with IP Address/PrefixLength: $($conn.IPAddress)/$($conn.PrefixLength)"
                    $errorMessage += 'However Hyper-V Network adapter corresponding to this connection cannot be found. Try restarting Windows to fix this problem.'
                    Throw ($errorMessage -join "`n")
                }
            }
            else {
                $errorMessage += "There was was Error extracting Hyper-V Network Adapter Name from this connection's Alias: '$($connection.InterfaceAlias)"
                Throw ($errorMessage -join "`n")
            }
        }
        else {
            $errorMessage += "Network Connection's Interface Alias: '$($connection.InterfaceAlias)
            unexpectedly did not match pattern: 'vEthernet \((.*)\).*'"
            Throw ($errorMessage -join "`n")
        }
    }
}

if ($overlappingConnections.Static) {
    # Show Error about overlapping with existing Network Connection that can not be modified automatically and exit
    foreach ($conn in $overlappingConnections.Static) {
        $errorMessage += "'$($conn.InterfaceAlias)' with IP Address/PrefixLength: $($conn.IPAddress)/$($conn.PrefixLength)"
    }
    $errorMessage += "Choose another IP Address for WSL Subnet or Change IP Addresses of Network Connection(s) above in Windows Setting App: 'Network and Internet Settings' -> 'Change Adapter Options'."
    Throw ($errorMessage -join "`n")
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

$networkId = Get-HnsNetworkId $VirtualAdapterName

$networkSetting = New-HnsNetworkSettings -Json `
    -Name $VirtualAdapterName `
    -GatewayIpAddress $networkParameters.GatewayAddress `
    -AddressPrefix $networkParameters.AddressPrefix `
    -DNSServerList $networkParameters.DNSServerList `
    -Flags $Flags `
    -Type 'ICS'

New-HnsNetworkEx -Id $NetworkId -SettingsJsonString $networkSetting | Out-Null

$hnsNetwork = Get-HnsNetworkEx -Id $networkId -ErrorAction SilentlyContinue

Remove-Module $ipNetModuleName -Verbose:$false -Debug:$false
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
        Throw "Network Adapter: '$vEthernetName' was not created as expected!"
    }

    if ($networkAdapter.Status -ne 'Up') {
        Throw "Network Adapter: '$vEthernetName' was created, but is not active!"
    }

    $netIpAddress = Get-NetIPAddress -InterfaceAlias $vEthernetName -AddressFamily IPv4
    if ($GatewayIpAddress -ne $netIpAddress.IPAddress) {
        Throw "Actual IP Address of Network Adapter: '$vEthernetName': $($netIpAddress.IPAddress) is different from required: $GatewayIpAddress"
    }

    $ErrorActionPreference = $originalErrorActionPreference

    if ($PrefixLength -ne $netIpAddress.PrefixLength) {
        Throw "Actual PrefixLength of Network Adapter: '$vEthernetName': $($netIpAddress.PrefixLength) is different from required: $PrefixLength"
    }

    $msgCreated = "Created New Hyper-V VM Adapter: '$VirtualAdapterName'"
    Write-Verbose "${msgCreated} with $networkParametersAsString"
}
