#region Global Initialize
function Get-HnsClientNativeMethods() {
    $signature = @'
        // Networks

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnEnumerateNetworks(
            [MarshalAs(UnmanagedType.LPWStr)]
            string Query,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Networks,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnCreateNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Settings,
            [MarshalAs(UnmanagedType.SysUInt)]
            out IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnOpenNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.SysUInt)]
            out IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnModifyNetwork(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Settings,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnQueryNetworkProperties(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Query,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Properties,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnDeleteNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);

        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnCloseNetwork(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network);
'@

    # Compile into runtime type
    Add-Type -MemberDefinition $signature -Namespace ComputeNetwork.HNS.PrivatePInvoke -Name NativeMethods -PassThru
}

$OriginalDebugPreference = $DebugPreference
$OriginalVerbosePreference = $VerbosePreference
$DebugPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

Add-Type -TypeDefinition @'
    public enum ModifyRequestType
    {
        Add,
        Remove,
        Update,
        Refresh
    };

    public enum EndpointResourceType
    {
        Port,
        Policy,
    };
    public enum NetworkResourceType
    {
        DNS,
        Extension,
        Policy,
        Subnet,
        Subnets,
        IPSubnet
    };
    public enum NamespaceResourceType
    {
    Container,
    Endpoint,
    };
'@ -Verbose:$false -Debug:$false

$ClientNativeMethods = Get-HnsClientNativeMethods

$DebugPreference = $OriginalDebugPreference
$VerbosePreference = $OriginalVerbosePreference

$NetworkNativeMethods = @{
    Enumerate = $ClientNativeMethods::HcnEnumerateNetworks
    Create    = $ClientNativeMethods::HcnCreateNetwork
    Open      = $ClientNativeMethods::HcnOpenNetwork
    Modify    = $ClientNativeMethods::HcnModifyNetwork
    Query     = $ClientNativeMethods::HcnQueryNetworkProperties
    Delete    = $ClientNativeMethods::HcnDeleteNetwork
    Close     = $ClientNativeMethods::HcnCloseNetwork
}

function Get-ClientNativeMethod {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [hashtable]$NativeMethods = $NetworkNativeMethods
    )
    if ($NativeMethods.ContainsKey($Name)) {
        Write-Debug "$($MyInvocation.MyCommand.Name): Found key: '$Name'"
        $NativeMethods[$Name]
    }
    else {
        Throw "Method '$Name' cannot be found. Available methods: $($NativeMethods.Keys -join ', ')"
    }
}
#endregion Global Initialize

#region Network
function New-HnsNetworkEx {
    param(
        [Parameter(Mandatory, ParameterSetName = 'Id+Json')]
        [Parameter(Mandatory, ParameterSetName = 'Id+Params')]
        [ValidateScript( { $_ -ne [Guid]::Empty } )]
        [Guid]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Id+Params')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Params')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Json')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'Id+Params')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Params')]
        [string]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [string]$AddressPrefix,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [string]$DNSServerList,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [int]$Flags,

        [Parameter(Mandatory, ParameterSetName = 'Id+Json')][Parameter(Mandatory, ParameterSetName = 'Name+Json')]
        [string]$SettingsJsonString
    )
    switch -wildcard ($PSCmdlet.ParameterSetName) {
        '*Params' {
            $params = @{ }
            if ($Name) { $params.Name = $Name }
            if ($GatewayIpAddress) { $params.GatewayIpAddress = $GatewayIpAddress }
            if ($AddressPrefix) { $params.AddressPrefix = $AddressPrefix }
            if ($DNSServerList) { $params.DNSServerList = $DNSServerList }
            if ($Flags) { $params.Flags = $Flags }
            $settings = New-HnsNetworkSettings @params
        }
        '*Json' { $settings = $SettingsJsonString }
        'Name*' { $Id = Get-HnsNetworkId -Name $Name -ThrowIfNotFound }
    }
    $handle = Invoke-HcnCreateNetwork -Id $id -SettingsJsonString $settings -KeepHandleOpen
    Invoke-HcnQueryNetworkProperties -HcnNetworkHandle $handle
}

