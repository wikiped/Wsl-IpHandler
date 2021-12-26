Describe 'Install & Uninstall WSL IP Handler' -ForEach @(
    @{
        WslInstanceName      = 'Ubuntu'
        GatewayIpAddress     = '172.16.0.1'
        PrefixLength         = 24
        WslInstanceIpAddress = '172.16.0.2'
        DontModifyPsProfile  = $true
    }
) {
    BeforeAll {
        Set-Variable wsl 'WSL'
        $moduleRoot = Split-Path $PSScriptRoot
        $subModulesRoot = Join-Path $moduleRoot 'SubModules'
        $scriptsRoot = Join-Path $moduleRoot 'Scripts' 'Powershell'
        Set-Variable hnsModulePath (Join-Path $subModulesRoot 'HNS.psm1')
        Import-Module $moduleRoot
        Import-Module $hnsModulePath -Verbose:$false -Debug:$false
        Import-Module (Join-Path $subModulesRoot 'IPNetwork.psm1') -Verbose:$false -Debug:$false
        . (Join-Path $scriptsRoot 'FunctionsPSElevation.ps1')
    }
    Context " When WSL Adater does not exist and it's IP subnet is free" {
        Context ' Install-WslIpHandler' {
            BeforeAll {
                Set-WslNetworkAdapter -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength
                Remove-WslNetworkAdapter
                Install-WslIpHandler -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -WslInstanceIpAddress $WslInstanceIpAddress -DontModifyPsProfile:$DontModifyPsProfile -AutoFixWslConfig
            }
            It ' Created WSL Adapter with required parameters' {
                $wslId = Get-HnsNetworkId -Name $wsl
                $elevatedCommand = "Import-Module '$hnsModulePath'; Get-HnsNetwork -Id $wslId"
                $wslAdapter = Invoke-CommandElevated -Command $elevatedCommand -PassThruResult
                $wslAdapter | Should -Not -BeNullOrEmpty
                $actualGateway = $wslAdapter.Subnets[0].GatewayAddress
                $actualPrefix = $wslAdapter.Subnets[0].AddressPrefix -split '/' | Select-Object -Last 1
                $actualGateway | Should -Be $GatewayIpAddress
                $actualPrefix | Should -Be $PrefixLength
            }
            It ' Assigned Static IP address matches <WslInstanceIpAddress>' {
                $command = '"hostname -I"'
                $actualWslIpAddress = Invoke-WslExe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                $actualWslIpAddress.Trim() | Should -Be $WslInstanceIpAddress
            }
            It ' Gateway IP address matches <GatewayIpAddress>' {
                $command = "`"grep -oP 'nameserver \K.*' /etc/resolv.conf`""
                $actualGateway = Invoke-WslExe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                $actualGateway | Should -Be $GatewayIpAddress
            }
            Context ' Uninstall-WslIpHandler' {
                BeforeAll {
                    Uninstall-WslIpHandler -WslInstanceName $WslInstanceName
                }
                It ' Removed wsl-iphandler.sh from <WslInstanceName>' {
                    $command = '"test -f /usr/local/bin/wsl-iphandler.sh && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed run-wsl-iphandler.sh from <WslInstanceName>' {
                    $command = '"test -f /etc/profile.d/run-wsl-iphandler.sh && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed /etc/sudoers.d/wsl-iphandler from <WslInstanceName>' {
                    $command = '"test -f /etc/sudoers.d/wsl-iphandler && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed windows_host from /etc/wsl.conf @ <WslInstanceName>' {
                    $command = '"grep -Pqs "^\s*windows_host\s*=*" "/etc/wsl.conf" &>/dev/null && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed wsl_host from /etc/wsl.conf @ <WslInstanceName>' {
                    $command = '"grep -Pqs "^\s*wsl_host\s*=*" "/etc/wsl.conf" &>/dev/null && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed static_ip from /etc/wsl.conf @ <WslInstanceName>' {
                    $command = '"grep -Pqs "^\s*static_ip\s*=*" "/etc/wsl.conf" &>/dev/null && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
                It ' Removed ip_offset from /etc/wsl.conf @ <WslInstanceName>' {
                    $command = '"grep -Pqs "^\s*ip_offset\s*=*" "/etc/wsl.conf" &>/dev/null && echo true || echo false"'
                    $fileExists = wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c $command
                    $fileExists | Should -Be 'false'
                }
            }
        }
    }
    Context " When WSL Adater does not exist but it's IP subnet is not free" {

    }
    Context ' When WSL Adater exists and has required configuration' {

    }
    Context " When WSL Adater exists but is misconfigured and it's subnet is free" {

    }
    Context " When WSL Adater exists but is misconfigured and it's subnet is NOT free" {

    }
}
