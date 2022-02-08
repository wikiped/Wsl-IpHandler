using namespace System.Net.Sockets
using namespace System.Management.Automation

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

$IpNetworkTypeName = 'IPNetwork'

#region Extend System.Net.IPAddress type
$BinaryScriptProperty = {
    ($This.GetAddressBytes() |
        ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join '.'
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptProperty -MemberName 'Binary' -Value $BinaryScriptProperty -Force

$ToBinaryScriptMethod = {
    $separator = $args ? $args[0] : ''
    ($This.GetAddressBytes() |
        ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join $separator
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptMethod -MemberName 'ToBinary' -Value $ToBinaryScriptMethod -Force

$DecimalScriptProperty = {
    [Convert]::ToInt64($This.ToBinary(), 2)
    # [int]$b1, [int]$b2, [int]$b3, [int]$b4 = $This.GetAddressBytes()
    # [int64]($b1 * 16mb + $b2 * 64kb + $b3 * 256 + $b4)
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptProperty -MemberName 'Decimal' -Value $DecimalScriptProperty -Force

$NetworkClassScriptProperty = {
    switch ($This.GetAddressBytes()[0]) {
        { $_ -in 0..126 } { 'A' }
        { $_ -in 128..191 } { 'B' }
        { $_ -in 192..233 } { 'C' }
        { $_ -in 224..239 } { 'D' }
        { $_ -in 240..255 } { 'E' }
        Default { '' }
    }
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptProperty -MemberName 'NetworkClass' -Value $NetworkClassScriptProperty -Force

$PrivateNetworkCidrScriptProperty = {
    switch ($This.GetAddressBytes(), @()) {
        { $_[0] -eq 10 } { return '10.0.0.0/8' }
        { $_[0] -eq 172 -and ($_[1] -ge 16 -or $_[1] -le 31) } { return '172.16.0.0/12' }
        { $_[0] -eq 192 -and $_[1] -eq 168 } { return '192.168.0.0/16' }
    }
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptProperty -MemberName 'CidrPrivateNetwork' -Value $PrivateNetworkCidrScriptProperty -Force

$AddScriptMethod = {
    [int]$n = if ($args.Count) { $args[0] } else { 1 }
    if ($n -eq 0) { return $This }
    [int]$octet = if ($args.Count -gt 1) { $args[1] } else { 4 }
    switch ($octet) {
        4 { $adder = $n }
        3 { $adder = $n * 256 }
        2 { $adder = $n * 64kb }
        1 { $adder = $n * 16mb }
        Default {
            Throw "There are 4 octets in IP Address: 1st.2nd.3rd.4th - There is no octet: $octet"
        }
    }
    [ipaddress]"$($this.Decimal + $adder)"
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptMethod -MemberName 'Add' -Value $AddScriptMethod -Force

$SubtractMethod = {
    [int]$n = if ($args.Count) { $args[0] } else { 1 }
    if ($n -eq 0) { return $This }
    [int]$octet = if ($args.Count -gt 1) { $args[1] } else { 4 }
    switch ($octet) {
        4 { $subtractor = $n }
        3 { $subtractor = $n * 256 }
        2 { $subtractor = $n * 64kb }
        1 { $subtractor = $n * 16mb }
        Default {
            Throw "There are 4 octets in IP Address: 1st.2nd.3rd.4th - There is no octet: $octet"
        }
    }
    [ipaddress]"$($this.Decimal - $subtractor)"
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptMethod -MemberName 'Subtract' -Value $SubtractMethod -Force

$CompareToMethod = {
    if ($args.Count) {
        [ipaddress]$other = $args[0]
    }
    else { return 0 }
    $this.Decimal - $other.Decimal
}
Update-TypeData -TypeName 'System.Net.IPAddress' -MemberType ScriptMethod -MemberName 'CompareTo' -Value $CompareToMethod -Force
#endregion Extend System.Net.IPAddress type

#region Generic Functions
Function Test-IsValidIpAddress {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [array]$IpAddress
    )
    $array = @($input)
    if ($array.Count) { $IpAddress = $array }
    if (!(Test-Path variable:IpAddress)) { $IpAddress = @() }
    $IpAddress | ForEach-Object {
        try { ($_ -as [ipaddress]).AddressFamily -eq [AddressFamily]::InterNetwork }
        catch { $false }
    }
}

function Test-IsValidCidr {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()][AllowEmptyCollection()]
        [string[]]$Cidr
    )
    $array = @($input)
    if ($array.Count) { $Cidr = $array }
    if (!(Test-Path variable:Cidr)) { $Cidr = @() }
    $Cidr | ForEach-Object {
        if ($_ -is [string]) {
            try {
                $ipAddress, $prefixLength = $_ -split '\\|\/' | Select-Object -First 2
                (Test-IsValidIpAddress $ipAddress) -and [string[]](0..32) -contains $prefixLength
            }
            catch { $false }
        }
        else { $false }
    }
}

Function Get-CidrParts {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({ Test-IsValidCidr $_ })]
        [string[]]$Cidr
    )
    $array = @($input)
    if ($array.Count) { $Cidr = $array }
    if (!(Test-Path variable:Cidr)) { $Cidr = @() }
    $Cidr | ForEach-Object {
        $CIDR -split '\\|\/' | Select-Object -First 2
    }
}

Function ConvertFrom-IpAddressToDecimal {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()][AllowEmptyCollection()]
        [ipaddress[]]$IpAddress
    )
    $array = @($input)
    if ($array.Count) { $IpAddress = $array }
    if (!(Test-Path variable:IpAddress)) { $IpAddress = @() }
    $IpAddress | ForEach-Object {
        [Convert]::ToInt64($IpAddress.ToBinary(), 2)
        # [int]$b1, [int]$b2, [int]$b3, [int]$b4 = $IPAddress.GetAddressBytes()
        # [int64]($b1 * 16mb + $b2 * 64kb + $b3 * 256 + $b4)
    }
}

Function ConvertFrom-DecimalToIpAddress {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [int64[]]$Decimal
    )
    $array = @($input)
    if ($array.Count) { $Decimal = $array }
    if (!(Test-Path variable:Decimal)) { $Decimal = @() }
    $Decimal | ForEach-Object {
        [ipaddress]("$Decimal")
        # [int]$b1 = [Math]::Floor($ip.Decimal % 16mb % 64kb % 256)
        # [int]$b2 = [Math]::Floor($ip.Decimal % 16mb % 64kb / 256)
        # [int]$b3 = [Math]::Floor($ip.Decimal % 16mb / 64kb)
        # [int]$b4 = [Math]::Floor($ip.Decimal / 16mb)
        # [ipaddress]("$b1.$b2.$b3.$b4")
    }
}

Function ConvertFrom-IpAddressToBinaryString {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript( { Test-IsValidIpaddress $_ })]
        [ipaddress[]]$IpAddress,

        [Parameter()][Alias('Separator')]
        [string]$OctetsSeparator = '.'
    )
    $array = @($input)
    if ($array.Count) { $IpAddress = $array }
    if (!(Test-Path variable:IpAddress)) { $IpAddress = @() }
    $IpAddress | ForEach-Object {
            ($_.GetAddressBytes() | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') }) -join $OctetsSeparator
    }
}

