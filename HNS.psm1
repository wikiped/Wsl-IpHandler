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
    Open      = $ClientNativeMethods::HcnOpenNetwork;
    Close     = $ClientNativeMethods::HcnCloseNetwork;
    Enumerate = $ClientNativeMethods::HcnEnumerateNetworks;
    Delete    = $ClientNativeMethods::HcnDeleteNetwork;
    Query     = $ClientNativeMethods::HcnQueryNetworkProperties;
    Modify    = $ClientNativeMethods::HcnModifyNetwork;
}
#endregion Global Initialize

#region Network
function New-HnsNetworkEx {
    param
    (
        [parameter(Mandatory = $true)] [Guid] $Id,
        [parameter(Mandatory = $true, Position = 0)]
        [string] $JsonString
    )

    $settings = $JsonString
    $handle = 0
    $result = ''
    $hnsClientApi = Get-HnsClientNativeMethods
    $hr = $hnsClientApi::HcnCreateNetwork($id, $settings, [ref] $handle, [ref] $result);
    ReportErrorsEx -FunctionName HcnCreateNetwork -Hr $hr -Result $result -ThrowOnFail

    $query = Get-HnsSchemaVersion -Json
    $properties = '';
    $result = ''
    $hr = $hnsClientApi::HcnQueryNetworkProperties($handle, $query, [ref] $properties, [ref] $result);
    ReportErrorsEx -FunctionName HcnQueryNetworkProperties -Hr $hr -Result $result
    $hr = $hnsClientApi::HcnCloseNetwork($handle);
    ReportErrorsEx -FunctionName HcnCloseNetwork -Hr $hr

    if ($properties) {
        return ConvertResponseFromJsonEx -JsonInput $properties
    }
}

function Get-HnsNetworkEx {
    param
    (
        [parameter(Mandatory = $false)] [Guid] $Id = [Guid]::Empty,
        [parameter(Mandatory = $false)] [switch] $Detailed,
        [parameter(Mandatory = $false)] [int] $Version
    )
    $params = @{
        Id            = $Id
        NativeMethods = $NetworkNativeMethods
        Version       = $Version
    }

    if ($Detailed.IsPresent) {
        $params += @{Detailed = $true }
    }

    return Get-HnsGenericEx @params
}

function Remove-HnsNetworkEx {
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [Object[]] $InputObjects
    )
    begin { $objects = @() }
    process { $Objects += $InputObjects; }
    end {
        Remove-HnsGenericEx -InputObjects $Objects -NativeMethods $NetworkNativeMethods
    }
}
#endregion Network

#region Generic
function Get-HnsNetworkIdEx {
    param
    (
        [parameter(Mandatory = $false)] [string] $Name = '',
        [parameter(Mandatory = $false)] [Hashtable] $Filter = @{},
        [parameter(Mandatory = $false)] [Hashtable] $NativeMethods = $NetworkNativeMethods,
        [parameter(Mandatory = $false)] [int]       $Version
    )
    $ids = ''

    if ($Name) {
        $Filter['Name'] = $Name
    }

    $FilterString = ConvertTo-Json $Filter -Depth 32
    $query = @{ Filter = $FilterString }
    $query += Get-HnsSchemaVersion -Version $Version

    $query = ConvertTo-Json $query -Depth 32

    $result = ''
    $hr = $NativeMethods['Enumerate'].Invoke($query, [ref] $ids, [ref] $result);
    ReportErrorsEx -FunctionName $NativeMethods['Enumerate'].Name -Hr $hr -Result $result -ThrowOnFail

    if ($null -eq $ids) {
        return
    }

    $ids | ConvertFrom-Json
}

function Get-HnsGenericEx {
    param
    (
        [parameter(Mandatory = $false)] [Guid] $Id = [Guid]::Empty,
        [parameter(Mandatory = $false)] [Hashtable] $Filter = @{},
        [parameter(Mandatory = $false)] [Hashtable] $NativeMethods = $NetworkNativeMethods,
        [parameter(Mandatory = $false)] [switch]    $Detailed,
        [parameter(Mandatory = $false)] [int]       $Version
    )

    $ids = Get-HnsNetworkIdEx -Filter $Filter -NativeMethods $NativeMethods -Version $Version
    $FilterString = ConvertTo-Json $Filter -Depth 32
    $query = @{ Filter = $FilterString }
    $query += Get-HnsSchemaVersion -Version $Version

    if ($Detailed.IsPresent) {
        $query += @{Flags = 1 }
    }
    $query = ConvertTo-Json $query -Depth 32

    if ($Id -ne [Guid]::Empty) {
        $ids = $Id
    }
    else {
        $ids = Get-HnsNetworkIdEx -Filter $Filter -NativeMethods $NativeMethods -Version $Version
    }

    $output = @()
    $ids | ForEach-Object {
        $handle = 0
        $result = ''
        $hr = $NativeMethods['Open'].Invoke($_, [ref] $handle, [ref] $result);
        ReportErrorsEx -FunctionName $NativeMethods['Open'].Name -Hr $hr -Result $result
        $properties = '';
        $result = ''
        $hr = $NativeMethods['Query'].Invoke($handle, $query, [ref] $properties, [ref] $result);
        ReportErrorsEx -FunctionName $NativeMethods['Query'].Name -Hr $hr -Result $result
        $output += ConvertResponseFromJsonEx -JsonInput $properties
        $hr = $NativeMethods['Close'].Invoke($handle);
        ReportErrorsEx -FunctionName $NativeMethods['Close'].Name -Hr $hr
    }

    if ($output) { return $output }
}