function Get-HnsNetworkEx {
    [CmdletBinding(DefaultParameterSetName = 'Id')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Id', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript( { $_ | ForEach-Object { $_ -ne [Guid]::Empty } })]
        [Guid[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [switch]$Detailed,

        [Parameter()]
        [int]$Version
    )
    $fn = $MyInvocation.MyCommand.Name

    $array = @($input)
    if ($array.Count) { $Id = $array }
    if (!(Test-Path variable:Id)) { $Id = @() }
    Write-Debug "${fn}: Id initial: $Id"

    [guid[]]$Id = ($Id | Where-Object { $_ -ne [Guid]::Empty } )

    Write-Debug "${fn}: Id after removing [Guid]::Empty: $Id"

    if (-not $Id) {
        $Id = Get-HnsNetworkId -Name $Name -Version $Version
        if (-not $Id) { $Id = @() }
        Write-Debug "${fn}: Id after Name + Filter: $Id"
    }
    Write-Debug "${fn}: Id final: $Id"

    $query = Get-HnsSchemaVersion -Version $Version

    if ($Detailed) { $query += @{Flags = 1 } }

    $jsonQuery = ConvertTo-Json $query -Depth 32
    Write-Debug "${fn}: jsonQuery:`n$jsonQuery"

    $output = [pscustomobject]@()

    $Id | ForEach-Object {
        $handle = Invoke-HcnOpenNetwork -Id $_
        $output += Invoke-HcnQueryNetworkProperties -HcnNetworkHandle $handle -QueryJsonString $jsonQuery
    }

    $output
}

function Remove-HnsNetworkEx {
    [CmdletBinding(DefaultParameterSetName = 'Id')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Id', ValueFromPipeline)]
        [AllowEmptyCollection()]
        [ValidateScript( { $_ -ne [Guid]::Empty } )]
        [Guid[]]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [string]$Name
    )
    $fn = $MyInvocation.MyCommand.Name

    $array = @($input)
    if ($array.Count) { $Id = $array }
    if (!(Test-Path variable:Id)) { $Id = @() }
    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        $Id = @(Get-HnsNetworkId -Name $Name -ThrowIfNotFound)
        Write-Debug "${fn}: Found Id for '$Name': $Id"
        if ($Id.Count -gt 1) {
            Throw "$($MyInvocation.MyCommand.Name) Expected 1 ID for '$Name', but found $($Id.Count): $Id"
        }
    }
    $Id | ForEach-Object {
        Invoke-HcnDeleteNetwork -Id $_
    }
}

function Set-HnsNetworkEx {
    param(
        [Parameter(Mandatory, ParameterSetName = 'Id+Json')]
        [Parameter(Mandatory, ParameterSetName = 'Id+Params')]
        [ValidateScript( { $_ -ne [Guid]::Empty } )]
        [Guid]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Name+Params')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Json')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'Id+Params')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Params')]
        [string]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [string]$AddressPrefix,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [string]$DNSServerList,

        [Parameter(ParameterSetName = 'Id+Params')]
        [Parameter(ParameterSetName = 'Name+Params')]
        [int]$Flags,

        [Parameter(Mandatory, ParameterSetName = 'Id+Json')]
        [Parameter(Mandatory, ParameterSetName = 'Name+Json')]
        [string]$SettingsJsonString
    )
    $fn = $MyInvocation.MyCommand.Name

    switch -wildcard ($PSCmdlet.ParameterSetName) {
        'Name*' { $Id = Get-HnsNetworkId -Name $Name -ThrowIfNotFound }
        '*Json' { $settings = $SettingsJsonString }
        '*Params' {
            # $params = @{}
            # if ($Name) { $params.Name = $Name }
            # if ($GatewayIpAddress) { $params.GatewayIpAddress = $GatewayIpAddress }
            # if ($AddressPrefix) { $params.AddressPrefix = $AddressPrefix }
            # if ($DNSServerList) { $params.DNSServerList = $DNSServerList }
            # if ($Flags) { $params.Flags = $Flags }
            # Write-Debug "${fn}: Settings to be modified: $($params | Out-String)"
            $newSettings = New-HnsNetworkSettings -Name $Name -GatewayIpAddress $GatewayIpAddress -AddressPrefix $AddressPrefix -DNSServerList $DNSServerList -Flags $Flags
            $settings = Set-HnsNetworkSettings -Id $Id -Settings $newSettings -Json
        }
    }
    # Invoke-HcnModifyNetwork DOES NOT Work throwing:
    # 'The specified request is unsupported. HRESULT=2151350293'
    # $handle = Invoke-HcnOpenNetwork -Id $Id
    # Invoke-HcnModifyNetwork -HcnNetworkHandle $handle -SettingsJsonString $settings -KeepHandleOpen
    Invoke-HcnDeleteNetwork -Id $Id
    Write-Debug "${fn}: Deleted Adapter with ID: $Id"
    Write-Debug "${fn}: New Setting to create Adapter with ID: '$Id':`n$settings"
    $handle = Invoke-HcnCreateNetwork -Id $Id -SettingsJsonString $settings -KeepHandleOpen
    Invoke-HcnQueryNetworkProperties -HcnNetworkHandle $handle
}

