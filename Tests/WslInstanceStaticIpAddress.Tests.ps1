Describe 'Editing Static IP addresses in wslconfig' {
    BeforeAll {
        Set-Variable ConfigPath 'TestDrive:\test.wslconfig'
        Import-Module (Join-Path $PSScriptRoot 'IPNetwork.psm1' -Resolve) -Function Get-IpNet
    }
    BeforeEach {
        Import-Module WSL-IpHandler -Force
        Mock -ModuleName WSL-IpHandler Get-WslConfigPath {
            param([switch]$Resolve) return $ConfigPath
        }
    }
    Describe ' Given Parameters with Static IP: <WslInstanceIpAddress>' -ForEach @(
        @{
            WslInstanceName      = 'TestInstance'
            GatewayIpAddress     = '172.16.0.1'
            PrefixLength         = '24'
            WslInstanceIpAddress = '172.16.0.100'
            Expected             = "[static_ips]`r`nTestInstance = 172.16.0.100"
        }
        @{
            WslInstanceName      = 'TestInstance'
            GatewayIpAddress     = '192.168.0.2'
            PrefixLength         = '16'
            WslInstanceIpAddress = '192.168.0.200'
            Expected             = "[static_ips]`r`nTestInstance = 192.168.0.200"
        }
    ) {
        Context ' With config file that does not exist' {
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -WslInstanceIpAddress $WslInstanceIpAddress
                }
                It ' Should create file with a record of IP assignment' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
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
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -WslInstanceIpAddress $WslInstanceIpAddress
                }
                It ' Should make a record with IP assignment' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
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
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    $Modified = $false
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -WslInstanceIpAddress $WslInstanceIpAddress -Modified ([ref]$Modified)
                }
                It ' Should not change existing file' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                    $Modified | Should -BeFalse
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
                }
                It ' Should keep config file empty' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
        }
        Context ' With config file having IP address different from required' {
            BeforeEach {
                $ipObj = Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
                $badIp = $ipObj.Add($ipObj.IPcount)
                $badRecord = "[static_ips]`r`n$WslInstanceName = $($badIp.IP)"
                Set-Content $ConfigPath -Value $badRecord
            }
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Set-WslInstanceStaticIpAddress `
                        -WslInstanceName $WslInstanceName `
                        -GatewayIpAddress $GatewayIpAddress `
                        -WslInstanceIpAddress $WslInstanceIpAddress `
                        -PrefixLength $PrefixLength
                }
                It ' Should replace existing setting in config file to required IP address' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
                }
                It ' Should remove existing record' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($badRecord))
                }
            }
        }
    }
    Describe ' Given Parameters without Static IP' -ForEach @(
        @{
            WslInstanceName  = 'TestInstance'
            GatewayIpAddress = '172.16.0.1'
            PrefixLength     = '24'
            Expected         = "[static_ips]`r`nTestInstance = 172.16.0.2"
        }
        @{
            WslInstanceName  = 'TestInstance'
            GatewayIpAddress = '192.168.0.1'
            PrefixLength     = '16'
            Expected         = "[static_ips]`r`nTestInstance = 192.168.0.2"
        }
    ) {
        Context ' With config file that does not exist' {
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -WslInstanceIpAddress $WslInstanceIpAddress
                }
                It ' Should create file with a record of IP assignment' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
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
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress
                }
                It ' Should make a record with IP assignment' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
                }
                It ' Should keep config file empty' {
                    Get-Content $ConfigPath | Should -BeNullOrEmpty
                }
            }
        }
        Context ' With config file having some IP address within required SubNet' {
            BeforeEach {
                Set-Content $ConfigPath -Value $Expected
            }
            Context ' Set-WslInstanceStaticIpAddress' {
                BeforeEach {
                    $Modified = $false
                    Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -Modified ([ref]$Modified)
                }
                It ' Should not change existing file' {
                    $ConfigPath | Should -FileContentMatchMultiline ([regex]::Escape($Expected))
                    $Modified | Should -BeFalse
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
                }
                It ' Should remove existing assignment' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($Expected))
                }
            }
        }
        Context ' With config file having some IP address not within required SubNet' {
            BeforeAll {
                $ipObj = Get-IpNet -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength
                $badIp = $ipObj.Add($ipObj.IPcount)
                Set-Variable BadRecord "[static_ips]`r`n$WslInstanceName = $($badIp.IP)"
            }
            BeforeEach {
                Set-Content $ConfigPath -Value $BadRecord
            }
            Context ' Set-WslInstanceStaticIpAddress' {
                It ' Should throw ArgumentException' {
                    { Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress } | Should -Throw -ExceptionType ([System.ArgumentException])
                }
            }
            Context ' Remove-WslInstanceStaticIpAddress' {
                BeforeEach {
                    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName
                }
                It ' Should remove existing assignment' {
                    $ConfigPath | Should -Not -FileContentMatchMultiline ([regex]::Escape($BadRecord))
                }
            }
        }
    }
}
# Describe 'Given empty config file '