function Remove-HnsGenericEx {
    param
    (
        [parameter(Mandatory = $false, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
        [Object[]] $InputObjects,
        [parameter(Mandatory = $false)] [Hashtable] $NativeMethods = $NetworkNativeMethods
    )

    begin { $objects = @() }
    process {
        if ($InputObjects) {
            $Objects += $InputObjects;
        }
    }
    end {
        $Objects | ForEach-Object {
            $result = ''
            $hr = $NativeMethods['Delete'].Invoke($_.Id, [ref] $result);
            ReportErrorsEx -FunctionName $NativeMethods['Delete'].Name -Hr $hr -Result $result
        }
    }
}
#endregion Generic

#region Helpers
function ReportErrorsEx {
    param
    (
        [parameter(Mandatory = $false)]
        [string] $FunctionName,
        [parameter(Mandatory = $true)]
        [Int64] $Hr,
        [parameter(Mandatory = $false)]
        [string] $Result,
        [switch] $ThrowOnFail
    )

    $errorOutput = ''

    if (-NOT [string]::IsNullOrWhiteSpace($Result)) {
        $parsedResult = ConvertFrom-Json $Result -ErrorAction SilentlyContinue
        if ($null -ne $parsedResult) {
            if ([bool]($parsedResult | Get-Member Error -ErrorAction SilentlyContinue)) {
                $errorOutput += $parsedResult.Error
            }
            else {
                $errorOutput += "Result: $Result"
            }
        }
        else {
            $errorOutput += "Result: $Result"
        }
    }

    if ($Hr -ne 0) {
        $errorOutput += " HRESULT=$Hr"
    }

    if (-NOT [string]::IsNullOrWhiteSpace($errorOutput)) {
        $errString = "$($FunctionName) [ERROR]: $($errorOutput)"
        if ($ThrowOnFail.IsPresent) {
            throw $errString
        }
        else {
            Write-Error $errString
        }
    }
}

function ConvertResponseFromJsonEx {
    param
    (
        [parameter(Mandatory = $false)]
        [string] $JsonInput
    )

    $output = '';
    if ($JsonInput) {
        try {
            $output = ($JsonInput | ConvertFrom-Json -Depth 32);
        }
        catch {
            Write-Error $_.Exception.Message
            return ''
        }
        if ([bool]($output | Get-Member Error -MemberType Properties -ErrorAction SilentlyContinue)) {
            Write-Error $output;
        }
    }

    return $output;
}
#endregion Helpers

#region Json Settings Helpers
function Get-HnsNetworkId {
    param (
        [Parameter()]
        # [ValidateSet('WSL', 'Default Switch', 'External Switch')]
        [string]$HnsNetworkName
    )
    switch ($HnsNetworkName) {
        'WSL' { return 'b95d0c5e-57d4-412b-b571-18a81a16e005' }
        'Default Switch' { return 'c08cb7b8-9b3c-408e-8e30-5e16a3aeb444' }
        'External Switch' { return '03c876a3-4c5b-40a6-98f4-a4c9a1855fd1' }
        Default {
            # $fn = $MyInvocation.MyCommand.Name
            # ThrowTerminatingError "Parameter 'HnsNetworkName' for $fn can be one of { 'WSL' | 'Default Switch' | 'External Switch' }, not '$HnsNetworkName'."
            Get-HnsNetworkIdEx -Name $HnsNetworkName
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
        Select-Object -Property Name, Subnets |
        ForEach-Object {
            $Name = $_.Name;
            $_.Subnets | ForEach-Object {
                [PSCustomObject]@{Name = $Name; AddressPrefix = $_.AddressPrefix }
            }
        }
}

function Get-HnsSchemaVersion {
    param ([int]$Version, [switch]$Json)
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

function New-HnsNetworkSettings {
    param(
        [ValidateSet('WSL', 'Default Switch')]
        [string]$Name = 'WSL',
        [Parameter(Mandatory)]
        [string]$GatewayIpAddress,
        [Parameter(Mandatory)]
        [string]$AddressPrefix,
        [Parameter(Mandatory)]
        [string]$DNSServerList,
        [Parameter(Mandatory)]
        [int]$Flags,
        [switch]$Json
    )
    $settings = @{
        Name          = $Name
        Type          = 'ICS'
        Flags         = $Flags
        DNSServerList = @(
            $($DNSServerList -split ',' | ForEach-Object { $_.Trim() } )
        )
        Subnets       = @(
            @{
                AddressPrefix = $AddressPrefix
                IpSubnets     = @(
                    @{
                        IpAddressPrefix = $AddressPrefix
                        Flags           = 3
                    }
                )
            }
        )
    }

    $settings += Get-HnsSchemaVersion
    if ($Json) { ConvertTo-Json $settings -Depth 64 } else { $settings }
}

#endregion Json Settings Helpers

$OriginalDebugPreference = $DebugPreference
$DebugPreference = 'SilentlyContinue'
$OriginalVerbosePreference = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'

Export-ModuleMember -Function New-HnsNetworkEx
Export-ModuleMember -Function Get-HnsNetworkEx
Export-ModuleMember -Function Remove-HnsNetworkEx
Export-ModuleMember -Function Get-HnsNetworkId
Export-ModuleMember -Function Get-HnsNetworkIdEx
Export-ModuleMember -Function New-HnsNetworkSettings
Export-ModuleMember -Function Get-HnsNetworkSubnets

$DebugPreference = $OriginalDebugPreference
$VerbosePreference = $OriginalVerbosePreference
