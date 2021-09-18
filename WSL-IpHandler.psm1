
$ErrorActionPreference = 'Stop'

Set-StrictMode -Version latest

. (Join-Path $PSScriptRoot 'WindowsCommandsUTF16Converters.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'HelpersPrivateData.ps1' -Resolve)
. (Join-Path $PSScriptRoot 'HelpersWslConfig.ps1' -Resolve)

function Install-WSLIpHandler {
    [CmdletBinding(DefaultParameterSetName = 'Dynamic')]
    param (
        [Parameter(Mandatory)]
        [ArgumentCompleter(
            {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                Get-CommandOutputInUTF16AsUTF8 'wsl.exe' '-l' |
                    Select-Object -Skip 1 |
                    Where-Object { $_ -like "*${wordToComplete}*" } |
                    ForEach-Object {
                        $res = $_ -split ' ' | Select-Object -First 1
                        New-Object System.Management.Automation.CompletionResult (
                            $res,
                            $res,
                            'ParameterValue',
                            $res
                        )
                    }
            }
        ) ]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter(Mandatory, ParameterSetName = 'Static')][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Static')][Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Parameter(ParameterSetName = 'Static')][Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Alias('IpAddress')]
        [ipaddress]$WslInstanceIpAddress,

        # [Parameter(ParameterSetName = 'Dynamic')][ValidateRange(1, 254)]
        # [Alias('Offset')]
        # [int]$WslIpOffset,

        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [string]$WindowsHostName = 'windows',

        [switch]$DontModifyPsProfile,

        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name
    $debug_var = if ($DebugPreference -eq 'Continue') { 'DEBUG=1' } else { '' }
    $verbose_var = if ($VerbosePreference -eq 'Continue') { 'VERBOSE=1' } else { '' }

    Write-Host "PowerShell Installing WSL-IpHandler to $WslInstanceName..."
    #region PS Autorun
    # Get Path to PS Script that injects (if needed) IP-host to windows hosts on every WSL launch
    $WinHostsEditScript = Get-SourcePath 'WinHostsEdit'
    Write-Debug "${fn}: `$WinHostsEditScript='$WinHostsEditScript'"
    #endregion PS Autorun

    #region Bash Installation Script Path
    $BashInstallScript = Get-SourcePath 'BashInstall'
    Write-Debug "${fn}: `$BashInstallScript='$BashInstallScript'"
    #endregion Bash Installation Script Path

    #region WSL Autorun Script Path
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptSource = Get-SourcePath 'BashAutorun'
    Write-Debug "${fn}: `$BashAutorunScriptSource='$BashAutorunScriptSource'"
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    Write-Debug "${fn}: `$BashAutorunScriptTarget='$BashAutorunScriptTarget'"
    #endregion WSL Autorun Script Path

    #region Save Parameters to .wslconfig
    if ($null -ne $GatewayIpAddress) {
        $DNSServerList = [string]::IsNullOrWhiteSpace($DNSServerList) ? $GatewayIpAddress : $DNSServerList
        Write-Debug "${fn}: Seting Wsl Network Parameters: GatewayIpAddress=$GatewayIpAddress PrefixLength=$PrefixLength DNSServerList=$DNSServerList"
        Set-WslNetworkParameters -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList

        Set-WslNetworkAdapter
    }

    if ($null -ne $WslInstanceIpAddress) {
        $null = Test-ValidStaticIpAddress $WslInstanceIpAddress -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength

        Write-Debug "${fn}: Seting Wsl Config Value: SectionName=$(Get-StaticIpAddressesSectionName) KeyName=$WslInstanceName Value=$($WslInstanceIpAddress.IPAddressToString)"

        Set-WslConfigValue (Get-StaticIpAddressesSectionName) $WslInstanceName $WslInstanceIpAddress.IPAddressToString -UniqueValue

        $WslHostIpOrOffset = $WslInstanceIpAddress.IPAddressToString
    }
    else {
        $WslIpOffset = Get-WslIpOffset $WslInstanceName
        Write-Verbose "Setting Automatic Ip Offset: $WslIpOffset for $WslInstanceName."
        Set-WslIpOffset $WslInstanceName $WslIpOffset

        $WslHostIpOrOffset = $WslIpOffset
    }

    Write-WslConfig -Backup:$BackupWslConfig
    #endregion Save Parameters to .wslconfig

    #region Run Bash Installation Script
    $BashInstallScriptWslPath = '$(wslpath "' + "$BashInstallScript" + '")'
    $BashInstallParams = @("`"$BashAutorunScriptSource`"", "$BashAutorunScriptTarget",
        "`"$WinHostsEditScript`"", "$WindowsHostName", "$WslHostName", "$WslHostIpOrOffset"
    )
    Write-Verbose "Running WSL installation script $BashInstallScript"

    wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' $debug_var $verbose_var bash $BashInstallScriptWslPath @BashInstallParams
    #endregion Run Bash Installation Script

    #region Set Content to Powershell Profile
    Set-ProfileContent
    #endregion Set Content to Powershell Profile

    #region Restart WSL Instance
    wsl.exe -t $WslInstanceName
    #endregion Restart WSL Instance

    #region Test IP and host Assignments
    try {
        Test-WslInstallation -WslInstanceName $WslInstanceName -WslHostName $WslHostName -WindowsHostName $WindowsHostName
    }
    catch {
        throw
        exit 1
    }
    finally {
        wsl.exe -t $WslInstanceName
    }

    #endregion Test IP and host Assignments

    Write-Host "PowerShell Successfully Installed WSL-IpHandler to $WslInstanceName."
}

function Uninstall-WSLIpHandler {
    [CmdletBinding()]
    param (
        [AllowNull()][AllowEmptyString()]
        [ArgumentCompleter(
            {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                Get-CommandOutputInUTF16AsUTF8 'wsl.exe' '-l' |
                    Select-Object -Skip 1 |
                    Where-Object { $_ -like "*${wordToComplete}*" } |
                    ForEach-Object {
                        $res = $_ -split ' ' | Select-Object -First 1
                        New-Object System.Management.Automation.CompletionResult (
                            $res,
                            $res,
                            'ParameterValue',
                            $res
                        )
                    }
            }
        ) ]
        [Alias('Name')]
        [string]$WslInstanceName,

        [switch]$BackupWslConfig
    )
    $debug_var = if ($DebugPreference -eq 'Continue') { 'DEBUG=1' } else { '' }
    $verbose_var = if ($VerbosePreference -eq 'Continue') { 'VERBOSE=1' } else { '' }

    Write-Host "PowerShell Uninstalling WSL-IpHandler from $WslInstanceName..."
    #region Bash Installation Script Path
    $BashUninstallScript = Get-SourcePath 'BashUninstall'
    #endregion Bash Installation Script Path

    #region WSL Autorun
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptName = Split-Path -Leaf (Get-SourcePath 'BashAutorun')
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    #endregion WSL Autorun

    #region Remove Bash Autorun
    $BashUninstallScriptWslPath = '$(wslpath "' + "$BashUninstallScript" + '")'
    $BashUninstallParams = "$BashAutorunScriptName", "$BashAutorunScriptTarget"

    Write-Verbose "Running WSL Uninstallation script $BashUninstallScript"
    Write-Debug "`$DebugPreference=$DebugPreference"
    Write-Debug "`$VerbosePreference=$VerbosePreference"

    wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' $debug_var $verbose_var bash $BashUninstallScriptWslPath @BashUninstallParams
    #endregion Remove Bash Autorun

    #region Restart WSL Instance
    wsl.exe -t $WslInstanceName
    #endregion Restart WSL Instance

    #region Remove Content from Powershell Profile
    Remove-ProfileContent
    #endregion Remove Content from Powershell Profile

    #region Remove WSL Network Configuration
    Remove-WslNetworkParameters -BackupWslConfig:$BackupWslConfig
    #endregion Remove WSL Network Configuration

    Write-Host "PowerShell Successfully Uninstalled WSL-IpHandler from $WslInstanceName."
}

function Set-ProfileContent {
    [CmdletBinding()]
    param($ProfilePath = $profile.CurrentUserAllHosts)
    $handlerContent = (Get-ProfileContent)
    $content = (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue) ?? @()
    $content += $handlerContent
    Set-Content -Path $ProfilePath -Value $content -Force
}

function Remove-ProfileContent {
    [CmdletBinding()]
    param($ProfilePath = $profile.CurrentUserAllHosts)
    $handlerContent = (Get-ProfileContent)
    $content = (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue) ?? @()
    if ($content) {
        $content = ($content -join "`n") -replace ($handlerContent -join "`n")
        Set-Content -Path $ProfilePath -Value $content -Force
    }
}

function Set-WslNetworkParameters {
    param (
        [Parameter(Mandatory)][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [switch]$BackupWslConfig
    )
    Set-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) $GatewayIpAddress.IPAddressToString

    Set-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) $PrefixLength

    Set-WslConfigValue (Get-NetworkSectionName) (Get-DnsServersKeyName) $DNSServerList

    Write-WslConfig -Backup:$BackupWslConfig
}

function Remove-WslNetworkParameters {
    [CmdletBinding()]
    param ( [switch]$BackupWslConfig )
    Remove-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName)

    Remove-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName)

    Remove-WslConfigValue (Get-NetworkSectionName) (Get-DnsServersKeyName)

    Write-WslConfig -Backup:$BackupWslConfig
}

