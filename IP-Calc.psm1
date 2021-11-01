using namespace System.Net.Sockets
using namespace System.Management.Automation

Set-StrictMode -Version Latest

$IpCalcTypeName = 'IpCalcResult'

#region Functions
Function Get-CidrParts {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()][ValidateNotNull()]
        [array]$Cidr
    )
    $array = @($input)
    if ($array.Count) { $Cidr = $array }
    if (!(Test-Path variable:Cidr)) { $Cidr = @() }
    $Cidr | ForEach-Object {
        $CIDR -split '\\|\/' | Select-Object -First 2
    }
}

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
        [ValidateNotNull()]
        [array]$Cidr
    )
    $array = @($input)
    if ($array.Count) { $Cidr = $array }
    if (!(Test-Path variable:Cidr)) { $Cidr = @() }
    $Cidr | ForEach-Object {
        if ($_ -is [string]) {
            try {
                $ipAddress, $prefixLength = Get-CidrParts $_
                (Test-IsValidIpAddress $ipAddress) -and [string[]](0..32) -contains $prefixLength
            }
            catch { $false }
        }
        else { $false }
    }
}

Function ConvertFrom-IpAddressToDecimal {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [ipaddress[]]$IpAddress
    )
    $array = @($input)
    if ($array.Count) { $IpAddress = $array }
    if (!(Test-Path variable:IpAddress)) { $IpAddress = @() }
    $IpAddress | ForEach-Object {
        [int]$b1, [int]$b2, [int]$b3, [int]$b4 = $IPAddress.GetAddressBytes()
        [int64]($b1 * 16mb + $b2 * 64kb + $b3 * 256 + $b4)
    }
}

Function ConvertFrom-IpAddressToBinaryString {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
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
        [ValidateNotNull()]
        [int[]]$PrefixLength
    )
    $array = @($input)
    if ($array.Count) { $PrefixLength = $array }
    if (!(Test-Path variable:PrefixLength)) { $PrefixLength = @() }
    $PrefixLength | ForEach-Object {
        [IPAddress]([string](4gb - ([System.Math]::Pow(2, (32 - $_)))))
    }
}