function Get-HnsNetworkId {
    param (
        [Parameter()]
        # [ValidateSet('WSL', 'Default Switch', 'External Switch')]
        [string]$Name,

        [Parameter()]
        [switch]$ThrowIfNotFound,

        [int]$Version = 1
    )
    switch ($Name) {
        'WSL' { return 'b95d0c5e-57d4-412b-b571-18a81a16e005' }
        'Default Switch' { return 'c08cb7b8-9b3c-408e-8e30-5e16a3aeb444' }
        'External Switch' { return '03c876a3-4c5b-40a6-98f4-a4c9a1855fd1' }
        Default {
            Write-Debug "$($MyInvocation.MyCommand.Name) did not find ID for '$Name'."
            Get-HnsNetworkIdEx -Name $Name -ThrowIfNotFound:$ThrowIfNotFound -Version $Version
        }
    }
}

function Get-HnsNetworkIdEx {
    param (
        [Parameter()]
        [string]$Name,

        [Parameter()]
        [Hashtable]$Filter = @{},

        [Parameter()]
        [switch]$ThrowIfNotFound,

        [Parameter()]
        [int]$Version = 1
    )
    $fn = $MyInvocation.MyCommand.Name

    if ($Name) { $Filter.Name = $Name }

    $query = Get-HnsSchemaVersion -Version $Version

    $FilterString = ConvertTo-Json $Filter -Depth 32

    if ($Filter.Count) { $query.Filter = $FilterString }
    Write-Debug "${fn}: Query: $($query | Out-String)"

    $jsonQuery = ConvertTo-Json $query -Depth 32
    Write-Debug "${fn}: Json Query:`n$jsonQuery"

    $ids = Invoke-HcnEnumerateNetworks -QueryJsonString $jsonQuery
    Write-Debug "${fn}: IDs: $ids"

    if ($ids) {
        $ids
    }
    else {
        if ($ThrowIfNotFound) {
            if ($Name) {
                $errorMsg = "ID cannot be found for Hyper-V Network Adapter: '$Name'"
            }
            else {
                $errorMsg = 'Hyper-V Network Adapters not found'
            }
            Throw "$errorMsg in $($MyInvocation.MyCommand.Name)."
        }
        else {
            @()
        }
    }
}

