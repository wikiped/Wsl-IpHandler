Describe 'Editing Network settings in wslconfig' -ForEach @(
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
        $ModuleName = 'WSL-IpHandler'
        $ModulePath = Join-Path (Split-Path $PSScriptRoot) "$ModuleName"
        Import-Module $ModulePath -Force
        Set-Variable ConfigPath 'TestDrive:\test.wslconfig'
        $sectionName = InModuleScope WSL-IpHandler { Get-NetworkSectionName }
        $gatewayKeyName = InModuleScope WSL-IpHandler { Get-GatewayIpAddressKeyName }
        $prefixKeyName = InModuleScope WSL-IpHandler { Get-PrefixLengthKeyName }
        $dnsKeyName = InModuleScope WSL-IpHandler { Get-DnsServersKeyName }
        $dynamicAdaptersKeyName = InModuleScope WSL-IpHandler { Get-DynamicAdaptersKeyName }
        $windowsHostNameKeyName = InModuleScope WSL-IpHandler { Get-WindowsHostNameKeyName }
        $expectedText = @(
            "[$sectionName]"
            "$windowsHostNameKeyName = $WindowsHostName"
            "$gatewayKeyName = $GatewayIpAddress"
            "$prefixKeyName = $PrefixLength"
            "$dnsKeyName = $(if ($DNSServerList) {$DNSServerList -join ', '} else {$GatewayIpAddress})"
            "$dynamicAdaptersKeyName = $($DynamicAdapters -join ', ')"
        ) -join "`r`n"
        Set-Variable Expected $expectedText
    }
    BeforeEach {
        # $ModuleName = 'WSL-IpHandler'
        # $ModulePath = Join-Path (Split-Path $PSScriptRoot) "$ModuleName"
        Import-Module $ModulePath -Force
        Mock -ModuleName WSL-IpHandler Get-WslConfigPath {
            param([switch]$Resolve) return $ConfigPath
        }
    }
    Context ' With config file that does not exist' {
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -WindowsHostName $WindowsHostName -DynamicAdapters $DynamicAdapters
            }
            It ' Should create file with a record of IP assignment' {
                try {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $ConfigPath) -join "`n")"
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
            It ' Should not have created config file' {
                $ConfigPath | Should -Not -Exist
            }
        }
    }
    Context ' With config file that is empty' {
        BeforeEach {
            Set-Content $ConfigPath -Value @()
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -WindowsHostName $WindowsHostName -DynamicAdapters $DynamicAdapters
            }
            It ' Should make a record with IP assignment' {
                $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
            }
        }
        Context ' Remove-WslNetworkConfig' {
            BeforeEach {
                Remove-WslNetworkConfig
            }
            It ' Should keep config file empty' {
                Get-Content $ConfigPath | Should -BeNullOrEmpty
            }
        }
    }
    Context ' With config file already having required record' {
        BeforeEach {
            Set-Content $ConfigPath -Value $Expected
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                $Modified = $false
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -WindowsHostName $WindowsHostName -DynamicAdapters $DynamicAdapters -Modified ([ref]$Modified)
            }
            It ' Should not change existing file' {
                try {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                    $Modified | Should -BeFalse
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $ConfigPath) -join "`n")"
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
            It ' Should keep config file empty' {
                $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($Expected))
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
            # $badRecord = "[network]`r`ngateway_ip = $($badIp.IP)"
            # $badRecord += "`r`nprefix_length = $PrefixLength"
            # $badRecord += "`r`ndns_servers = $GatewayIpAddress"
            $badRecord = $Expected -replace 'gateway_ip = .*', "gateway_ip = $($badIp.IP)"
            Set-Content $ConfigPath -Value $badRecord
        }
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -WindowsHostName $WindowsHostName -DynamicAdapters $DynamicAdapters
            }
            It ' Should replace existing setting in config file removing bad record' {
                try {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $ConfigPath) -join "`n")"
                    Write-Host '---------------'
                    Write-Host 'Expected NOT To Have Content:'
                    Write-Host '-----------------'
                    Write-Host "$badRecord"
                    Write-Host '-----------------'
                    Throw
                }
            }
            It ' Should replace existing setting in config file to required IP address' {
                try {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $ConfigPath) -join "`n")"
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
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                }
                catch {
                    Write-Host 'Actual Content:'
                    Write-Host '---------------'
                    Write-Host "$((Get-Content $ConfigPath) -join "`n")"
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