function Set-WslNetworkAdapter {
    param(
        [Parameter()][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter()][Alias('Prefix')]
        [int]$IpAddressPrefixLength,

        [Parameter()][Alias('DNS')]
        [string]$DNSServerList  # Comma separated ipaddresses/hosts
    )
    $fn = $MyInvocation.MyCommand.Name
    $networkSectionName = (Get-NetworkSectionName)

    $GatewayIpAddress ??= Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-GatewayIpAddressKeyName)

    $PrefixLength = $PSBoundParameters.ContainsKey('PrefixLength') ? $PrefixLength : (Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-PrefixLengthKeyName) -DefaultValue 24)

    $DNSServerList = [string]::IsNullOrWhiteSpace($DNSServerList) ? (Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-DnsServersKeyName) -DefaultValue $GatewayIpAddress) : $DNSServerList

    $wslAdapter = Get-NetIPAddress -InterfaceAlias 'vEthernet (WSL)' -AddressFamily IPv4 -ErrorAction SilentlyContinue

    Write-Debug "${fn}: `$GatewayIpAddress='$GatewayIpAddress'; `$PrefixLength=$PrefixLength;"
    Write-Debug "${fn}: `$DNSServerList='$DNSServerList'; `$wslAdapter=$wslAdapter;"

    if ($null -ne $wslAdapter) {
        Write-Debug "${fn}: WSL Hyper-V VM Adapter already exists."
        $currentIpAddress = $wslAdapter.IPAddress
        $currentPrefixLength = $wslAdapter.PrefixLength

        $ipcalc = Join-Path $PSScriptRoot 'IP-Calc.ps1' -Resolve
        $currentIpObj = (& $ipcalc -IpAddress $currentIpAddress -PrefixLength $currentPrefixLength)
        $requiredIpObj = (& $ipcalc -IpAddress $GatewayIpAddress -PrefixLength $PrefixLength)

        if ($currentIpAddress -eq $GatewayIpAddress -and $($currentIpObj.CIDR) -eq ($requiredIpObj.CIDR)) {
            Write-Debug "${fn}: WSL Adapter with IpAddress/Prefix: '$($currentIpObj.CIDR)' and GatewayAddress: '$currentIpAddress' already exists!"
            return
        }
    }

    Write-Debug "${fn}: Shutting down all WSL isntances..."
    wsl.exe --shutdown

    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve)
    $adapterScript = Join-Path $PSScriptRoot 'Set-WSLNetworkAdapter.ps1' -Resolve
    $scriptArguments = @($GatewayIpAddress, $PrefixLength, $DNSServerList)

    if (IsElevated) {
        . $adapterScript @scriptArguments
    }
    else {
        Invoke-ScriptElevated $adapterScript $scriptArguments
    }

    Write-Verbose 'Created WSL Network Adapter with parameters:'
    Write-Verbose "GatewayIpAddress : $GatewayIpAddress"
    Write-Verbose "PrefixLength     : $PrefixLength"
    Write-Verbose "DNSServerList    : $DNSServerList"
}