function Get-HnsNetworkSubnets {
    param (
        [Parameter()]
        [string]$HnsNetworkName
    )
    $params = @{}
    if ($HnsNetworkName) {
        $params.Id = Get-HnsNetworkId -HnsNetworkName $HnsNetworkName
    }
    Get-HnsNetworkEx @params |
        Select-Object -Property ID, Name, Subnets |
        ForEach-Object {
            $Id = $_.ID;
            $Name = $_.Name;
            $_.Subnets |
                Where-Object { -Not [string]::IsNullOrWhiteSpace($_.AddressPrefix) } |
                ForEach-Object {
                    [PSCustomObject]@{Id = $Id; Name = $Name; AddressPrefix = $_.AddressPrefix }
                }
            }
}
#endregion Network

#region Generic
function Invoke-HcnEnumerateNetworks {
    param (
        [Parameter()]
        [string]$QueryJsonString,

        [Parameter()]
        $EnumerateMethod = (Get-ClientNativeMethod Enumerate)
    )
    $fn = $MyInvocation.MyCommand.Name
    if (-not $QueryJsonString) {
        $QueryJsonString = Get-HnsSchemaVersion -Json
    }
    if (-not $EnumerateMethod) { Throw "${fn}: Parameter EnumerateMethod cannot be `$null!" }
    $ids = ''
    $result = ''
    Write-Debug "${fn}: QueryJsonString:`n$QueryJsonString"
    $hr = $EnumerateMethod.Invoke($QueryJsonString, [ref]$ids, [ref]$result)
    ReportErrorsEx -FunctionName $EnumerateMethod.Name -Hr $hr -Result $result -ThrowOnFail

    if ($ids) { $ids | ConvertFrom-Json } else { @() }
}

function Invoke-HcnCreateNetwork {
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty })]
        [Guid]$Id,

        [Parameter(Mandatory)]
        [string]$SettingsJsonString,

        [Parameter()]
        [switch]$KeepHandleOpen,

        [Parameter()]
        $CreateMethod = (Get-ClientNativeMethod Create)
    )
    $handle = 0
    $result = ''
    $hr = $createMethod.Invoke($Id, $SettingsJsonString, [ref]$handle, [ref]$result)
    ReportErrorsEx -FunctionName $createMethod.Name -Hr $hr -Result $result -ThrowOnFail

    if ($KeepHandleOpen) {
        $handle
    }
    else {
        Invoke-HcnCloseNetwork $handle
    }
}

function Invoke-HcnOpenNetwork {
    [OutputType([System.IntPtr])]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty })]
        [Guid]$Id,

        [Parameter()]
        $OpenMethod = (Get-ClientNativeMethod Open)
    )
    $handle = 0
    $result = ''
    $hr = $openMethod.Invoke($Id, [ref]$handle, [ref]$result)
    ReportErrorsEx -FunctionName $openMethod.Name -Hr $hr -Result $result
    $handle
}

function Invoke-HcnModifyNetwork {
    param (
        [Parameter(Mandatory)]
        [System.IntPtr]$HcnNetworkHandle,

        [Parameter(Mandatory)]
        [string]$SettingsJsonString,

        [Parameter()]
        [switch]$KeepHandleOpen,

        [Parameter()]
        $ModifyMethod = (Get-ClientNativeMethod Modify)
    )
    $result = ''
    $hr = $modifyMethod.Invoke($HcnNetworkHandle, $SettingsJsonString, [ref]$result)
    ReportErrorsEx -FunctionName $modifyMethod.Name -Hr $hr -Result $result -ThrowOnFail

    if (-not $KeepHandleOpen) { Invoke-HcnCloseNetwork $HcnNetworkHandle }
}