Function ConvertFrom-PrefixLengthToMask {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateRange(0, 32)]
        [int[]]$PrefixLength
    )
    $array = @($input)
    if ($array.Count) { $PrefixLength = $array }
    if (!(Test-Path variable:PrefixLength)) { $PrefixLength = @() }
    $PrefixLength | ForEach-Object {
        [IPAddress]([string](4gb - ([Math]::Pow(2, (32 - $_)))))
    }
}

Function Get-BroadcastFromSubnetAndWildcard {
    param(
        [Parameter(Mandatory)]
        [ValidateScript( { Test-IsValidIpaddress $_ })]
        [ipaddress]$IpAddress,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ipaddress]$Wildcard
    )
    [int[]]$SplitIpAddress = $IpAddress.GetAddressBytes()
    [int[]]$SplitWildCard = $Wildcard.GetAddressBytes()
    [IPAddress]$Broadcast = (0..3 | ForEach-Object { [int]($SplitIpAddress[$_]) + [int]($SplitWildCard[$_]) }) -join '.'
    $Broadcast
}
#endregion Generic Functions

#region IPNetwork Methods
$AddMethod = {
    param(
        [int]$Add,
        [ValidateRange(0, 32)][int]$PrefixLength = $This.PrefixLength
    )
    Get-IpNet -IPAddress "$($This.Decimal + $Add)" -PrefixLength $PrefixLength
}

