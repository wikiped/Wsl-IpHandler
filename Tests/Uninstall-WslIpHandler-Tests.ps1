Describe 'Uninstall WSL IP Handler' -ForEach @(
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
        Import-Module $hnsModulePath
        Import-Module (Join-Path $subModulesRoot 'IPNetwork.psm1')
        . (Join-Path $scriptsRoot 'FunctionsPSElevation.ps1')
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
    Context ' Remove-WslNetworkAdapter' {
        BeforeAll {
            $wslId = Get-HnsNetworkId -Name $wsl
            $elevatedCommand = "Import-Module '$hnsModulePath'; Get-HnsNetwork -Id $wslId"
            $wslAdapter = Invoke-CommandElevated -Command $elevatedCommand -PassThruResult
            if ($null -ne $wslAdapter) {
                Write-Host "Removing WSL Network Adapter..."
                Remove-WslNetworkAdapter
            }
        }
        It ' Removed WSL Adapter' {
            $wslId = Get-HnsNetworkId -Name $wsl
            $elevatedCommand = "Import-Module '$hnsModulePath'; Get-HnsNetwork -Id $wslId"
            $wslAdapter = Invoke-CommandElevated -Command $elevatedCommand -PassThruResult
            $wslAdapter | Should -BeNullOrEmpty
        }
    }
}
