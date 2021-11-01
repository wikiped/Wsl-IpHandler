Describe 'Editing Network settings in wslconfig' -ForEach @(
    @{
        GatewayIpAddress = '172.16.0.1'
        PrefixLength     = '24'
        Expected         = "[network]`r`ngateway_ip = 172.16.0.1`r`nprefix_length = 24`r`ndns_servers = 172.16.0.1"
    }
    @{
        GatewayIpAddress = '192.168.1.100'
        PrefixLength     = '16'
        DNSServerList    = '192.168.1.100,8.8.8.8'
        Expected         = "[network]`r`ngateway_ip = 192.168.1.100`r`nprefix_length = 16`r`ndns_servers = 172.16.0.1,8.8.8.8"
    }
) {
    BeforeAll {
        Set-Variable ConfigPath 'TestDrive:\test.wslconfig'
        $sectionName = InModuleScope WSL-IpHandler { Get-NetworkSectionName }
        $gatewayKeyName = InModuleScope WSL-IpHandler { Get-GatewayIpAddressKeyName }
        $prefixKeyName = InModuleScope WSL-IpHandler { Get-PrefixLengthKeyName }
        $dnsKeyName = InModuleScope WSL-IpHandler { Get-DnsServersKeyName }
        $expectedText = @(
            "[$sectionName]"
            "$gatewayKeyName = $GatewayIpAddress"
            "$prefixKeyName = $PrefixLength"
            "$dnsKeyName = $GatewayIpAddress"
        ) -join "`r`n"
        Set-Variable Expected $expectedText
    }
    BeforeEach {
        Import-Module WSL-IpHandler -Force
        Mock -ModuleName WSL-IpHandler Get-WslConfigPath {
            param([switch]$Resolve) return $ConfigPath
        }
    }
    Context ' With config file that does not exist' {
        Context ' Set-WslNetworkConfig' {
            BeforeEach {
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength
            }
            It ' Should create file with a record of IP assignment' {
                $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
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
                Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength
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
        Context ' With config file already having required record' {
            BeforeEach {
                Set-Content $ConfigPath -Value $Expected
            }
            Context ' Set-WslNetworkConfig' {
                BeforeEach {
                    $Modified = $false
                    Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -Modified ([ref]$Modified)
                }
                It ' Should not change existing file' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                    $Modified | Should -BeFalse
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
                Import-Module (Join-Path $PSScriptRoot 'IP-Calc.psm1' -Resolve) -Function Get-IpCalcResult | Out-Null
            }
            BeforeEach {
                $ipObj = Get-IpCalcResult -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
                $badIp = $ipObj.Add($ipObj.IPcount)
                $badRecord = "[network]`r`ngateway_ip = $($badIp.IP)"
                $badRecord += "`r`nprefix_length = $PrefixLength"
                $badRecord += "`r`ndns_servers = $GatewayIpAddress"
                Set-Content $ConfigPath -Value $badRecord
            }
            Context ' Set-WslNetworkConfig' {
                BeforeEach {
                    Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength
                }
                It ' Should replace existing setting in config file to required IP address' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslNetworkConfig' {
                BeforeEach {
                    Remove-WslNetworkConfig
                }
                It ' Should remove existing record' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                }
            }
        }
    }
}