$ContainsMethod = {
    param (
        [Parameter(Mandatory)]
        [object]$IpAddressOrCidrOrIpCalcResult
    )
    switch ($IpAddressOrCidrOrIpCalcResult) {
        { $_.psobject.TypeNames[0] -eq $IpNetworkTypeName } {
            $Other = $_
            break
        }
        { Test-IsValidCidr $_ } {
            $Other = Get-IpNet -Cidr $_
            break
        }
        { Test-IsValidIpAddress $_ } {
            $Other = Get-IpNet -IpAddress $_ -PrefixLength 32
            break
        }
        Default {
            Throw "First argument in Contains method must be a valid IpAddress or CIDR or IpCalcResult object, not $($_.Gettype()): '$_'"
        }
    }
    $This.Subnet.Decimal -le $Other.Subnet.Decimal -and $This.Broadcast.Decimal -ge $Other.Broadcast.Decimal
}

$OverlapsMethod = {
    param (
        [Parameter(Mandatory)]
        [object]$IpAddressOrCidrOrIpCalcResult,
        [Parameter(Mandatory)]
        [ValidateRange(0, 32)][int]$PrefixLength = $This.PrefixLength
    )
    switch ($IpAddressOrCidrOrIpCalcResult) {
        { $_.psobject.TypeNames[0] -eq $IpNetworkTypeName } {
            $Other = Get-IpNet -Cidr $_.CIDR
            break
        }
        { Test-IsValidCidr $_ } {
            $Other = Get-IpNet -Cidr $_
            break
        }
        { Test-IsValidIpAddress $_ } {
            $Other = Get-IpNet -IpAddress $_ -PrefixLength $PrefixLength
            break
        }
        Default {
            Throw "First argument in Overlaps method must be a valid IpAddress or CIDR or IpCalcResult object, not $($_.Gettype()): '$_'"
        }
    }
    $This.Contains($Other.Subnet) -or $This.Contains($Other.Broadcast) -or ($Other.Contains($This.Subnet) -or $Other.Contains($This.Broadcast))
}

$IsLocalMethod = {
    param ([Parameter(Mandatory)][IPAddress]$IP = $This.IPAddress)
    [bool](@(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred).Where({ (Get-IpNet -IPAddress $_.IPAddress -PrefixLength $_.PrefixLength).Contains($IP) }).Count)
}

$GetIpArrayMethod = {
    $snb1, $snb2, $snb3, $snb4 = $This.Subnet.GetAddressBytes()
    $bcb1, $bcb2, $bcb3, $bcb4 = $This.Broadcast.GetAddressBytes()
    $w = @($snb1..$bcb1)
    $x = @($snb2..$bcb2)
    $y = @($snb3..$bcb3)
    $z = @($snb4..$bcb4)
    $w | ForEach-Object { $wi = $_
        $x | ForEach-Object { $xi = $_
            $y | ForEach-Object { $yi = $_
                $z | ForEach-Object { $zi = $_; $wi, $xi, $yi, $zi -join '.' }
            }
        }
    }
}

$GetLocalRouteMethod = {
    param (
        [Parameter(Mandatory)][ValidateScript( { Test-IsValidIpaddress $_ })]
        [IPAddress]$IP = $This.IPAddress,

        [int]$Count = 1
    )
    @(Get-NetRoute -AddressFamily IPv4).Where({
        (Get-IpNet -CIDR $_.DestinationPrefix).Contains($IP)
        }) | Sort-Object -Property @{
        Expression = { (Get-IpNet -CIDR $_.DestinationPrefix).PrefixLength }
    } -Descending | Select-Object -First $Count
}

$ShiftMethod = {
    param(
        [Parameter()]
        [int]$Steps = 1
    )
    $This.Add($This.IPCount * $Steps)
}

$OverlapsWithMethod = {
    param(
        [Parameter()][ValidateScript({ Test-IsValidCidr $_ })]
        [string[]]$Subnets
    )
    $Subnets | Where-Object { $This.Overlaps($_) }
}

$DistanceFromMethod = {
    param(
        [Parameter()][ValidateScript({ Test-IsValidCidr $_ })]
        [string]$Cidr
    )
    if ($This.Cidr -eq $Cidr) { return 0 }
    if ($This.Overlaps($Cidr)) { return -1 }
    $other = Get-IpNet -CIDR $Cidr

    if ($This.Subnet.Decimal -lt $other.Subnet.Decimal) {
        return $other.Subnet.Decimal - $This.Broadcast.Decimal
    }
    else {
        return $This.Subnet.Decimal - $other.Broadcast.Decimal
    }
}

