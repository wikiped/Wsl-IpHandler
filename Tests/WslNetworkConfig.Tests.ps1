Describe 'Editing Network settings in wsl-iphandler-config' -ForEach @(
    @{
        GatewayIpAddress = '172.16.0.1'
        PrefixLength     = '24'
        DynamicAdapters  = 'Ethernet', 'Default Switch'
        WindowsHostName  = 'windows'
    }
    @{
        GatewayIpAddress = '192.168.1.100'
        PrefixLength     = '16'
        DNSServerList    = '192.168.1.100, 8.8.8.8'
        DynamicAdapters  = 'Ethernet', 'Default Switch'
        WindowsHostName  = 'windows'
    }
) {
    BeforeAll {
        $ModulePath = $PSScriptRoot | Split-Path
        Import-Module $ModulePath -Force
        $sectionName = InModuleScope Wsl-IpHandler { Get-NetworkSectionName WslIpHandler }
        $gatewayKeyName = InModuleScope Wsl-IpHandler { Get-GatewayIpAddressKeyName }
        $prefixKeyName = InModuleScope Wsl-IpHandler { Get-PrefixLengthKeyName }
        $dnsKeyName = InModuleScope Wsl-IpHandler { Get-DnsServersKeyName }
        $dynamicAdaptersKeyName = InModuleScope Wsl-IpHandler { Get-DynamicAdaptersKeyName }
        $windowsHostNameKeyName = InModuleScope Wsl-IpHandler { Get-WindowsHostNameKeyName }
        $expectedText = @(
            "[$sectionName]"
            "$windowsHostNameKeyName = $WindowsHostName"
            "$gatewayKeyName = $GatewayIpAddress"
            "$prefixKeyName = $PrefixLength"
            "$dnsKeyName = $(if (Test-Path variable:DNSServerList) {$DNSServerList -join ', '} else {$GatewayIpAddress})"
            "$dynamicAdaptersKeyName = $($DynamicAdapters -join ', ')"
            ''
        ) -join "`r`n"
        Set-Variable Expected $expectedText
        Set-Variable WslConfigPath 'TestDrive:\.wslconfig'
        Set-Variable WslIpHandlerConfigPath 'TestDrive:\.wsl-iphandler-config'
        Mock -ModuleName Wsl-IpHandler Get-WslConfigPath { $WslConfigPath } -ParameterFilter { $ConfigType -eq 'Wsl' }
        Mock -ModuleName Wsl-IpHandler Get-WslConfigPath { $WslIpHandlerConfigPath } -ParameterFilter { $ConfigType -eq 'WslIpHandler' }

    }
    Context ' With config file that does not exist' {
        BeforeEach {
            Remove-Item $WslIpHandlerConfigPath -ErrorAction Ignore -Force
        }
        AfterEach {
            Remove-Item $WslIpHandlerConfigPath -ErrorAction Ignore -Force
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                $params = @{
                    GatewayIpAddress = $GatewayIpAddress
                    PrefixLength     = $PrefixLength
                    WindowsHostName  = $WindowsHostName
                    DynamicAdapters  = $DynamicAdapters
                }
                if (Test-Path variable:DNSServerList) { $params.DNSServerList = $DNSServerList }
                Set-WslNetworkConfig @params
            }
            It ' Should create file with a record of IP assignment' {
                try {
                    $WslIpHandlerConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $WslIpHandlerConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected Content:'
                    Write-Host '-----------------'
                    Write-Host "$Expected"
                    Write-Host '-----------------'
                    Throw
                }
            }
        }
        Context ' Remove-WslNetworkConfig' {
            BeforeEach {
                if (Test-Path $WslIpHandlerConfigPath -PathType Leaf) {
                    Write-Host "File exists when it shouldn't: $WslIpHandlerConfigPath"
                }
                Remove-WslNetworkConfig
            }
            It ' Should not have created config file' {
                try {
                    $WslIpHandlerConfigPath | Should -Not -Exist
                }
                catch {
                    Write-Host "Should not have existed: $WslIpHandlerConfigPath"
                    Write-Host 'Content of the file:'
                    Write-Host "$(Get-Content $WslIpHandlerConfigPath)"
                    Throw
                }
            }
        }
    }
    Context ' With config file that is empty' {
        BeforeEach {
            Set-Content $WslIpHandlerConfigPath -Value @()
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                $params = @{
                    GatewayIpAddress = $GatewayIpAddress
                    PrefixLength     = $PrefixLength
                    WindowsHostName  = $WindowsHostName
                    DynamicAdapters  = $DynamicAdapters
                }
                if (Test-Path variable:DNSServerList) { $params.DNSServerList = $DNSServerList }
                Set-WslNetworkConfig @params
            }
            It ' Should make a record with IP assignment' {
                $WslIpHandlerConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
            }
        }
        Context ' Remove-WslNetworkConfig' {
            BeforeEach {
                Remove-WslNetworkConfig
            }
            It ' Should keep config file empty' {
                Get-Content $WslIpHandlerConfigPath | Should -BeNullOrEmpty
            }
        }
    }
    Context ' With config file already having required record' {
        BeforeEach {
            Set-Content $WslIpHandlerConfigPath -Value $Expected
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                $Modified = $false
                $params = @{
                    GatewayIpAddress = $GatewayIpAddress
                    PrefixLength     = $PrefixLength
                    WindowsHostName  = $WindowsHostName
                    DynamicAdapters  = $DynamicAdapters
                }
                if (Test-Path variable:DNSServerList) { $params.DNSServerList = $DNSServerList }
                Set-WslNetworkConfig -Modified ([ref]$Modified) @params
            }
            It ' Should have kept the same content' {
                try {
                    $WslIpHandlerConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $WslIpHandlerConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected Content:'
                    Write-Host '-----------------'
                    Write-Host "$Expected"
                    Write-Host '-----------------'
                    Throw
                }
            }
            It ' Should not have modified existing file' {
                $Modified | Should -BeFalse
            }
        }
        Context ' Remove-WslNetworkConfig' {
            BeforeEach {
                Remove-WslNetworkConfig
            }
            It ' Should keep config file empty' {
                $WslIpHandlerConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($Expected))
            }
        }
    }
    Context ' With config file having IP address different from required' {
        BeforeAll {
            Import-Module (Join-Path $PSScriptRoot '..\SubModules\IPNetwork.psm1' -Resolve) -Function Get-IpNet | Out-Null
        }
        BeforeEach {
            $ipObj = Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            $badIp = $ipObj.Add($ipObj.IPcount)
            $params = @{
                GatewayIpAddress = $badIp.IP.IPAddressToString
                PrefixLength     = $PrefixLength
                WindowsHostName  = $WindowsHostName
                DynamicAdapters  = $DynamicAdapters
            }
            if (Test-Path variable:DNSServerList) { $params.DNSServerList = $DNSServerList }
            Set-WslNetworkConfig @params -Force

            # $badRecord = $Expected -replace 'gateway_ip = .*', "gateway_ip = $($badIp.IP)"
            # Set-Content $WslIpHandlerConfigPath -Value $badRecord
        }
        Context ' Set-WslNetworkConfig' {
            BeforeAll {
                $params = @{
                    GatewayIpAddress = $GatewayIpAddress
                    PrefixLength     = $PrefixLength
                    WindowsHostName  = $WindowsHostName
                    DynamicAdapters  = $DynamicAdapters
                }
                if (Test-Path variable:DNSServerList) { $params.DNSServerList = $DNSServerList }
                Set-WslNetworkConfig @params
            }
            It ' Should replace existing setting in config file removing bad record' {

                try {
                    $WslIpHandlerConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badIp.IP.IPAddressToString))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $WslIpHandlerConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected NOT To Have Content:'
                    Write-Host '-----------------'
                    Write-Host "$($badIp.IP.IPAddressToString)"
                    Write-Host '-----------------'
                    Throw
                }
            }
            It ' Should replace existing setting in config file to required IP address' {
                try {
                    $WslIpHandlerConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $WslIpHandlerConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected Content:'
                    Write-Host '-----------------'
                    Write-Host "$Expected"
                    Write-Host '-----------------'
                    Throw
                }
            }
        }
        Context ' Remove-WslNetworkConfig' {
            BeforeEach {
                Remove-WslNetworkConfig
            }
            It ' Should remove existing record' {
                try {
                    $WslIpHandlerConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $WslIpHandlerConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected NOT To Have Content:'
                    Write-Host '-----------------'
                    Write-Host "$badRecord"
                    Write-Host '-----------------'
                    Throw
                }
            }
        }
    }
}