function Invoke-HcnQueryNetworkProperties {
    param (
        [Parameter(Mandatory)]
        [System.IntPtr]$HcnNetworkHandle,

        [Parameter()]
        [string]$QueryJsonString,

        [Parameter()]
        [switch]$KeepHandleOpen,

        [Parameter()]
        $QueryMethod = (Get-ClientNativeMethod Query)
    )
    if (-not $QueryJsonString) {
        $QueryJsonString = Get-HnsSchemaVersion -Json
    }
    $properties = ''
    $result = ''
    $hr = $queryMethod.Invoke($HcnNetworkHandle, $QueryJsonString, [ref]$properties, [ref]$result)
    ReportErrorsEx -FunctionName $queryMethod.Name -Hr $hr -Result $result

    if (-not $KeepHandleOpen) { Invoke-HcnCloseNetwork $HcnNetworkHandle }

    if ($properties) {
        ConvertResponseFromJsonEx -JsonInput $properties
    }
}

function Invoke-HcnDeleteNetwork {
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -ne [guid]::Empty })]
        [Guid]$Id,

        [Parameter()]
        $DeleteMethod = (Get-ClientNativeMethod Delete)
    )
    $result = ''
    $hr = $deleteMethod.Invoke($Id, [ref]$result)
    ReportErrorsEx -FunctionName $deleteMethod.Name -Hr $hr -Result $result
}

function Invoke-HcnCloseNetwork {
    param (
        [Parameter(Mandatory)]
        [System.IntPtr]$HcnNetworkHandle,

        [Parameter()]
        $CloseMethod = (Get-ClientNativeMethod Close)
    )
    $hr = $closeMethod.Invoke($HcnNetworkHandle);
    ReportErrorsEx -FunctionName $closeMethod.Name -Hr $hr
}
#endregion Generic

#region Helpers
function ReportErrorsEx {
    param(
        [Parameter()]
        [string]$FunctionName,
        [Parameter(Mandatory)]
        [Int64]$Hr,
        [Parameter()]
        [string]$Result,
        [switch]$ThrowOnFail
    )
    $errorOutput = @()

    if (-NOT [string]::IsNullOrWhiteSpace($Result)) {
        $parsedResult = ConvertFrom-Json $Result -ErrorAction SilentlyContinue
        if ($null -ne $parsedResult -and [bool]($parsedResult | Get-Member Error -ErrorAction SilentlyContinue)) {
            $errorOutput += $parsedResult.Error
        }
        else {
            $errorOutput += "Result: $Result"
        }
    }

    if ($Hr -ne 0) {
        $errorOutput += "HRESULT=$Hr"
    }

    if ($errorOutput) {
        $errString = "$($FunctionName): $($errorOutput -join ' ')"
        if ($ThrowOnFail) {
            throw $errString
        }
        else {
            Write-Error $errString
        }
    }
}

function ConvertResponseFromJsonEx {
    param(
        [Parameter()]
        [string]$JsonInput
    )

    $output = [PSCustomObject]@{};
    if ($JsonInput) {
        try {
            $output = ($JsonInput | ConvertFrom-Json -Depth 32);
        }
        catch {
            Write-Error $_.Exception.Message
            return ''
        }
        if ($output -and [bool]($output | Get-Member Error -ErrorAction SilentlyContinue)) {
            Write-Error $output.Error;
        }
    }

    return $output;
}
#endregion Helpers

#region Json Settings Helpers
function Get-HnsSchemaVersion {
    param ([int]$Version = 1, [switch]$Json)
    # $buildVersion = [environment]::OSVersion.Version.Build -as [int]
    # switch ($buildVersion) {
    # Schema Version Map Source:
    # https://docs.microsoft.com/en-us/virtualization/api/hcn/hns_schema#schema-version-map
    #     { $_ -gt 22000 } { $major = 2; $minor = 14; break }
    #     { $_ -gt 20348 } { $major = 2; $minor = 11; break }
    #     { $_ -gt 19041 } { $major = 2; $minor = 6; break }
    #     Default { $major = 1; $minor = 0 }
    # }
    if ($Version -eq 2) { $major = 2; $Minor = 0 }
    else { $major = 1; $minor = 0 }
    $schema = @{SchemaVersion = @{ Major = $major; Minor = $minor } }

    if ($Json) { ConvertTo-Json $schema -Depth 2 } else { $schema }
}

