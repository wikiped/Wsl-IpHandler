
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
        [int]$IpAddressPrefixLength = 24,

        [Parameter(ParameterSetName = 'Static')][Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Parameter(ParameterSetName = 'Dynamic')][ValidateRange(1, 254)]
        [Alias('Offset')]
        [int]$WslIpOffset,

        [AllowNull()]
        [string]$WslHostName = $WslInstanceName,

        [string]$WindowsHostName = 'windows',

        [switch]$BackupWslConfig
    )
    $debug_var = if ($DebugPreference -eq 'Continue') { 'DEBUG=1' } else { '' }
    $verbose_var = if ($VerbosePreference -eq 'Continue') { 'VERBOSE=1' } else { '' }


    Write-Host "PowerShell Installing WSL-IpHandler to $WslInstanceName..."
    #region PS Autorun
    # Get Path to PS Script that injects (if needed) IP-host to windows hosts on every WSL launch
    $WinHostsEditScript = Get-SourcePath 'WinHostsEdit'
    #endregion PS Autorun

    #region Bash Installation Script Path
    $BashInstallScript = Get-SourcePath 'BashInstall'
    #endregion Bash Installation Script Path

    #region WSL Autorun Script Path
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptSource = Get-SourcePath 'BashAutorun'
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    #endregion WSL Autorun Script Path

    #region Save Parameters to .wslconfig
    switch ($PsCmdlet.ParameterSetName) {
        'Dynamic' {
            if (-not $PSBoundParameters.ContainsKey('WslIpOffset')) {
                $WslIpOffset = Get-IpOffset $WslInstanceName
                Write-Verbose "Automatic Ip Offset: $WslIpOffset for $WslInstanceName."
            }

            Write-Verbose "Setting Ip Offset: $WslIpOffset for $WslInstanceName."
            Set-IpOffset $WslInstanceName $WslIpOffset -BackupWslConfig:$BackupWslConfig
            break
        }
        'Static' {
            break
        }
        Default {}
    }
    #endregion Save Parameters to .wslconfig

    #region Run Bash Installation Script
    $BashInstallScriptWslPath = '$(wslpath "' + "$BashInstallScript" + '")'
    $BashInstallParams = @("`"$BashAutorunScriptSource`"", "$BashAutorunScriptTarget",
        "`"$WinHostsEditScript`"", "$WindowsHostName", "$WslHostName", $WslIpOffset)
    Write-Verbose "Running WSL installation script $BashInstallScript"

    wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' $debug_var $verbose_var bash $BashInstallScriptWslPath @BashInstallParams
    #endregion Run Bash Installation Script

    #region Restart WSL Instance
    wsl.exe -t $WslInstanceName
    #endregion Restart WSL Instance

    #region Test IP and host Assignments
    $failed = $false
    $error_message = @(
        "PowerShell finished installation of WSL-IpHandler to $WslInstanceName with errors:"
    )

    $testCommand = "ping -c1 $WindowsHostName"
    Write-Debug "Test Ping command from WSL: `"$testCommand`""
    $wslTest = (wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$testCommand`")

    if (! ($wslTest -match ', 0% packet loss')) {
        $failed = $true
        $error_message += "Pinging $WindowsHostName from $WslInstanceName Failed with error:`n$wslTest`n"
    }

    # Before testing WSL IP address - make sure WSL Instance is up and running
    if (-not (Get-WslIsRunning $WslInstanceName)) {
        $runCommand = 'exit'  # Evan after 'exit' wsl instance should be running in background
        Write-Debug "Running WSL instance $WslInstanceName for testing ping from Windows."
        wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$runCommand`"
    }

    $windowsTest = $(ping -n 1 $WslHostName)

    if ( ! ($windowsTest -match 'Lost = 0 \(0% loss\)')) {
        $failed = $true
        $error_message += "Pinging $WslHostName from windows Failed with error:`n$windowsTest`n"
    }

    if ($failed) {
        Write-Error ($error_message -join "`n") -ea Stop
        exit 1
    }

    wsl.exe -t $WslInstanceName
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
        [string]$WslInstanceName
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

    Write-Host "PowerShell Successfully Uninstalled WSL-IpHandler from $WslInstanceName."
}

function Invoke-WslStatic {
    function ArgsAreExec {
        param($argumnets)
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
        foreach ($a in $argumnets) {
            if ($a -in $nonExecArgs) {
                $allArgsAreExec = $false
                break
            }
        }
        $allArgsAreExec
    }

    if ($args.Count -eq 0 -or (ArgsAreExec $args)) {
        $networkSectionName = (Get-NetworkSectionName)

        $GatewayIpAddress = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-GatewayIpAddressKeyName)

        $IpAddressPrefixLength = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-PrefixLengthKeyName) -DefaultValue 24

        $DNSServerList = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-DnsServersKeyName) -DefaultValue $GatewayIpAddress

        . (Join-Path $PSScriptRoot 'Set-WSLNetworkAdapter.ps1') $GatewayIpAddress $IpAddressPrefixLength $DNSServerList
    }
    Write-Host "Starting 'wsl.exe $args'"
}
