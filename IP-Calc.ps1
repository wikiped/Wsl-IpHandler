<#PSScriptInfo
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

<#
.DESCRIPTION
IP Calculator for calculation IP Subnet
.EXAMPLE
IP-Calc -CIDR 192.168.0.0/24
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
IP-Calc -IPAddress 192.168.0.0 -Mask 255.255.255.0
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
IP-Calc -IPAddress 192.168.3.0 -PrefixLength 23
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
(IP-Calc -IPAddress (IP-Calc 192.168.99.56/28).Subnet -PrefixLength 32).Add(1).IPAddress
192.168.99.49
.EXAMPLE
(IP-Calc 192.168.99.56/28).Compare('192.168.99.50')
True
.EXAMPLE
(IP-Calc 192.168.99.58/30).GetIPArray()
192.168.99.56
192.168.99.57
192.168.99.58
192.168.99.59
.EXAMPLE
Get-NetRoute -AddressFamily IPv4 | ? {(IP-Calc -CIDR $_.DestinationPrefix).Compare('8.8.8.8')} | Sort-Object -Property @(@{Expression = {$_.DestinationPrefix.Split('/')[1]}; Asc = $false},'RouteMetric','ifMetric')

ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
------- -----------------                              -------                                  ----------- -------- -----------
22      0.0.0.0/0                                      192.168.0.1                                        0 25       ActiveStore


.EXAMPLE
(IP-Calc 0.0.0.0/0).GetLocalRoute('127.0.0.1')

ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
------- -----------------                              -------                                  ----------- -------- -----------
1       127.0.0.0/8                                    0.0.0.0                                          256 75       ActiveStore
.EXAMPLE
(IP-Calc 0.0.0.0/0).GetLocalRoute('127.0.0.1',2)

ifIndex DestinationPrefix                              NextHop                                  RouteMetric ifMetric PolicyStore
------- -----------------                              -------                                  ----------- -------- -----------
1       127.0.0.1/32                                   0.0.0.0                                          256 75       ActiveStore
1       127.0.0.0/8                                    0.0.0.0                                          256 75       ActiveStore

.EXAMPLE
(IP-Calc 192.168.0.0/25).Overlaps('192.168.0.0/27')
True

#>
[CmdletBinding(DefaultParameterSetName='CIDR')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='CIDR',ValueFromPipelineByPropertyName=$true,Position=0)]
        [ValidateScript({$Array = ($_ -split '\\|\/'); ($Array[0] -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and [string[]](0..32) -contains $Array[1]})]
        [Alias('DestinationPrefix')]
        [string]$CIDR,
    [parameter(ParameterSetName='Mask')][parameter(ParameterSetName=('PrefixLength'),ValueFromPipelineByPropertyName=$true)][parameter(ParameterSetName=('WildCard'))]
        [ValidateScript({($_ -as [IPAddress]).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork})]
		[Alias('IP')]
        [IPAddress]$IPAddress,
    [Parameter(Mandatory=$true,ParameterSetName='Mask')]
        [IPAddress]$Mask,
    [parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='PrefixLength')]
        [ValidateRange(0,32)]
        [int]$PrefixLength,
    [parameter(Mandatory=$true,ParameterSetName='WildCard')]
        [IPAddress]$WildCard
)

if($CIDR){
    [IPAddress]$IPAddress = ($CIDR -split '\\|\/')[0]
    [int]$PrefixLength = ($CIDR -split '\\|\/')[1]
    [IPAddress]$Mask = [IPAddress]([string](4gb-([System.Math]::Pow(2,(32-$PrefixLength)))))
}
if($PrefixLength -and !$Mask){
    [IPAddress]$Mask = [IPAddress]([string](4gb-([System.Math]::Pow(2,(32-$PrefixLength)))))
}
if($WildCard){
    [IPAddress]$Mask = $WildCard.GetAddressBytes().ForEach({255 - $_}) -join '.'
}
if(!$PrefixLength -and $Mask){
    $PrefixLength = 32 - ($Mask.GetAddressBytes().ForEach({[System.Math]::Log((256-$_),2)}) | Measure-Object -Sum).Sum
}

[int[]]$SplitIPAddress = $IPAddress.GetAddressBytes()
[int64]$ToDecimal = $SplitIPAddress[0]*16mb + $SplitIPAddress[1]*64kb + $SplitIPAddress[2]*256 + $SplitIPAddress[3]

[int[]]$SplitMask = $Mask.GetAddressBytes()
$IPBin = ($SplitIPAddress.ForEach({[System.Convert]::ToString($_,2).PadLeft(8,'0')})) -join '.'
$MaskBin = ($SplitMask.ForEach({[System.Convert]::ToString($_,2).PadLeft(8,'0')})) -join '.'