Function Get-BroadcastFromIpAddress {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
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
#endregion Functions

#region Methods
$AddMethod = {
    param(
        [int]$Add,
        [int]$PrefixLength = $This.PrefixLength
    )
    Get-IpCalcResult `
        -IPAddress ([IPAddress]([String]($This.ToDecimal + $Add))).IPAddressToString `
        -PrefixLength $PrefixLength
}

$CompareMethod = {
    param ([Parameter(Mandatory)][IPAddress]$IP)
    $IPBin = ConvertFrom-IpAddressToBinaryString $IP -Separator ''
    $SubnetBin = ConvertFrom-IpAddressToBinaryString $This.Subnet -Separator ''
    for ($i = 0; $i -lt $This.PrefixLength; $i += 1) {
        if ($IPBin[$i] -ne $SubnetBin[$i]) { return $false }
    }
    $true
}

$ContainsMethod = {
    param (
        [Parameter(Mandatory)]
        [object]$IpAddressOrCidrOrIpCalcResult
    )
    switch ($IpAddressOrCidrOrIpCalcResult) {
        { $_.psobject.TypeNames[0] -eq $IpCalcTypeName } {
            $Other = $_
            break
        }
        { Test-IsValidCidr $_ } {
            $Other = Get-IpCalcResult -Cidr $_
            break
        }
        { Test-IsValidIpAddress $_ } {
            $Other = Get-IpCalcResult -IpAddress $_ -PrefixLength 32
            break
        }
        Default {
            Throw "First argument in Contains method must be a valid IpAddress or CIDR or IpCalcResult object, not $($_.Gettype()): '$_'"
        }
    }
    (ConvertFrom-IpAddressToDecimal $This.Subnet) -le (ConvertFrom-IpAddressToDecimal $Other.Subnet) -and (ConvertFrom-IpAddressToDecimal $This.Broadcast) -ge (ConvertFrom-IpAddressToDecimal $Other.Broadcast)
}

$OverlapsMethod = {
    param (
        [Parameter(Mandatory)]
        [object]$IpAddressOrCidrOrIpCalcResult,
        [Parameter(Mandatory)]
        [int]$PrefixLength = $This.PrefixLength
    )
    switch ($IpAddressOrCidrOrIpCalcResult) {
        { $_.psobject.TypeNames[0] -eq $IpCalcTypeName } {
            $Other = Get-IpCalcResult -Cidr $_.CIDR
            break
        }
        { Test-IsValidCidr $_ } {
            $Other = Get-IpCalcResult -Cidr $_
            break
        }
        { Test-IsValidIpAddress $_ } {
            $Other = Get-IpCalcResult -IpAddress $_ -PrefixLength $PrefixLength
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
    [bool](@(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred).Where({ (Get-IpCalcResult -IPAddress $_.IPAddress -PrefixLength $_.PrefixLength).Compare($IP) }).Count)
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
        [Parameter(Mandatory)][IPAddress]$IP = $This.IPAddress,
        [int]$Count = 1
    )
    @(Get-NetRoute -AddressFamily IPv4).Where({
        (Get-IpCalcResult -CIDR $_.DestinationPrefix).Compare($IP)
        }) | Sort-Object -Property @{
        Expression = { (Get-IpCalcResult -CIDR $_.DestinationPrefix).PrefixLength }
    } -Descending | Select-Object -First $Count
}
#endregion Methods

function Get-IpCalcResult {
    <#
    .SYNOPSIS
        IP Calculator for calculation IP Subnet
    .EXAMPLE
        Get-IpCalcResult -CIDR 192.168.0.0/24
        IP           : 192.168.0.0
        Mask         : 255.255.255.0
        PrefixLength : 24
        WildCard     : 0.0.0.255
        IPcount      : 256
        Subnet       : 192.168.0.0
        Broadcast    : 192.168.0.255
        CIDR         : 192.168.0.0/24
        ToDecimal    : 3232235520
        IPBin        : 11000000.10101000.00000000.00000000
        MaskBin      : 11111111.11111111.11111111.00000000
        SubnetBin    : 11000000.10101000.00000000.00000000
        BroadcastBin : 11000000.10101000.00000000.11111111
    .EXAMPLE
        Get-IpCalcResult -IPAddress 192.168.0.0 -Mask 255.255.255.0
        IP           : 192.168.0.0
        Mask         : 255.255.255.0
        PrefixLength : 24
        WildCard     : 0.0.0.255
        IPcount      : 256
        Subnet       : 192.168.0.0
        Broadcast    : 192.168.0.255
        CIDR         : 192.168.0.0/24
        ToDecimal    : 3232235520
        IPBin        : 11000000.10101000.00000000.00000000
        MaskBin      : 11111111.11111111.11111111.00000000
        SubnetBin    : 11000000.10101000.00000000.00000000
        BroadcastBin : 11000000.10101000.00000000.11111111
    .EXAMPLE
        Get-IpCalcResult -IPAddress 192.168.3.0 -PrefixLength 23
        IP           : 192.168.3.0
        Mask         : 255.255.254.0
        PrefixLength : 23
        WildCard     : 0.0.1.255
        IPcount      : 512
        Subnet       : 192.168.2.0
        Broadcast    : 192.168.3.255
        CIDR         : 192.168.2.0/23
        ToDecimal    : 3232236288
        IPBin        : 11000000.10101000.00000011.00000000
        MaskBin      : 11111111.11111111.11111110.00000000
        SubnetBin    : 11000000.10101000.00000010.00000000
        BroadcastBin : 11000000.10101000.00000011.11111111
    .EXAMPLE
        (Get-IpCalcResult -IPAddress (Get-IpCalcResult 192.168.99.56/28).Subnet -PrefixLength 32).Add(1).IPAddress
        192.168.99.49
    .EXAMPLE
        (Get-IpCalcResult 192.168.99.56/28).Compare('192.168.99.50')
        True
    .EXAMPLE
        (Get-IpCalcResult 192.168.99.58/30).GetIPArray()
        192.168.99.56
        192.168.99.57
        192.168.99.58
        192.168.99.59
    .EXAMPLE
        Get-NetRoute -AddressFamily IPv4 | ? {(Get-IpCalcResult -CIDR $_.DestinationPrefix).Compare('8.8.8.8')} | Sort-Object -Property @(@{Expression = {$_.DestinationPrefix.Split('/')[1]}; Asc = $false},'RouteMetric','ifMetric')

        ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
        ------- -----------------                              -------                                  ----------- -------- -----------
        22      0.0.0.0/0                                      192.168.0.1                                        0 25       ActiveStore


    .EXAMPLE
        (Get-IpCalcResult 0.0.0.0/0).GetLocalRoute('127.0.0.1')

        ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
        ------- -----------------                              -------                                  ----------- -------- -----------
        1       127.0.0.0/8                                    0.0.0.0                                          256 75       ActiveStore
    .EXAMPLE
        (Get-IpCalcResult 0.0.0.0/0).GetLocalRoute('127.0.0.1',2)

        ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
        ------- -----------------                              -------                                  ----------- -------- -----------
        1       127.0.0.1/32                                   0.0.0.0                                          256 75       ActiveStore
        1       127.0.0.0/8                                    0.0.0.0                                          256 75       ActiveStore

    .EXAMPLE
        (Get-IpCalcResult 192.168.0.0/25).Overlaps('192.168.0.0/27')
        True
    .OUTPUTS
        Output PSCustomObject with PSTypeName = 'NetWork.IPCalcResult'
    .NOTES
        .VERSION 3.1.0
        .GUID cb059a0e-09b6-4756-8df4-28e997b9d97f
        .AUTHOR saw-friendship@yandex.ru
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
        [Parameter(Mandatory, ParameterSetName = 'CIDR', ValueFromPipelineByPropertyName = $true, Position = 0)]
        [ValidateScript({ Test-IsValidCidr $_ })]
        [Alias('DestinationPrefix')]
        [string]$CIDR,

        [parameter(ParameterSetName = 'Mask')]
        [parameter(ParameterSetName = 'PrefixLength', ValueFromPipelineByPropertyName = $true)]
        [parameter(ParameterSetName = 'WildCard')]
        [ValidateScript({ Test-IsValidIpAddress $_ })]
        [Alias('IP')]
        [IPAddress]$IPAddress,

        [Parameter(Mandatory, ParameterSetName = 'Mask')]
        [IPAddress]$Mask,

        [parameter(Mandatory, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'PrefixLength')]
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
        $PrefixLength = 32 - ($Mask.GetAddressBytes().ForEach({ [System.Math]::Log((256 - $_), 2) }) | Measure-Object -Sum).Sum
    }

    [int64]$Decimal = ConvertFrom-IpAddressToDecimal $IPAddress

    $IPBin = ConvertFrom-IpAddressToBinaryString $IPAddress
    $MaskBin = ConvertFrom-IpAddressToBinaryString $Mask

    if ((($MaskBin -replace '\.').TrimStart('1').Contains('1')) -and (!$Wildcard)) {
        Write-Error 'Invalid Mask. Is WildCard parameter missing?' -ea Stop
    }
    if (!$Wildcard) {
        [IPAddress]$Wildcard = $Mask.GetAddressBytes().ForEach({ 255 - $_ }) -join '.'
    }

    [IPAddress]$Subnet = $IPAddress.Address -band $Mask.Address
    [string]$SubnetBin = ConvertFrom-IpAddressToBinaryString $Subnet
    [IPAddress]$Broadcast = Get-BroadcastFromIpAddress $Subnet $Wildcard
    [string]$BroadcastBin = ConvertFrom-IpAddressToBinaryString $Broadcast
    [string]$CIDR = "$($Subnet.IPAddressToString)/$PrefixLength"
    [int64]$IPcount = [System.Math]::Pow(2, $(32 - $PrefixLength))

    $Object = [pscustomobject][ordered]@{
        IPAddress    = $IPAddress.IPAddressToString
        Mask         = $Mask.IPAddressToString
        PrefixLength = $PrefixLength
        Wildcard     = $Wildcard.IPAddressToString
        IPcount      = $IPcount
        Subnet       = $Subnet
        Broadcast    = $Broadcast
        CIDR         = $CIDR
        Decimal      = $Decimal
        IPBin        = $IPBin
        MaskBin      = $MaskBin
        SubnetBin    = $SubnetBin
        BroadcastBin = $BroadcastBin
        PSTypeName   = $IpCalcTypeName
    }

    Add-Member -InputObject $Object -MemberType AliasProperty -Name IP -Value IPAddress

    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Add -Value $AddMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Compare -Value $CompareMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Contains -Value $ContainsMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Overlaps -Value $OverlapsMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name GetIpArray -Value $GetIpArrayMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name IsLocal -Value $IsLocalMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Name GetLocalRoute -Value $GetLocalRouteMethod
    Add-Member -InputObject $Object -MemberType:ScriptMethod -Force -Name ToString -Value {
        $This.CIDR
    }

    [string[]]$DefaultProperties = @('IPAddress', 'Mask', 'PrefixLength', 'Wildcard', 'Subnet', 'Broadcast', 'CIDR', 'Decimal')
    $PSPropertySet = New-Object -TypeName PSPropertySet -ArgumentList @('DefaultDisplayPropertySet', $DefaultProperties)
    $PSStandardMembers = [PSMemberInfo[]]$PSPropertySet
    Add-Member -InputObject $Object -MemberType MemberSet -Name PSStandardMembers -Value $PSStandardMembers

    $Object
}

$DebugPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
Export-ModuleMember -Function Get-IpCalcResult
Export-ModuleMember -Function Test-IsValidCidr
Export-ModuleMember -Function Test-IsValidIpAddress