function Remove-WslNetworkAdapter {
    [CmdletBinding()]
    param()
    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve)
    $adapterScript = Join-Path $PSScriptRoot 'Remove-WslNetworkAdapter.ps1' -Resolve

    if (IsElevated) {
        . $adapterScript
    }
    else {
        Invoke-ScriptElevated $adapterScript
    }
    Write-Verbose 'Removed WSL Network Adapter.'
}

function Test-WslInstallation {
    param (
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$WslInstanceName,

        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [ValidateNotNullOrEmpty()]
        [string]$WindowsHostName
    )
    $failed = $false
    $error_message = @(
        "PowerShell finished installation of WSL-IpHandler to $WslInstanceName with errors:"
    )

    $testCommand = "ping -c1 $WindowsHostName"
    Write-Debug "Testing Ping from WSL instance ${WslInstanceName}: `"$testCommand`""
    $wslTest = (wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$testCommand`")

    if (! ($wslTest -match ', 0% packet loss')) {
        $failed = $true
        $error_message += "Pinging $WindowsHostName from $WslInstanceName Failed with error:`n$wslTest`n"
    }

    # Before testing WSL IP address - make sure WSL Instance is up and running
    if (-not (Get-WslIsRunning $WslInstanceName)) {
        $runCommand = 'exit'  # Even after 'exit' wsl instance should be running in background
        Write-Debug "Running WSL instance $WslInstanceName for testing ping from Windows."
        wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$runCommand`"
    }

    if (Get-WslIsRunning $WslInstanceName) {
        $windowsTest = $(ping -n 1 $WslHostName)

        if ( ! ($windowsTest -match 'Lost = 0 \(0% loss\)')) {
            $failed = $true
            $error_message += "Pinging $WslHostName from windows Failed with error:`n$windowsTest`n"
        }
    }
    else {
        $failed = $true
        $error_message += "Could not start WSL Instance: $WslInstanceName to test Ping from Widnows"
    }

    if ($failed) {
        Write-Error ($error_message -join "`n") -ErrorAction Stop
    }
}