$FindFreeSubnetMethod = {
    param(
        [Parameter()]
        [string[]]$CIDRs = @()
    )
    $DebugPreference = 'Continue'


    $subnets = $CIDRs | Where-Object { Test-IsValidCidr $_ }
    Write-Debug "$(_@) Incoming subnets: $($CIDRs -join '; ')"

    $privateCidr = $This.PrivateNetwork

    if (-not $privateCidr) {
        Throw "FindFreeSubnet method only works with Private Networks Subnets. $($This.CIDR) is not part of any Private Network!"
    }

    $privateCidrNet = Get-IpNet -CIDR $privateCidr
    $gapSize = $This.IPCount
    Write-Debug "$(_@) Gap Size: $gapSize"

    $sortedSubnets = $subnets | Sort-Object { ($_ | Get-IpNet).IPAddress.Decimal }
    Write-Debug "$(_@) Sorted subnets: $($sortedSubnets -join '; ')"

    $edgedSubnets = @()
    $edgedSubnets += "$($privateCidrNet.Subnet)/32"
    if ($sortedSubnets) { $edgedSubnets += $sortedSubnets }
    $edgedSubnets += "$($privateCidrNet.Broadcast)/32"
    Write-Debug "$(_@) Edged subnets: $($edgedSubnets -join '; ')"

    $result = (1..($edgedSubnets.Count - 1)).ForEach({
            $ip, $pref = Get-CidrParts $edgedSubnets[$_]
            $pref = if ($pref -eq 32) { $pref } else { [Math]::Min($This.PrefixLength, $pref) }
            $net = Get-IpNet -CIDR "$ip/$pref"
            if ($net.PrivateNetwork -eq $privateCidr) {
                $prevIp, $prevPref = Get-CidrParts $edgedSubnets[$_ - 1]
                $prevPref = if ($prevPref -eq 32) { $prevPref } else { [Math]::Min($This.PrefixLength, $prevPref) }
                $prevNet = Get-IpNet -CIDR "$prevIp/$prevPref"
                $distance = $net.DistanceFrom($prevNet.Cidr)
                Write-Debug "$(_@) Distance = $distance between $prevNet and $net"
                if ($distance -ge $gapSize) {
                    Write-Debug "$(_@) Free subnet space: $distance is enough to fit target size: $gapSize"
                    $newSubnetStart = $prevNet.Broadcast.Add()
                    Write-Debug "$(_@) New subnet can start from: $newSubnetStart"
                    $out = (Get-IpNet -CIDR "$newSubnetStart/$($This.PrefixLength)").CIDR
                    Write-Debug "$(_@) Subnet: $This can be reallocated to: $out."
                    $out
                }
            }
        })
    $result | Select-Object -First 1
}
#endregion IPNetwork Methods