if((($MaskBin -replace '\.').TrimStart('1').Contains('1')) -and (!$WildCard)){
    Write-Warning 'Mask Length error, you can try put WildCard'; break
}
if(!$WildCard){
    [IPAddress]$WildCard = $SplitMask.ForEach({255 - $_}) -join '.'
}
if($WildCard){
    [int[]]$SplitWildCard = $WildCard.GetAddressBytes()
}

[IPAddress]$Subnet = $IPAddress.Address -band $Mask.Address
[int[]]$SplitSubnet = $Subnet.GetAddressBytes()
[string]$SubnetBin = $SplitSubnet.ForEach({[System.Convert]::ToString($_,2).PadLeft(8,'0')}) -join '.'
[IPAddress]$Broadcast = @(0..3).ForEach({[int]($SplitSubnet[$_]) + [int]($SplitWildCard[$_])}) -join '.'
[int[]]$SplitBroadcast = $Broadcast.GetAddressBytes()
[string]$BroadcastBin = $SplitBroadcast.ForEach({[System.Convert]::ToString($_,2).PadLeft(8,'0')}) -join '.'
[string]$CIDR = "$($Subnet.IPAddressToString)/$PrefixLength"
[int64]$IPcount = [System.Math]::Pow(2,$(32 - $PrefixLength))

$Object = [pscustomobject][ordered]@{
    IPAddress = $IPAddress.IPAddressToString
    Mask = $Mask.IPAddressToString
    PrefixLength = $PrefixLength
    WildCard = $WildCard.IPAddressToString
    IPcount = $IPcount
    Subnet = $Subnet
    Broadcast = $Broadcast
    CIDR = $CIDR
    ToDecimal = $ToDecimal
    IPBin = $IPBin
    MaskBin = $MaskBin
    SubnetBin = $SubnetBin
    BroadcastBin = $BroadcastBin
    PSTypeName = 'NetWork.IPCalcResult'
}

[string[]]$DefaultProperties = @('IPAddress','Mask','PrefixLength','WildCard','Subnet','Broadcast','CIDR','ToDecimal')

Add-Member -InputObject $Object -MemberType AliasProperty -Name IP -Value IPAddress

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Add -Value {
    param([int]$Add,[int]$PrefixLength = $This.PrefixLength)
    IP-Calc -IPAddress ([IPAddress]([String]$($This.ToDecimal + $Add))).IPAddressToString -PrefixLength $PrefixLength
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Compare -Value {
    param ([Parameter(Mandatory=$true)][IPAddress]$IP)
    $IPBin = -join (($IP)).GetAddressBytes().ForEach({[System.Convert]::ToString($_,2).PadLeft(8,'0')})
    $SubnetBin = $This.SubnetBin.Replace('.','')
    for ($i = 0; $i -lt $This.PrefixLength; $i += 1) {if ($IPBin[$i] -ne $SubnetBin[$i]) {return $false}}
    return $true
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name Overlaps -Value {
	param ([Parameter(Mandatory=$true)][string]$CIDR = $This.CIDR)
	$Calc = IP-Calc -Cidr $CIDR
	$This.Compare($Calc.Subnet) -or $This.Compare($Calc.Broadcast)
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name GetIParray -Value {
    $w = @($This.Subnet.GetAddressBytes()[0]..$This.Broadcast.GetAddressBytes()[0])
    $x = @($This.Subnet.GetAddressBytes()[1]..$This.Broadcast.GetAddressBytes()[1])
    $y = @($This.Subnet.GetAddressBytes()[2]..$This.Broadcast.GetAddressBytes()[2])
    $z = @($This.Subnet.GetAddressBytes()[3]..$This.Broadcast.GetAddressBytes()[3])
    $w.ForEach({$wi = $_; $x.ForEach({$xi = $_; $y.ForEach({$yi = $_; $z.ForEach({$zi = $_; $wi,$xi,$yi,$zi -join '.'})})})})
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name isLocal -Value {
	param ([Parameter(Mandatory=$true)][IPAddress]$IP = $This.IPAddress)
	[bool](@(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred).Where({(IP-Calc -IPAddress $_.IPAddress -PrefixLength $_.PrefixLength).Compare($IP)}).Count)
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Name GetLocalRoute -Value {
	param ([Parameter(Mandatory=$true)][IPAddress]$IP = $This.IPAddress,[int]$Count = 1)
	@(Get-NetRoute -AddressFamily IPv4).Where({(IP-Calc -CIDR $_.DestinationPrefix).Compare($IP)}) | Sort-Object -Property @{Expression = {(IP-Calc -CIDR $_.DestinationPrefix).PrefixLength}} -Descending | Select-Object -First $Count
}

Add-Member -InputObject $Object -MemberType:ScriptMethod -Force -Name ToString -Value {
    $This.CIDR
}

$PSPropertySet = New-Object -TypeName System.Management.Automation.PSPropertySet -ArgumentList @('DefaultDisplayPropertySet',$DefaultProperties)
$PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]$PSPropertySet
Add-Member -InputObject $Object -MemberType MemberSet -Name PSStandardMembers -Value $PSStandardMembers

$Object