function Invoke-WslStatic {
    function ArgsAreExec {
        param($arguments)
        $nonExecArgs = @(
            '-l', '--list',
            '--shutdown',
            '--terminate', '-t',
            '--status',
            '--update',
            '--set-default', '-s'
            '--help',
            '--install',
            '--set-default-version',
            '--export',
            '--import',
            '--set-version',
            '--unregister'
        )
        $allArgsAreExec = $true
        foreach ($a in $arguments) {
            if ($a -in $nonExecArgs) {
                $allArgsAreExec = $false
                break
            }
        }
        $allArgsAreExec
    }
    $fn = $MyInvocation.MyCommand.Name
    $args_copy = $args.Clone()

    $DebugPreferenceOriginal = $DebugPreference
    if ('-debug' -in $args_copy) {
        $DebugPreference = 'Continue'
        $args_copy = $args_copy | Where-Object { $_ -notlike '-debug' }
    }

    if ($args_copy.Count -eq 0 -or (ArgsAreExec $args_copy)) {
        Write-Debug "${fn}: `$args: $args_copy"
        Write-Debug "${fn}: Passed arguments require Setting WSL Netwrok Adapter."

        Set-WslNetworkAdapter
    }

    Write-Debug "${fn}: Invoking wsl.exe $args_copy"
    $DebugPreference = $DebugPreferenceOriginal
    & wsl.exe @args_copy
}

Set-Alias wsl Invoke-WslStatic