function Set-HnsNetworkSettings {
    param (
        [Parameter(Mandatory, ParameterSetName = 'Id')]
        [ValidateScript( { $_ -ne [Guid]::Empty } )]
        [Guid]$Id,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Settings,

        [switch]$Json
    )
    $fn = $MyInvocation.MyCommand.Name

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        $Id = Get-HnsNetworkId -Name $Name -ThrowIfNotFound
    }
    $newSettings = New-HnsNetworkSettings
    $currentSettings = Get-HnsNetworkEx -Id $Id
    Write-Debug "${fn}: Current Settings to modify:`n$($currentSettings | Out-String)"

    ForEach ($Key in $currentSettings.psobject.Properties.Name) {
        if ($Settings.ContainsKey($Key)) {
            $newSettings.$Key = $Settings.$Key
            Write-Debug "${fn}: Updated $Key=$currentSettings.$Key with Value: '$Settings.$Key'"
        }
        else {
            $newSettings.$Key = $currentSettings.$Key
        }
    }
    Write-Debug "${fn}: Final Modified Settings:`n$($newSettings | Out-String)"

    if ($Json) { $newSettings | ConvertTo-Json -Depth 32 } else { $newSettings }
}

function New-HnsNetworkSettings {
    param(
        [Parameter()]
        [string]$Name,
        [Parameter()]
        [string]$GatewayIpAddress,
        [Parameter()]
        [string]$AddressPrefix,
        [Parameter()]
        [string]$DNSServerList,
        [Parameter()]
        [int]$Flags,
        [Parameter()]
        [string]$Type,
        [Parameter()]
        [switch]$Json,
        [Parameter()]
        [int]$Version = 1
    )
    $settings = Get-HnsSchemaVersion -Version $Version
    if ($Type) { $settings.Type = $Type }
    if ($Name) { $settings.Name = $Name }
    if ($Flags) { $settings.Flags = $Flags }
    if ($DNSServerList) {
        $settings.DNSServerList = @($($DNSServerList -split ',' | ForEach-Object { $_.Trim() } ) )
    }
    if ($AddressPrefix -and $GatewayIpAddress) {
        $settings.Subnets = @(
            @{
                GatewayAddress = $GatewayIpAddress
                AddressPrefix  = $AddressPrefix
                IpSubnets      = @(
                    @{
                        IpAddressPrefix = $AddressPrefix
                        Flags           = 3
                    }
                )
            }
        )
    }
    if ($Json) { ConvertTo-Json $settings -Depth 32 } else { $settings }
}
#endregion Json Settings Helpers

$OriginalDebugPreference = $DebugPreference
$DebugPreference = 'SilentlyContinue'
$OriginalVerbosePreference = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

Export-ModuleMember -Function Invoke-HcnEnumerateNetworks
# Export-ModuleMember -Function Invoke-HcnQueryNetworkProperties
# Export-ModuleMember -Function Invoke-HcnCreateNetwork
# Export-ModuleMember -Function Invoke-HcnOpenNetwork
# Export-ModuleMember -Function Invoke-HcnCloseNetwork
# Export-ModuleMember -Function Invoke-HcnModifyNetwork
# Export-ModuleMember -Function Invoke-HcnDeleteNetwork

Export-ModuleMember -Function New-HnsNetworkEx
Export-ModuleMember -Function Get-HnsNetworkEx
Export-ModuleMember -Function Set-HnsNetworkEx
Export-ModuleMember -Function Remove-HnsNetworkEx
Export-ModuleMember -Function Get-HnsNetworkId
Export-ModuleMember -Function New-HnsNetworkSettings
Export-ModuleMember -Function Set-HnsNetworkSettings
Export-ModuleMember -Function Get-HnsNetworkSubnets

$DebugPreference = $OriginalDebugPreference
$VerbosePreference = $OriginalVerbosePreference