function Get-IpNet {
    <#
    .SYNOPSIS
        IP Calculator for calculation IP Subnet
    .EXAMPLE
        Get-IpNet -CIDR 192.168.0.0/24
        IP              : 192.168.0.0
        Mask            : 255.255.255.0
        PrefixLength    : 24
        WildCard        : 0.0.0.255
        IPCount         : 256
        Subnet          : 192.168.0.0
        Broadcast       : 192.168.0.255
        CIDR            : 192.168.0.0/24
        Decimal         : 3232235520
        Binary          : 11000000.10101000.00000000.00000000
        MaskBinary      : 11111111.11111111.11111111.00000000
        SubnetBinary    : 11000000.10101000.00000000.00000000
        BroadcastBinary : 11000000.10101000.00000000.11111111
    .EXAMPLE
        Get-IpNet -IPAddress 192.168.0.0 -Mask 255.255.255.0
        IP              : 192.168.0.0
        Mask            : 255.255.255.0
        PrefixLength    : 24
        WildCard        : 0.0.0.255
        IPCount         : 256
        Subnet          : 192.168.0.0
        Broadcast       : 192.168.0.255
        CIDR            : 192.168.0.0/24
        Decimal         : 3232235520
        Binary          : 11000000.10101000.00000000.00000000
        MaskBinary      : 11111111.11111111.11111111.00000000
        SubnetBinary    : 11000000.10101000.00000000.00000000
        BroadcastBinary : 11000000.10101000.00000000.11111111
    .EXAMPLE
        Get-IpNet -IPAddress 192.168.3.0 -PrefixLength 23
        IP              : 192.168.3.0
        Mask            : 255.255.254.0
        PrefixLength    : 23
        WildCard        : 0.0.1.255
        IPCount         : 512
        Subnet          : 192.168.2.0
        Broadcast       : 192.168.3.255
        CIDR            : 192.168.2.0/23
        Decimal         : 3232236288
        Binary          : 11000000.10101000.00000011.00000000
        MaskBinary      : 11111111.11111111.11111110.00000000
        SubnetBinary    : 11000000.10101000.00000010.00000000
        BroadcastBinary : 11000000.10101000.00000011.11111111
    .EXAMPLE
        (Get-IpNet -IPAddress (Get-IpNet 192.168.99.56/28).Subnet -PrefixLength 32).Add(1).IPAddress
        192.168.99.49
    .EXAMPLE
        (Get-IpNet 192.168.99.56/28).Contains('192.168.99.50')
        True
    .EXAMPLE
        (Get-IpNet 192.168.99.58/30).GetIPArray()
        192.168.99.56
        192.168.99.57
        192.168.99.58
        192.168.99.59

    .EXAMPLE
        Get-NetRoute -AddressFamily IPv4 | ? {(Get-IpNet -CIDR $_.DestinationPrefix).Contains('8.8.8.8')} | Sort-Object -Property @(@{Expression = {$_.DestinationPrefix.Split('/')[1]}; Asc = $false},'RouteMetric','ifMetric')

        ifIndex DestinationPrefix NextHop     RouteMetric ifMetric PolicyStore
        ------- ----------------- ----------- ----------- -------- -----------
        22              0.0.0.0/0 192.168.0.1           0       25 ActiveStore

    .EXAMPLE
        (Get-IpNet 0.0.0.0/0).GetLocalRoute('127.0.0.1')

        ifIndex DestinationPrefix NextHop RouteMetric ifMetric
        ------- ----------------- ------- ----------- --------
        1       127.0.0.1/32      0.0.0.0         256       75
    .EXAMPLE
        (Get-IpNet 0.0.0.0/0).GetLocalRoute('127.0.0.1',2)

        ifIndex DestinationPrefix NextHop RouteMetric ifMetric PolicyStore
        ------- ----------------- ------- ----------- -------- -----------
        1       127.0.0.1/32      0.0.0.0         256 75       ActiveStore
        1       127.0.0.0/8       0.0.0.0         256 75       ActiveStore

    .EXAMPLE
        (Get-IpNet 192.168.0.0/25).Overlaps('192.168.0.0/27')
        True
    .OUTPUTS
        Output PSCustomObject with PSTypeName = 'IPNetwork'
    .NOTES
        .VERSION 3.1.0
        .GUID cb059a0e-09b6-4756-8df4-28e997b9d97f
        .AUTHOR wikiped@ya.ru (refactor and enhancements)
        .ORIGINAL AUTHOR saw-friendship@yandex.ru
        .COMPANYNAME
        .COPYRIGHT
        .TAGS IP Subnet Calculator WildCard CIDR
        .LICENSEURI
        .PROJECTURI https://sawfriendship.wordpress.com/
        .ICONURI
        .EXTERNALMODULEDEPENDENCIES
        .REQUIREDSCRIPTS
        .EXTERNALSCRIPTDEPENDENCIES
        .RELEASENOTES
    #>
    [CmdletBinding(DefaultParameterSetName = 'CIDR')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'CIDR', ValueFromPipeline)]
        [ValidateScript({ Test-IsValidCidr $_ })]
        [Alias('DestinationPrefix')]
        [string]$CIDR,

        [parameter(ParameterSetName = 'Mask')]
        [parameter(ParameterSetName = 'PrefixLength', ValueFromPipelineByPropertyName)]
        [parameter(ParameterSetName = 'WildCard')]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [Alias('IP')]
        [IPAddress]$IPAddress,

        [Parameter(Mandatory, ParameterSetName = 'Mask')]
        [IPAddress]$Mask,

        [parameter(Mandatory, ParameterSetName = 'PrefixLength', ValueFromPipelineByPropertyName)]
        [ValidateRange(0, 32)]
        [int]$PrefixLength,

        [parameter(Mandatory, ParameterSetName = 'WildCard')]
        [IPAddress]$Wildcard
    )

    if ($CIDR) {
        [IPAddress]$IPAddress, [int]$PrefixLength = Get-CidrParts $CIDR
        [IPAddress]$Mask = ConvertFrom-PrefixLengthToMask $PrefixLength
    }
    if ($PrefixLength -and !$Mask) {
        [IPAddress]$Mask = ConvertFrom-PrefixLengthToMask $PrefixLength
    }
    if ($Wildcard) {
        [IPAddress]$Mask = $Wildcard.GetAddressBytes().ForEach({ 255 - $_ }) -join '.'
    }
    if (!$PrefixLength -and $Mask) {
        $PrefixLength = 32 - ($Mask.GetAddressBytes().ForEach({ [Math]::Log((256 - $_), 2) }) | Measure-Object -Sum).Sum
    }

    if ((($Mask.ToBinary()).TrimStart('1').Contains('1')) -and (!$Wildcard)) {
        Write-Error 'Invalid Mask. Is WildCard parameter missing?' -ea Stop
    }
    if (!$Wildcard) {
        [IPAddress]$Wildcard = $Mask.GetAddressBytes().ForEach({ 255 - $_ }) -join '.'
    }

    [IPAddress]$Subnet = $IPAddress.Address -band $Mask.Address
    [IPAddress]$Broadcast = Get-BroadcastFromSubnetAndWildcard $Subnet $Wildcard
    [int64]$IPCount = [Math]::Pow(2, 32 - $PrefixLength)

    $Object = [pscustomobject][ordered]@{
        IPAddress       = $IPAddress
        Mask            = $Mask
        PrefixLength    = $PrefixLength
        Wildcard        = $Wildcard
        IPCount         = $IPCount
        Subnet          = $Subnet
        Broadcast       = $Broadcast
        CIDR            = "$Subnet/$PrefixLength"
        Decimal         = $IPAddress.Decimal
        Binary          = $IPAddress.Binary
        MaskBinary      = $Mask.Binary
        SubnetBinary    = $Subnet.Binary
        BroadcastBinary = $Broadcast.Binary
        NetworkClass    = $IPAddress.NetworkClass
        PrivateNetwork  = $IPAddress.CidrPrivateNetwork
        PSTypeName      = $IpNetworkTypeName
    }

    Add-Member -InputObject $Object -MemberType AliasProperty -Name IP -Value IPAddress
    Add-Member -InputObject $Object -MemberType AliasProperty -Name Length -Value IPCount

    Add-Member -InputObject $Object -MemberType ScriptMethod -Name Add -Value $AddMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name Contains -Value $ContainsMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name Overlaps -Value $OverlapsMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name OverlapsWith -Value $OverlapsWithMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name GetIpArray -Value $GetIpArrayMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name IsLocal -Value $IsLocalMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name GetLocalRoute -Value $GetLocalRouteMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name Shift -Value $ShiftMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name DistanceFrom -Value $DistanceFromMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Name FindFreeSubnet -Value $FindFreeSubnetMethod
    Add-Member -InputObject $Object -MemberType ScriptMethod -Force -Name ToString -Value {
        $This.CIDR
    }

    [string[]]$DefaultProperties = @(
        'IPAddress'
        'PrefixLength'
        'CIDR'
        'Length'
        'Subnet'
        'Mask'
        'Wildcard'
        'Broadcast'
        'Decimal'
    )
    $PSPropertySet = New-Object -TypeName PSPropertySet -ArgumentList @('DefaultDisplayPropertySet', $DefaultProperties)

    $PSStandardMembers = [PSMemberInfo[]]$PSPropertySet

    Add-Member -InputObject $Object -MemberType MemberSet -Name PSStandardMembers -Value $PSStandardMembers

    $Object
}

$OriginalDebugPreference = $DebugPreference
$DebugPreference = 'SilentlyContinue'
$OriginalVerbosePreference = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

Export-ModuleMember -Function Get-IpNet
Export-ModuleMember -Function Test-IsValidCidr
Export-ModuleMember -Function Test-IsValidIpAddress
Export-ModuleMember -Function Get-CidrParts
Export-ModuleMember -Function ConvertFrom-DecimalToIpAddress

$DebugPreference = $OriginalDebugPreference
$VerbosePreference = $OriginalVerbosePreference
