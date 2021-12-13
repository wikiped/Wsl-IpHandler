#Requires -Version 7.1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Scripts\Powershell\ArgumentsCompleters.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'Scripts\Powershell\WindowsCommandsUTF16Converters.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsWslConfig.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsHostsFile.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsPrivateData.ps1' -Resolve) | Out-Null

$vEthernetWsl = 'vEthernet (WSL)'

#region Debug Functions
# if (!(Test-Path function:\_@)) {
function _@ {
    $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
    $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
    "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
}
# }
#endregion Debug Functions

function Install-WslIpHandler {
    <#
    .SYNOPSIS
    Installs WSL IP Addresses handler into a specified WSL Instance

    .DESCRIPTION
    Installs WSL IP Addresses handler into a specified WSL Instance optionally with specific IP address within certain Subnet.

    There are 2 modes of operations:
      - Dynamic
      - Static

    To operate in the Dynamic Mode the only required parameter is WslInstanceName.
    In this mode the following will happen:
    @ specified WSL instance's file system:
        a) a new script will be created: /usr/local/bin/wsl-iphandler.sh
        b) a new startup script created: /etc/profile.d/run-wsl-iphandler.sh. This actually start script in a).
        c) sudo permission will be created at: /etc/sudoers.d/wsl-iphandler to enable passwordless start of script a).
        d) /etc/wsl.conf will be modified to store Host names / IP offset
    @ Windows host file system:
        a) New [ip_offsets] section in ~/.wslconfig will be created to store ip_offset for a specified WSL Instance. This offset will be used by bash startup script to create an IP Address at start time.
        b) When bash startup script on WSL instance side is executed it will create (if not present already) a record binding its current IP address to it's host name (which is set by WslHostName parameter)

    To operate in Static Mode at the very least one parameter has to be specified: GatewayIpAddress.
    In this mode the following will happen:
    @ specified WSL instance's file system:
        a) the same scripts will be created as in Static Mode.
        b) /etc/wsl.conf will be modified to store Host names / IP Addresses
           Note that if parameter WslInstanceIpAddress is not specified a first available IP address will be selected and will be used until the WSL-IpHandler is Uninstalled. Otherwise specified IP address will be used.
    @ Windows host file system:
        a) New [static_ips] section in ~/.wslconfig will be created to store ip address for a specified WSL Instance. This ip address will be used by bash startup script to bind this IP Address at start time to eth0 interface.
        b) The same as for Static Mode.
        c) Powershell profile file (CurrentUserAllHosts) will be modified: This module will be imported and an alias `wsl` to Invoke-WslExe will be created).

    .PARAMETER WslInstanceName
    Required. Name of the WSL Instance as listed by `wsl.exe -l` command

    .PARAMETER GatewayIpAddress
    Optional. IP v4 Address of the gateway. This IP Address will appear in properties of Network Adapter (vEthernet (WSL)).

    .PARAMETER PrefixLength
    Optional. Defaults to 24. Length of WSL Subnet.

    .PARAMETER DNSServerList
    Optional. Defaults to GatewayIpAddress.

    .PARAMETER WslInstanceIpAddress
    Optional. Static IP Address of WSL Instance. It will be assigned to the instance when it starts. This address will be also added to Windows HOSTS file so that a given WSL Instance can be accessed via its WSLHostName.

    .PARAMETER WslHostName
    Optional. Defaults to WslInstanceName. The name to use to access the WSL Instance on WSL SubNet. This name together with WslInstanceIpAddress are added to Windows HOSTS file.

    .PARAMETER WindowsHostName
    Optional. Defaults to `windows`. Name of Windows Host that can be used to access windows host from WSL Instance. This will be added to /etc/hosts on WSL Instance system.

    .PARAMETER DontModifyPsProfile
    Optional. If specifies will not modify Powershell Profile (default profile: CurrentUserAllHosts). Otherwise profile will be modified to Import this module and create an Alias `wsl` which will transparently pass through any and all paramaters to `wsl.exe` and, if necessary, initialize beforehand WSL Hyper-V network adapter to allow usage of Static IP Addresses. Will be ignored in Dynamic Mode.

    .PARAMETER UseScheduledTaskOnUserLogOn
    When present - a new Scheduled Task will be created: WSL-IpHandlerTask. It will be triggered at user LogOn. This task execution is equivalent to running Set-WslNetworkAdapter command. It will create WSL Hyper-V Network Adapter when user Logs On.

    .PARAMETER AnyUserLogOn
    When this parameter is present - The Scheduled Task will be set to run when any user logs on. Otherwise (default behavior) - the task will run only when current user (who executed Install-WslIpHandler command) logs on.

    .PARAMETER BackupWslConfig
    Optional. If specified will create backup of ~/.wslconfig before modifications.

    .EXAMPLE
    ------------------------------------------------------------------------------------------------
    Install-WslIpHandler -WslInstanceName Ubuntu

    Will install WSL IP Handler in Dynamic Mode. IP address of WSL Instance will be set when the instance starts and address will be based on whatever SubNet will be set by Windows system.
    This IP address might be different after Windows restarts as it depends on what Gateway IP address Windows assigns to vEthernet (WSL) network adapter.
    The actual IP address of WSL Instance can always be checked with command: `hostname -I`.

    ------------------------------------------------------------------------------------------------
    Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1

    Will install WSL IP Handler in Static Mode. IP address of WSL Instance will be set automatically to the first available in SubNet 172.16.0.0/24, excluding Gateway IP address.
    From WSL Instance shell prompt Windows Host will be accessible at 172.16.0.1 or simply as `windows`, i.e. two below commands will yield the same result:
    ping 172.16.0.1
    ping windows

    ------------------------------------------------------------------------------------------------
    Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.2

    Will install WSL IP Handler in Static Mode. IP address of WSL Instance will be set to 172.16.0.2. This IP Address will stay the same as long as wsl instance is started through this module's alias `wsl` (which shadows `wsl` command) and until Uninstall-WslIpHandler is executed.

    .NOTES
    Use Powershell command prompt to launch WSL Instance(s) in Static Mode, especially after system restart.
    Executing `wsl.exe` from within Windows cmd.exe after Windows restarts will allow Windows to take control over WSL network setup and will break Static IP functionality.

    To mannerly take control over WSL Network setup use this module's command: Set-WslNetworkConfig
    #>
    param (
        [Parameter(Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'Dynamic')]
        [Parameter(ParameterSetName = 'Static')]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter(Mandatory, ParameterSetName = 'Static')][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Static')][Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Parameter(ParameterSetName = 'Static')][Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Parameter(ParameterSetName = 'Static')][Alias('IpAddress')]
        [ipaddress]$WslInstanceIpAddress,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [Parameter()]
        [string]$WindowsHostName = 'windows',

        [Parameter(ParameterSetName = 'Static')]
        [Alias('NoProfile')]
        [switch]$DontModifyPsProfile,

        [Parameter(ParameterSetName = 'Static')]
        [Alias('Logon')]
        [Alias('Task')]
        [switch]$UseScheduledTaskOnUserLogOn,

        [Parameter(ParameterSetName = 'Static')]
        [Alias('AnyUser')]
        [switch]$AnyUserLogOn,

        [Parameter()]
        [Alias('Backup')]
        [switch]$BackupWslConfig,

        [Parameter(ParameterSetName = 'Static')]
        [string[]]$DynamicAdapters = @('Ethernet', 'Default Switch')
    )
    Write-Host "PowerShell installing WSL-IpHandler to $WslInstanceName..."
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    # $PSDefaultParameterValues['*:Verbose'] = $VerbosePreference -eq 'Continue'
    # $PSDefaultParameterValues['*:Debug'] = $DebugPreference -eq 'Continue'

    #region Save Network Parameters to .wslconfig and Setup Network Adapters
    $configModified = $false

    Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -DynamicAdapters $DynamicAdapters -WindowsHostName $WindowsHostName -Modified ([ref]$configModified)

    if ($null -ne $GatewayIpAddress) {
        Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
        $setParams = @{
            GatewayIpAddress            = $GatewayIpAddress
            PrefixLength                = $PrefixLength
            DNSServerList               = $DNSServerList
            DynamicAdapters             = $DynamicAdapters
            WaitForWslNetworkConnection = $true
        }
        Set-WslNetworkAdapter @setParams -Verbose:$($VerbosePreference -eq 'Continue')

        Write-Verbose "Setting Static IP Address: $($WslInstanceIpAddress.IPAddressToString) for $WslInstanceName."
        Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -WslInstanceIpAddress $WslInstanceIpAddress.IPAddressToString -Modified ([ref]$configModified)

        if ($UseScheduledTaskOnUserLogOn) {
            Write-Verbose 'Registering WSL-IpHandler scheduled task...'
            $taskParams = @{
                WaitForWslNetworkConnection = $true
                ShowToast                   = $true
                AnyUserLogOn                = $AnyUserLogOn
            }
            Set-WslScheduledTask @taskParams
        }
    }
    else {
        $WslIpOffset = Get-WslConfigIpOffset $WslInstanceName
        if (-not $WslIpOffset) {
            $WslIpOffset = Get-WslConfigAvailableIpOffset
            Write-Verbose "Setting Automatic IP Offset: $WslIpOffset for $WslInstanceName."
            Set-WslConfigIpOffset $WslInstanceName $WslIpOffset -Modified ([ref]$configModified)
        }
    }

    if ($configModified) {
        Write-Verbose "Saving Configuration in .wslconfig $($BackupWslConfig ? 'with Backup ' : '')..."
        Write-WslConfig -Backup:$BackupWslConfig
    }
    #endregion Save Network Parameters to .wslconfig and Setup Network Adapters

    #region Bash Scripts Installation
    Install-WslBashScripts -WslInstanceName $WslInstanceName -WslHostName $WslHostName
    #endregion Bash Scripts Installation

    #region Set Content to Powershell Profile
    if ($PSCmdlet.ParameterSetName -eq 'Static' -and -not $DontModifyPsProfile) {
        Write-Verbose "Modifying Powershell Profile: $($profile.CurrentUserAllHosts) ..."
        Set-ProfileContent
    }
    #endregion Set Content to Powershell Profile

    #region Restart WSL Instance
    Write-Verbose "Terminating running instances of $WslInstanceName ..."
    wsl.exe -t $WslInstanceName
    #endregion Restart WSL Instance

    #region Test IP and host Assignments
    try {
        Write-Verbose "Testing Activation of WSL IP Handler on $WslInstanceName ..."
        Test-WslInstallation -WslInstanceName $WslInstanceName -WslHostName $WslHostName -WindowsHostName $WindowsHostName
    }
    catch {
        Write-Host "PowerShell finished installation of WSL-IpHandler to $WslInstanceName with Errors:"
        Write-Debug "$(_@) ScriptStackTrace: $($_.ScriptStackTrace)"
        Write-Host "$_" -ForegroundColor Red
        return
    }
    finally {
        Write-Verbose 'Finished Testing Activation of WSL IP Handler.'
        wsl.exe -t $WslInstanceName
    }
    #endregion Test IP and host Assignments

    Write-Host "PowerShell successfully installed WSL-IpHandler to $WslInstanceName."
}

function Uninstall-WslIpHandler {
    <#
    .SYNOPSIS
    Uninstall WSL IP Handler from WSL Instance

    .DESCRIPTION
    Uninstall WSL IP Handler from WSL Instance with the specified name.

    .PARAMETER WslInstanceName
    Required. Name of the WSL Instance to Uninstall WSL Handler from (should be one of the names listed by `wsl.exe -l` command).

    .PARAMETER BackupWslConfig
    Optional. If specified ~/.wslconfig file will backed up before modifications.

    .EXAMPLE
    Uninstall-WslIpHandler -WslInstanceName Ubuntu

    .NOTES
    When the instance specified in WslInstanceName parameter is the LAST one (there are no other instances for which static IP address has been assigned) This command will also reset
    #>
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$WslInstanceName,

        [switch]$BackupWslConfig
    )
    Write-Host "PowerShell Uninstalling WSL-IpHandler from $WslInstanceName..."

    #region Bash Scripts UnInstallation
    Uninstall-WslBashScripts -WslInstanceName $WslInstanceName
    #endregion Bash Scripts UnInstallation

    #region Restart WSL Instance
    wsl.exe -t $WslInstanceName
    Write-Debug "$(_@) Restarted $WslInstanceName"
    #endregion Restart WSL Instance

    #region Remove WSL Instance Static IP from .wslconfig
    $wslconfigModified = $false
    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -Modified ([ref]$wslconfigModified)
    #endregion Remove WSL Instance Static IP from .wslconfig

    #region Remove WSL Instance IP Offset from .wslconfig
    Write-Debug "$(_@) Removing IP address offset for $WslInstanceName from .wslconfig..."
    Remove-WslConfigIpOffset -WslInstanceName $WslInstanceName -Modified ([ref]$wslconfigModified)
    #endregion Remove WSL Instance IP Offset from .wslconfig

    #region Remove WSL Instance IP from windows hosts file
    $hostsModified = $false
    Write-Debug "$(_@) Removing record for $WslInstanceName from Windows Hosts ..."
    $content = (Get-HostsFileContent)
    Write-Debug "$(_@) Removing Host: $WslInstanceName from $($content.Count) Windows Hosts records ..."
    $content = Remove-HostFromRecords -Records $content -HostName $WslInstanceName -Modified ([ref]$hostsModified)
    Write-Debug "$(_@) Setting Windows Hosts file with $($content.Count) records ..."
    #endregion Remove WSL Instance IP from windows hosts file

    #region Save Modified .wslconfig and hosts Files
    if ($hostsModified) { Write-HostsFileContent -Records $content }
    #endregion Save Modified .wslconfig and hosts Files

    #region Remove Network Config and Content from Powershell Profile and ScheduledTask
    # Clean .wslconfig, PSProfile and ScheduledTask if there are no more Static IP assignments
    if ((Get-WslConfigStaticIpSection).Count -eq 0) {
        Write-Debug "$(_@) No Static IPs found in .wslconfig."

        #region Remove WSL Network Configuration from .wslconfig
        Write-Debug "$(_@) Removing WSL Network Configuration for $WslInstanceName ..."
        Remove-WslNetworkConfig -Modified ([ref]$wslconfigModified)
        #endregion Remove WSL Network Configuration from .wslconfig

        Write-Debug "$(_@) Removing Powershell Profile Modifications ..."
        Remove-ProfileContent

        Write-Debug "$(_@) Removing Scheduled Task ..."
        Remove-WslScheduledTask -CheckRemoval
    }
    else {
        Write-Debug "$(_@) Skipping Removal of Network Config, Powershell Profile modifications and ScheduledTaskThere because there are Static IPs remaining:"
        Write-Debug "$(_@) $(Get-WslConfigStaticIpSection | Out-String)"
    }
    if ($wslconfigModified) { Write-WslConfig -Backup:$BackupWslConfig }
    #endregion Remove Network Config and Content from Powershell Profile and ScheduledTask

    Write-Host "PowerShell successfully uninstalled WSL-IpHandler from $WslInstanceName!"
}

function Install-WslBashScripts {
    <#
    .SYNOPSIS
    Installs (copies) Bash scripts to specified WSL Instance

    .DESCRIPTION
    Installs (copies) Bash scripts to specified WSL Instance to enable IP address determinism.

    .PARAMETER WslInstanceName
    Required. Name of the WSL Instance as listed by `wsl.exe -l` command

    .PARAMETER WslHostIpOrOffset
    Required. Either Static IP Address

    .PARAMETER WslHostName
    Optional. Defaults to WslInstanceName. The name to use to access the WSL Instance on WSL SubNet. This name together with WslInstanceIpAddress are added to Windows HOSTS file.

    .EXAMPLE
    Install-WslBashScripts -WslInstanceName Ubuntu

    Will read saved configuration from .wslconfig and use this setting to apply to Ubuntu WSL Instance.

    .NOTES
    This command can only be used AFTER `Install-WslIpHandler` command was used to setup network configuration.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [Parameter()]
        [switch]$BashVerbose,

        [Parameter()]
        [switch]$BashDebug
    )
    #region Read WSL config
    $existingIp = Get-WslConfigStaticIpAddress -WslInstanceName $WslInstanceName
    if ($existingIp) {
        Write-Debug "$(_@) Existing Static IP Address for $WslInstanceName = $existingIp"
        $WslHostIpOrOffset = "$existingIp"
    }
    else {
        Write-Debug "$(_@) Static IP Address for $WslInstanceName not found Querying for Offset."
        $WslIpOffset = Get-WslConfigIpOffset $WslInstanceName
        if ($WslIpOffset) {
            $WslHostIpOrOffset = $WslIpOffset
        }
        else {
            $msg = "Neither Static IP Address nor IP Offset are configured for '$WslInstanceName'. Please run `Install-WslIpHandler` to set either Static IP Address or Offset before using this command."
            Throw "$msg"
        }
    }
    $WindowsHostName = Get-WslConfigValue -SectionName (Get-NetworkSectionName) -KeyName (Get-WindowsHostNameKeyName) -DefaultValue 'windows'
    Write-Debug "$(_@) `$WindowsHostName='$WindowsHostName'"
    #endregion Read WSL config

    #region Bash Installation Script Path
    $BashInstallScript = Get-SourcePath 'BashInstall'
    Write-Debug "$(_@) `$BashInstallScript='$BashInstallScript'"
    #endregion Bash Installation Script Path

    #region WSL Autorun Script Path
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptSource = Get-SourcePath 'BashAutorun'
    Write-Debug "$(_@) `$BashAutorunScriptSource='$BashAutorunScriptSource'"
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    Write-Debug "$(_@) `$BashAutorunScriptTarget='$BashAutorunScriptTarget'"
    #endregion WSL Autorun Script Path

    #region PS Autorun
    # Get Path to PS Script that injects (if needed) IP-host to windows hosts on every WSL launch
    $WinHostsEditScript = Get-SourcePath 'WinHostsEdit'
    Write-Debug "$(_@) `$WinHostsEditScript='$WinHostsEditScript'"
    #endregion PS Autorun

    #region Run Bash Installation Script
    Write-Verbose "Running Bash WSL Install script $BashInstallScript"
    Write-Debug "$(_@) `$DebugPreference=$DebugPreference"
    Write-Debug "$(_@) `$VerbosePreference=$VerbosePreference"

    $bashInstallScriptWslPath = '$(wslpath "' + "$BashInstallScript" + '")'
    $bashCommand = @(
        $bashInstallScriptWslPath,
        "`"$BashAutorunScriptSource`""
        "$BashAutorunScriptTarget"
        "`"$WinHostsEditScript`""
        "$WindowsHostName"
        "$WslHostName"
        "$WslHostIpOrOffset"
    )

    $envVars = @()
    if ($DebugPreference -gt 0) { $envVars += 'DEBUG=1' }
    if ($VerbosePreference -gt 0) { $envVars += 'VERBOSE=1' }

    $bashArgs = @()
    if ($BashVerbose) { $bashArgs += '--verbose' }
    if ($BashDebug) { $bashArgs += '--debug' }

    Write-Debug "$(_@) Invoking: wsl.exe -d $WslInstanceName sudo -E env '`"PATH=`$PATH`"' $envVars bash $bashArgs $bashCommand"
    $bashInstallScriptOutput = wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' @envVars bash @bashArgs @bashCommand

    if ($DebugPreference -gt 0 -or $VerbosePreference -gt 0) {
        Write-Host "$($bashInstallScriptOutput -join "`n")"
    }
    if ($bashInstallScriptOutput -and ($bashInstallScriptOutput | Where-Object { $_.StartsWith('[Error') } | Measure-Object).Count -gt 0) {
        Write-Error "Error(s) occurred while running Bash Installation script: $bashCommand`n$($bashInstallScriptOutput -join "`n")"
        return
    }
    Write-Debug "$(_@) Installed Bash scripts."
    Write-Verbose 'Installed Bash scripts.'
    #endregion Run Bash Installation Script
}

function Uninstall-WslBashScripts {
    <#
    .SYNOPSIS
    Uninstalls (deletes) Bash scripts from specified WSL Instance.

    .DESCRIPTION
    Uninstalls (deletes) Bash scripts and removes all modifications made by this module to the specified WSL Instance.

    .PARAMETER WslInstanceName
    Required. Name of the WSL Instance as listed by `wsl.exe -l` command

    .EXAMPLE
    Uninstall-WslBashScripts Ubuntu

    Will remove all Bash scripts and all modifications made to Ubuntu WSL Instance.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [switch]$BashVerbose,

        [Parameter()]
        [switch]$BashDebug
    )
    #region Bash UnInstallation Script Path
    $BashUninstallScript = Get-SourcePath 'BashUninstall'
    #endregion Bash InInstallation Script Path

    #region WSL Autorun
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptName = Split-Path -Leaf (Get-SourcePath 'BashAutorun')
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    #endregion WSL Autorun

    #region Remove Bash Autorun
    Write-Verbose "Running Bash WSL Uninstall script $BashUninstallScript"
    Write-Debug "$(_@) `$DebugPreference=$DebugPreference"
    Write-Debug "$(_@) `$VerbosePreference=$VerbosePreference"

    $bashUninstallScriptWslPath = '$(wslpath "' + "$BashUninstallScript" + '")'
    $bashCommand = @(
        "$bashUninstallScriptWslPath"
        "$BashAutorunScriptName"
        "$BashAutorunScriptTarget"
    )

    $envVars = @()
    if ($DebugPreference -gt 0) { $envVars += 'DEBUG=1' }
    if ($VerbosePreference -gt 0) { $envVars += 'VERBOSE=1' }

    $bashArgs = @()
    if ($BashVerbose) { $bashArgs += '--verbose' }
    if ($BashDebug) { $bashArgs += '--debug' }

    Write-Debug "$(_@) Invoking: wsl.exe -d $WslInstanceName sudo -E env '`"PATH=`$PATH`"' $envVars bash $bashArgs $bashCommand"
    $bashUninstallScriptOutput = wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' @envVars bash @bashArgs @bashCommand

    if ($DebugPreference -gt 0 -or $VerbosePreference -gt 0) {
        Write-Host "$($bashUninstallScriptOutput -join "`n")"
    }
    if ($bashUninstallScriptOutput -and ($bashUninstallScriptOutput | Where-Object { $_.StartsWith('[Error') } | Measure-Object).Count -gt 0) {
        Write-Error "Error(s) occurred while running Bash Uninstall script: $bashCommand`n$($bashUninstallScriptOutput -join "`n")"
        return
    }

    Write-Debug "$(_@) Uninstalled Bash scripts."
    Write-Verbose 'Uninstalled Bash scripts.'
    #endregion Remove Bash Autorun
}

function Update-WslBashScripts {
    <#
    .SYNOPSIS
    Updates Bash scripts of specified WSL Instance to the latest version.

    .DESCRIPTION
    Uninstalls (deletes) and then installs (copies) last version of Bash scripts to specified WSL Instance

    .PARAMETER WslInstanceName
    Required. Name of the WSL Instance as listed by `wsl.exe -l` command

    .PARAMETER WslHostName
    Optional. Defaults to WslInstanceName. The name to use to access the WSL Instance on WSL SubNet. This name together with WslInstanceIpAddress are added to Windows HOSTS file.

    .EXAMPLE
    Update-WslBashScripts -WslInstanceName Ubuntu

    Will read saved configuration from .wslconfig and use this setting to apply to Ubuntu WSL Instance.

    .NOTES
    This command can only be used AFTER `Install-WslIpHandler` command was used to setup network configuration.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [Parameter()]
        [switch]$BashVerbose,

        [Parameter()]
        [switch]$BashDebug
    )
    #region Local Bash Script Paths
    $BashUpdateScript = Get-SourcePath 'BashUpdate'
    Write-Debug "$(_@) `$BashUpdateScript='$BashUpdateScript'"

    $BashUninstallScript = Get-SourcePath 'BashUninstall'
    Write-Debug "$(_@) `$BashUninstallScript='$BashUninstallScript'"

    $BashInstallScript = Get-SourcePath 'BashInstall'
    Write-Debug "$(_@) `$BashInstallScript='$BashInstallScript'"
    #endregion Local Bash Script Paths

    #region WSL Autorun
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptSource = Get-SourcePath 'BashAutorun'
    Write-Debug "$(_@) `$BashAutorunScriptSource='$BashAutorunScriptSource'"
    $BashAutorunScriptName = Split-Path -Leaf (Get-SourcePath 'BashAutorun')
    Write-Debug "$(_@) `$BBashAutorunScriptName='$BashAutorunScriptName'"
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    Write-Debug "$(_@) `$BashAutorunScriptTarget='$BashAutorunScriptTarget'"
    #endregion WSL Autorun

    #region Bash Script WSL Paths
    $BashUpdateScriptWslPath = '$(wslpath "' + "$BashUpdateScript" + '")'
    Write-Debug "$(_@) `$BashUpdateScriptWslPath='$BashUpdateScriptWslPath'"
    #endregion Bash Script WSL Paths

    #region Install Script Arguments
    # Get Path to PS Script that injects (if needed) IP-host to windows hosts on every WSL launch
    $WinHostsEditScript = Get-SourcePath 'WinHostsEdit'
    Write-Debug "$(_@) `$WinHostsEditScript='$WinHostsEditScript'"

    $WindowsHostName = Get-WslConfigValue -SectionName (Get-NetworkSectionName) -KeyName (Get-WindowsHostNameKeyName) -DefaultValue 'windows'
    Write-Debug "$(_@) `$WindowsHostName='$WindowsHostName'"

    $existingIp = Get-WslConfigStaticIpAddress -WslInstanceName $WslInstanceName
    if ($existingIp) {
        Write-Debug "$(_@) Existing Static IP Address for $WslInstanceName = $existingIp"
        $WslHostIpOrOffset = "$existingIp"
    }
    else {
        Write-Debug "$(_@) Static IP Address for $WslInstanceName not found Querying for Offset."
        $WslIpOffset = Get-WslConfigIpOffset $WslInstanceName
        if ($WslIpOffset) {
            $WslHostIpOrOffset = $WslIpOffset
        }
        else {
            $msg = "Neither Static IP Address nor IP Offset are configured for '$WslInstanceName'. Please run `Install-WslIpHandler` to set either Static IP Address or Offset before using this command."
            Throw "$msg"
        }
    }
    #endregion  Install Script Arguments

    #region Run Update Script
    Write-Verbose "Running Bash WSL Update script $BashUpdateScript"
    Write-Debug "$(_@) `$DebugPreference=$DebugPreference"
    Write-Debug "$(_@) `$VerbosePreference=$VerbosePreference"

    $bashUninstallArgs = @(
        "$BashAutorunScriptName"
        "$BashAutorunScriptTarget"
    )
    $bashInstallArgs = @(
        "`"$BashAutorunScriptSource`""
        "$BashAutorunScriptTarget"
        "`"$WinHostsEditScript`""
        "$WindowsHostName"
        "$WslHostName"
        "$WslHostIpOrOffset"
    )

    $bashCommand = @($BashUpdateScriptWslPath)
    $bashCommand = + $bashUninstallArgs
    $bashCommand = + $bashInstallArgs

    $envVars = @()
    if ($DebugPreference -gt 0) { $envVars += 'DEBUG=1' }
    if ($VerbosePreference -gt 0) { $envVars += 'VERBOSE=1' }

    $bashArgs = @()
    if ($BashVerbose) { $bashArgs += '--verbose' }
    if ($BashDebug) { $bashArgs += '--debug' }

    Write-Debug "$(_@) Invoking: wsl.exe -d $WslInstanceName sudo -E env '`"PATH=``$PATH`"' $envVars bash $bashArgs $bashCommand"
    $bashUpdateScriptOutput = wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' @envVars bash @bashArgs @bashCommand

    if ($DebugPreference -gt 0 -or $VerbosePreference -gt 0) {
        Write-Host "$($bashUpdateScriptOutput -join "`n")"
    }
    if ($bashUpdateScriptOutput -and ($bashUpdateScriptOutput | Where-Object { $_.StartsWith('[Error') } | Measure-Object).Count -gt 0) {
        Write-Error "Error(s) occurred while running Bash Update script: $bashCommand`n$($bashUpdateScriptOutput -join "`n")"
        return
    }

    Write-Debug "$(_@) Updated Bash scripts."
    Write-Verbose 'Updated Bash scripts.'
    #endregion Run Update Script
}

function Set-ProfileContent {
    <#
    .SYNOPSIS
    Modifies Powershell profile to set alias `wsl` -> Invoke-WslExe

    .DESCRIPTION
    Modifies Powershell profile file (by default CurrentUserAllHosts) to set alias `wsl` -> Invoke-WslExe.

    .PARAMETER ProfilePath
    Optional. Path to Powershell profile. Defaults to value of $Profile.CurrentUserAllhosts.

    .EXAMPLE
    Set-ProfileContent

    Modifies the default location for CurrentUserAllhosts.

    ------------------------------------------------------------------------------------------------
    Set-ProfileContent $Profile.AllUsersAllHosts

    Modifies the system profile file.

    .NOTES
    Having `wsl` alias in profile allows to automatically enable WSL Network Adapter with manually setting it up before launching WSL instance.
    #>
    [CmdletBinding()]
    param($ProfilePath = $profile.CurrentUserAllHosts)

    Write-Debug "$(_@) ProfilePath: $ProfilePath"

    $handlerContent = Get-ProfileContent

    $content = (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue) ?? @()

    $anyHandlerContentMissing = $false
    foreach ($line in $handlerContent) {
        if ($line -notin $content) { $anyHandlerContentMissing = $true; break }
    }

    if ($anyHandlerContentMissing) {
        # Safeguard to avoid duplication in case user manually edits profile file
        $content = $content | Where-Object { $handlerContent -notcontains $_ }
        $content += $handlerContent
        Set-Content -Path $ProfilePath -Value $content -Force
        Write-Warning "WSL-IpHandler Content was added to Powershell profile: $ProfilePath."
        Write-Warning 'The changes will take effect after Powershell session is restarted!'
        # . $ProfilePath  # !!! DONT DO THAT -> IT Removes ALL Sourced functions (i.e. '. File.ps1')
    }
    else {
        Write-Debug "$(_@) WSL-IpHandler Content is already present in Powershell profile: $ProfilePath."
    }
}

function Remove-ProfileContent {
    <#
    .SYNOPSIS
    Removes modifications made by Set-ProfileContent command.

    .DESCRIPTION
    Removes modifications made by Set-ProfileContent command.

    .PARAMETER ProfilePath
    Optional. Path to Powershell profile. Defaults to value of $Profile.CurrentUserAllhosts.
    #>
    [CmdletBinding()]
    param($ProfilePath = $Profile.CurrentUserAllHosts)
    Write-Debug "$(_@) ProfilePath: $ProfilePath"

    $handlerContent = Get-ProfileContent

    $content = (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue) ?? @()
    if ($content) {
        $handlerContentIsPresent = $null -ne ($content | Where-Object {
                $handlerContent -contains $_
            })
        if ($handlerContentIsPresent) {
            $content = $content | Where-Object { $handlerContent -notcontains $_ }
            Set-Content -Path $ProfilePath -Value $content -Force
            Write-Warning "WSL-IpHandler Content was removed from Powershell profile: $ProfilePath."
            Write-Warning 'The changes will take effect after Powershell session is restarted!'
        }
        else {
            Write-Debug "$(_@) WSL-IpHandler Content not found in $ProfilePath"
        }
    }
}

function Set-WslInstanceStaticIpAddress {
    <#
    .SYNOPSIS
    Sets Static IP Address for the specified WSL Instance.

    .DESCRIPTION
    Sets Static IP Address for the specified WSL Instance. Given WslInstanceIpAddress will be validated against specified GatewayIpAddress and PrefixLength, error will be thrown if it is incorrect.

    .PARAMETER WslInstanceName
    Required. Name of WSL Instance as listed by `wsl.exe -l` command.

    .PARAMETER GatewayIpAddress
    Required. Gateway IP v4 Address of vEthernet (WSL) network adapter.

    .PARAMETER PrefixLength
    Optional. Defaults to 24. WSL network SubNet Length.

    .PARAMETER WslInstanceIpAddress
    Required. IP v4 Address to assign to WSL Instance.

    .PARAMETER Modified
    Optional. Reference to boolean variable. Will be set to True if given parameters will lead to change of existing settings. If this parameter is specified - any occuring changes will have to be saved with Write-WslConfig command. This parameter cannot be used together with BackupWslConfig parameter.

    .PARAMETER BackupWslConfig
    Optional. If given - original version of .wslconfig file will be saved as backup. This parameter cannot be used together with Modified parameter.

    .EXAMPLE
    Set-WslInstanceStaticIpAddress -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.11

    Will set Ubuntu WSL Instance Static IP address to 172.16.0.11

    .NOTES
    This command only checks against specified Gateway IP Address, not actual one (even if it exists). Any changes made will require restart of WSL instance for them to take effect.
    #>
    param (
        [Parameter(Mandatory)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter(Mandatory)][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Alias('IpAddress')]
        [ipaddress]$WslInstanceIpAddress,

        [Parameter(Mandatory, ParameterSetName = 'SaveExternally')]
        [ref]$Modified,

        [Parameter(ParameterSetName = 'SaveHere')]
        [switch]$BackupWslConfig
    )
    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }
    if ($null -eq $WslInstanceIpAddress) {
        $existingIp = Get-WslConfigStaticIpAddress -Name $WslInstanceName

        if ($existingIp) {
            Write-Debug "$(_@) `$WslInstanceIpAddress is `$null. Using existing assignment:"
            Write-Debug "$(_@) $WslInstanceName = $existingIp"
            $WslInstanceIpAddress = $existingIp
        }
        else {
            $WslInstanceIpAddress = Get-WslConfigAvailableStaticIpAddress $GatewayIpAddress
            Write-Debug "$(_@) `$WslInstanceIpAddress is `$null."
            Write-Debug "$(_@) Available Static Ip Address: $WslInstanceIpAddress"
        }
    }

    Write-Debug "$(_@) `$WslInstanceName=$WslInstanceName `$GatewayIpAddress=$GatewayIpAddress `$PrefixLength=$PrefixLength `$WslInstanceIpAddress=$($WslInstanceIpAddress ? $WslInstanceIpAddress : "`$null")"

    $null = Test-IsValidStaticIpAddress -IpAddress $WslInstanceIpAddress -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength

    Set-WslConfigStaticIpAddress -WslInstanceName $WslInstanceName -WslInstanceIpAddress $WslInstanceIpAddress -Modified $Modified

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere' -and $localModified) {
        Write-WslConfig -Backup:$BackupWslConfig
    }
}

function Remove-WslInstanceStaticIpAddress {
    <#
    .SYNOPSIS
    Removes Static IP Address for the specified WSL Instance from .wslconfig.

    .DESCRIPTION
    Removes Static IP Address for the specified WSL Instance from .wslconfig.

    .PARAMETER WslInstanceName
    Required. Name of WSL Instance as listed by `wsl.exe -l` command.

    .PARAMETER Modified
    Optional. Reference to boolean variable. Will be set to True if given parameters will lead to change of existing settings. If this parameter is specified - any occuring changes will have to be saved with Write-WslConfig command. This parameter cannot be used together with BackupWslConfig parameter.

    .PARAMETER BackupWslConfig
    Optional. If given - original version of .wslconfig file will be saved as backup. This parameter cannot be used together with Modified parameter.

    .EXAMPLE
    Remove-WslInstanceStaticIpAddress -WslInstanceName Ubuntu

    Will remove Static IP address for Ubuntu WSL Instance.
    #>
    param (
        [Parameter(Mandatory)]
        [Alias('Name')]
        [string]$WslInstanceName,

        [Parameter(Mandatory, ParameterSetName = 'SaveExternally')]
        [ref]$Modified,

        [Parameter(ParameterSetName = 'SaveHere')]
        [switch]$BackupWslConfig
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }

    Write-Debug "$(_@) Before Calling Remove-WslConfigValue `$Modified=$($Modified.Value)"

    Remove-WslConfigStaticIpAddress -WslInstanceName $WslInstanceName -Modified $Modified
    Write-Debug "$(_@) After Calling Remove-WslConfigValue `$Modified=$($Modified.Value)"

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere' -and $localModified) {
        Write-Debug "$(_@) Calling Write-WslConfig -Backup:$BackupWslConfig"
        Write-WslConfig -Backup:$BackupWslConfig
    }
}

function Set-WslNetworkConfig {
    <#
    .SYNOPSIS
    Sets WSL Network Adapter parameters, which are stored in .wslconfig file

    .DESCRIPTION
    Sets WSL Network Adapter parameters, which are stored in .wslconfig file

    .PARAMETER GatewayIpAddress
    Required. Gateway IP v4 Address of vEthernet (WSL) network adapter.

    .PARAMETER PrefixLength
    Optional. Defaults to 24. WSL network SubNet Length.

    .PARAMETER DNSServerList
    Optional. Defaults to GatewayIpAddress. DNS servers to set for the network adapater. The list is a string with comma separated servers.

    .PARAMETER DynamicAdapters
    Array of strings - names of Hyper-V Network Adapters that can be moved to other IP network space to free space for WSL adapter. Defaults to: `'Ethernet', 'Default Switch'`

    .PARAMETER Modified
    Optional. Reference to boolean variable. Will be set to True if given parameters will lead to change of existing settings. If this parameter is specified - any occuring changes will have to be saved with Write-WslConfig command. This parameter cannot be used together with BackupWslConfig parameter.

    .PARAMETER BackupWslConfig
    Optional. If given - original version of .wslconfig file will be saved as backup. This parameter cannot be used together with Modified parameter.

    .EXAMPLE
    Set-WslNetworkConfig -GatewayIpAddress 172.16.0.1 -BackupWslConfig

    Will set Gateway IP Address to 172.16.0.1, SubNet length to 24 and DNS Servers to 172.16.0.1.
    Will save the changes in .wslconfig and create backup version of the file.

    .NOTES
    This command only changes parameters of the network adapter in .wslconfig file, without any effect on active adapter (if it exists). To apply these settings use command Set-WslNetworkAdapter.
    #>
    param (
        [Parameter()][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Parameter()]
        [string[]]$DynamicAdapters = @('Ethernet', 'Default Switch'),

        [Parameter()]
        [string]$WindowsHostName = 'windows',

        [Parameter(Mandatory, ParameterSetName = 'SaveExternally')]
        [ref]$Modified,

        [Parameter(ParameterSetName = 'SaveHere')]
        [switch]$BackupWslConfig
    )
    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }
    Write-Debug "$(_@) Setting WslConfig Network Parameters:"
    Write-Debug "$(_@) WindowsHostName=$WindowsHostName"

    Set-WslConfigWindowsHostName $WindowsHostName -Modified $Modified

    if ($null -ne $GatewayIpAddress) {
        $DNSServerList = $DNSServerList ? $DNSServerList : $GatewayIpAddress
        Write-Debug "$(_@) GatewayIpAddress=$GatewayIpAddress"
        Write-Debug "$(_@) PrefixLength=$PrefixLength"
        Write-Debug "$(_@) DNSServerList=$DNSServerList"
        Write-Debug "$(_@) DynamicAdapters=$DynamicAdapters"

        Set-WslConfigGatewayIpAddress $GatewayIpAddress -Modified $Modified
        Set-WslConfigPrefixLength $PrefixLength -Modified $Modified
        Set-WslConfigDnsServers $DNSServerList -Modified $Modified
        Set-WslConfigDynamicAdapters $DynamicAdapters -Modified $Modified
    }

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere' -and $localModified) {
        Write-WslConfig -Backup:$BackupWslConfig
    }
}

function Remove-WslNetworkConfig {
    <#
    .SYNOPSIS
    Removes all WSL network adapter parameters that are set by Set-WslNetworkConfig command.

    .DESCRIPTION
    Removes all WSL network adapter parameters that are set by Set-WslNetworkConfig command: -GatewayIpAddress, -PrefixLength, -DNSServerList. If there are any static ip address assignments in a .wslconfig file there will be a warning and command will have no effect. To override this limitation use -Force parameter.

    .PARAMETER Modified
    Optional. Reference to boolean variable. Will be set to True if given parameters will lead to change of existing settings. If this parameter is specified - any occuring changes will have to be saved with Write-WslConfig command. This parameter cannot be used together with BackupWslConfig parameter.

    .PARAMETER BackupWslConfig
    Optional. If given - original version of .wslconfig file will be saved as backup. This parameter cannot be used together with Modified parameter.

    .PARAMETER Force
    Optional. If specified will clear network parameters from .wslconfig file even if there are static ip address assignments remaining. This might make those static ip addresses invalid.

    .EXAMPLE
    Remove-WslNetworkConfig -Force

    Clears GatewayIpAddress, PrefixLength and DNSServerList settings from .wsl.config file, without saving a backup.

    .NOTES
    This command only clears parameters of the network adapter in .wslconfig file, without any effect on active adapter (if it exists). To remove adapter itself use command Remove-WslNetworkAdapter.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'SaveExternally')]
        [ref]$Modified,

        [Parameter(ParameterSetName = 'SaveHere')]
        [switch]$BackupWslConfig,

        [switch]$Force
    )
    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }

    $staticIpSection = Get-WslConfigStaticIpSection

    if ($Force -or ($staticIpSection.Count -le 0)) {
        Remove-WslConfigGatewayIpAddress -Modified $Modified

        Remove-WslConfigPrefixLength -Modified $Modified

        Remove-WslConfigDnsServers -Modified $Modified

        Remove-WslConfigWindowsHostName -Modified $Modified

        Remove-WslConfigDynamicAdapters -Modified $Modified
    }
    else {
        Write-Warning "Network Parameters in .wslconfig will not be removed because there are Static IP Addresses remaining in .wslconfig:`n$(($staticIpSection.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)"}) -join "`n")"`

    }

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere' -and $localModified) {
        Write-WslConfig -Backup:$BackupWslConfig
    }
}

function Set-WslNetworkAdapter {
    <#
    .SYNOPSIS
    Sets up WSL network adapter. Requires Administrator privileges.

    .DESCRIPTION
    Sets up WSL network adapter. Requires Administrator privileges. If executed from non elevated powershell prompt - will ask for confirmation to grant required permissions. Any running WSL Instances will be shutdown before the adapter is installed. If there is adapter with required parameters - no changes will be made.

    .PARAMETER GatewayIpAddress
    Optional. Gateway IP v4 Address of vEthernet (WSL) network adapter. Defaults to the setting in .wslconfig file. If there is not value in .wslconfig will issue a warning and exit.

    .PARAMETER PrefixLength
    Optional. Defaults to 24. WSL network SubNet Length.

    .PARAMETER DNSServerList
    Optional. Defaults to GatewayIpAddress. DNS servers to set for the network adapater. The list is a string with comma separated servers.

    .PARAMETER DynamicAdapters
    Array of strings - names of Hyper-V Network Adapters that can be moved to other IP network space to free space for WSL adapter. Defaults to: `'Ethernet', 'Default Switch'`

    .PARAMETER WaitForWslNetworkConnection
    If this switch parameter is specified then after the WSL Hyper-V Network Adapter is setup the command will wait for 'vEthernet (WSL)' Network Connection to become available within specified timeout period (see -Timeout parameter). If the network connection is not available by end of timeout period - Exception will be thrown.

    .PARAMETER Timeout
    Number of seconds to wait for 'vEthernet (WSL)' Network Connection to become available.

    .PARAMETER ShowToast
    If this switch parameter is specified then any exception or verbose message signaling of failure or success of operation will be shown in a Popup Toast Notification message near system tray. Intended to use in non-interactive session (i.e. as Scheduled Task).

    .PARAMETER ToastDuration
    Number of seconds to show Toast Notification. Defaults to 5 seconds.

    .EXAMPLE
    Set-WslNetworkConfig -GatewayIpAddress 172.16.0.1
    Set-WslNetworkAdapter

    First command will set Gateway IP Address to 172.16.0.1, SubNet length to 24 and DNS Servers to 172.16.0.1 saving the settings in .wslconfig file.
    Second command will actually put these settings in effect. If there was active WSL network adapter in the system - it will be removed beforehand. Any running WSL instances will be shutdown.

    .NOTES
    Executing this command will not save specified parameters to .wslconfig. To save settings use command Set-WslNetworkConfig.
    Or preferably first run Set-WslNetworkConfig with required parameters and then execute Set-WslNetworkAdapter without parameters for this command to read settings from .wslconfig.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter()][Alias('Prefix')]
        [int]$PrefixLength,

        [Parameter()][Alias('DNS')]
        [string]$DNSServerList, # Comma separated ipaddresses/hosts

        [Parameter()]
        [string[]]$DynamicAdapters = @('Ethernet', 'Default Switch'),

        [Parameter()]
        [Alias('Toast')]
        [switch]$ShowToast,

        [Parameter()]
        [Alias('Wait')]
        [switch]$WaitForWslNetworkConnection,

        [Parameter()]
        [int]$Timeout = 30,

        [Parameter()]
        [Alias('Duration')]
        [int]$ToastDuration = 5
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $GatewayIpAddress ??= Get-WslConfigGatewayIpAddress
    Write-Debug "$(_@) `$GatewayIpAddress='$GatewayIpAddress'"

    if ($ShowToast) {
        $toastModuleName = 'Show-ToastMessages'
        $toastModulePath = Join-Path $PSScriptRoot 'SubModules' "$toastModuleName.psm1" -Resolve
        Import-Module $toastModulePath -Function Show-ToastMessage
        $toastParams = @{
            Title   = 'WSL-IpHandler'
            Seconds = $ToastDuration
        }
    }

    if ($null -eq $GatewayIpAddress) {
        $msg = 'Gateway IP Address is not specified neither as parameter nor in .wslconfig. WSL Hyper-V Network Adapter cannot be setup without Gateway IP Address!'
        if ($ShowToast) { Show-ToastMessage -Text "$msg" -Type 'Info' @toastParams }
        Throw "$msg"
    }
    Write-Debug "$(_@) `$GatewayIpAddress='$GatewayIpAddress'"

    $PrefixLength = $PSBoundParameters.ContainsKey('PrefixLength') ? $PrefixLength : (Get-WslConfigPrefixLength -DefaultValue 24)
    Write-Debug "$(_@) `$PrefixLength=$PrefixLength"

    $DNSServerList = [string]::IsNullOrWhiteSpace($DNSServerList) ? (Get-WslConfigDnsServers -DefaultValue $GatewayIpAddress) : $DNSServerList
    Write-Debug "$(_@) `$DNSServerList='$DNSServerList'"

    $DynamicAdapters = $DynamicAdapters.Count ? $DynamicAdapters : (Get-WslConfigDynamicAdapters -DefaultValue @())
    Write-Debug "$(_@) `$DynamicAdapters='$DynamicAdapters'"

    $GetWslNetworkConnection = { Get-NetIPAddress -InterfaceAlias $vEthernetWsl -AddressFamily IPv4 -ErrorAction SilentlyContinue }

    $wslNetworkConnection = & $GetWslNetworkConnection

    # Check if there is existing WSL Adapter
    if ($null -ne $wslNetworkConnection) {
        Write-Verbose "Hyper-V VM Adapter 'WSL' already exists."
        Write-Debug "$(_@) `$wslNetworkConnection`n$($wslNetworkConnection | Out-String)"

        # Check if existing WSL Adapter has required settings
        if ($wslNetworkConnection.IPAddress -eq $GatewayIpAddress -and $wslNetworkConnection.PrefixLength -eq $PrefixLength) {
            $msg = "Hyper-V VM Adapter 'WSL' already has required Gateway: '$GatewayIpAddress' and PrefixLength: '$PrefixLength'!"
            Write-Verbose "$msg"

            if ($ShowToast) { Show-ToastMessage -Text $msg -Type 'Info' @toastParams }
            return
        }
    }

    # Setup required WSL adapter
    Write-Debug "$(_@) Shutting down all WSL instances before Setting up WSL Network Adapter..."
    wsl.exe --shutdown

    . (Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsPSElevation.ps1' -Resolve) | Out-Null
    $setAdapterScript = Join-Path $PSScriptRoot 'Scripts\Powershell\Set-VirtualNetworkAdapter.ps1' -Resolve

    $scriptParameters = @{
        GatewayIpAddress   = $GatewayIpAddress
        PrefixLength       = $PrefixLength
        DNSServerList      = $DNSServerList
        DynamicAdapters    = $DynamicAdapters
        VirtualAdapterName = 'WSL'
    }
    $commonParameters = @{}
    if ($VerbosePreference -eq 'Continue') { $commonParameters.Verbose = $true }
    if ($DebugPreference -eq 'Continue') { $commonParameters.Debug = $true }
    Write-Debug "$(_@) `$commonParameters $(& { $args } @commonParameters)"

    try {
        if (IsElevated) {
            Write-Debug "$(_@) & $setAdapterScript -ScriptParameters $(& {$args} @scriptParameters) $(& { $args } @commonParameters)"

            $msg = & $setAdapterScript @scriptParameters @commonParameters
        }
        else {
            Write-Debug "$(_@) Invoke-ScriptElevated $setAdapterScript -ScriptParameters $(& {$args} @scriptParameters) $(& { $args } @commonParameters)"

            Invoke-ScriptElevated $setAdapterScript -ScriptParameters $scriptParameters -Encode -Wait @commonParameters
            $msg = "Created New Hyper-V VM Adapter: 'WSL' with Gateway: $GatewayIpAddress and Prefix: $PrefixLength"
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($ShowToast) { Show-ToastMessage -Text $msg -Type 'Error' @toastParams }
        Write-Error "$msg"
    }

    if ($WaitForWslNetworkConnection) {
        $GetWslNetworkStatus = { if ($null -eq (& $GetWslNetworkConnection)) { $false } else { $true } }

        $waitingMessage = ''
        $eventLabel = "$vEthernetWsl Network Connection Setup"
        $waitingParams = @{
            ValidationScript = $GetWslNetworkStatus
            EventLabel       = $eventLabel
            Timeout          = $Timeout
            MessageVariable  = ([ref]$waitingMessage)
        }
        Write-Debug "$(_@) Waiting Params: $(& {$args} @waitingParams)"

        if (Wait-ForExpressionTimeout @waitingParams) {
            if ($ShowToast) { Show-ToastMessage -Text $waitingMessage -Type 'Info' @toastParams }
            if ($waitingMessage) { Write-Verbose "$waitingMessage" }
        }
        else {
            if ($ShowToast) { Show-ToastMessage -Text $waitingMessage -Type 'Error' @toastParams }
            if ($waitingMessage) { Write-Error "$waitingMessage" }
            else { Write-Error "Error waiting for $eventLabel - operation timed out." }
        }
    }
    else {
        if ($ShowToast) { Show-ToastMessage -Text $msg -Type 'Info' @toastParams }
        Write-Verbose "$msg"
    }
}

function Remove-WslNetworkAdapter {
    <#
    .SYNOPSIS
    Removes WSL Network Adapter from the system if there is any.

    .DESCRIPTION
    Removes WSL Network Adapter from the system if there is any. If there is none - does nothing. Requires Administrator privileges. If executed from non elevated powershell prompt - will ask for confirmation to grant required permissions.

    .EXAMPLE
    Remove-WslNetworkAdapter

    .NOTES
    Executing this command will cause all running WSL instances to be shutdown.
    #>
    [CmdletBinding()]
    param()
    $removeAdapterScript = Join-Path $PSScriptRoot 'Scripts\Powershell\Remove-VirtualNetworkAdapter.ps1' -Resolve
    $scriptParams = @{ VirtualAdapterName = 'WSL' }
    Write-Debug "$(_@) & $removeAdapterScript $(& {$args} @scriptParams @PsBoundParameters)"

    & $removeAdapterScript @scriptParams @PsBoundParameters
}

function Set-WslScheduledTask {
    <#
    .SYNOPSIS
    Creates a new Scheduled Task: WSL-IpHandlerTask that will be triggered at user LogOn.
    This task execution is equivalent to running Set-WslNetworkAdapter command. It will create WSL Hyper-V Network Adapter when user logs on.

    .DESCRIPTION
    Creates Scheduled Task named 'WSL-IpHandlerTask' under 'WSL-IpHandler' folder.
    The task will be executed with Highest level of privileges under SYSTEM account.
    It will run in background without any interaction with user.
    After it is finished there will be WSL Hyper-V network adapter with network properties specified with this command.

    .PARAMETER WaitForWslNetworkConnection
    If this switch parameter is specified then after the WSL Hyper-V Network Adapter is setup the command will wait for 'vEthernet (WSL)' Network Connection to become available within specified timeout period (see -Timeout parameter). If the network connection is not available by end of timeout period - Exception will be thrown.

    .PARAMETER Timeout
    Number of seconds to wait for 'vEthernet (WSL)' Network Connection to become available.

    .PARAMETER ShowToast
    If this switch parameter is specified then any exception or verbose message signaling of failure or success of operation will be shown in a Popup Toast Notification message near system tray. Intended to use in non-interactive session (i.e. as Scheduled Task).

    .PARAMETER ToastDuration
    Number of seconds to show Toast Notification. Defaults to 5 seconds.

    .PARAMETER UserName
    User Name to run the task under. Defaults to name of current user, which can checked with executing `$env:username` in Powershell prompt. Computer Name will be added and defaults to `$env:userdomain`.

    .PARAMETER AnyUserLogOn
    When this parameter is present - The Scheduled Task will be set to run when any user logs on. Otherwise (default behavior) - the task will run only when current user (who executed Install-WslIpHandler command) logs on.

    .PARAMETER RunWhetherUserLoggedOnOrNot
    Has the same effect as the setting with the same name in Task Scheduler. If this switch parameter is set, then -ShowToast parameter is ignored.

    .EXAMPLE
    Set-WslScheduledTask -AllUsers

    Creates scheduled task that will be executed when any user logs on.

    .NOTES
    The task created can be found in Task Scheduler UI.
    #>
    param (
        [Parameter()]
        [Alias('Wait')]
        [switch]$WaitForWslNetworkConnection,

        [Parameter()]
        [int]$Timeout = 30,

        [Parameter()]
        [Alias('Toast')]
        [switch]$ShowToast,

        [Parameter()]
        [Alias('Duration')]
        [int]$ToastDuration = 5,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$UserName = $env:USERNAME,

        [switch]$AnyUserLogOn,

        [switch]$RunWhetherUserLoggedOnOrNot
        # [switch]$AsLocalSystem
    )
    $elevationScript = Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsPSElevation.ps1' -Resolve
    . $elevationScript

    $taskName = Get-ScheduledTaskName
    $taskPath = Get-ScheduledTaskPath
    $taskDescription = Get-ScheduledTaskDescription
    $psExe = GetPowerShellExecutablePath

    Write-Debug "$(_@) Task Name: $taskName"
    Write-Debug "$(_@) Task Path: $taskPath"
    Write-Debug "$(_@) Task Description: $taskDescription"
    Write-Debug "$(_@) Powershell Executable Path: $psExe"

    $FullUserName = if ($UserName.Contains('\')) { $UserName } else { "$env:USERDOMAIN\$UserName" }
    Write-Debug "$(_@) `$UserName: $UserName"
    Write-Debug "$(_@) `$FullUserName: $FullUserName"

    $modulePath = $MyInvocation.MyCommand.Module.Path.Replace('.psm1', '.psd1')
    $command = @(
        "Import-Module '$modulePath';"
        'Set-WslNetworkAdapter'
    )
    if ($WaitForWslNetworkConnection) {
        $command += '-Wait'
        $command += "-Timeout:$Timeout"
    }

    if ($ShowToast -and -not $RunWhetherUserLoggedOnOrNot) {
        $command += '-Toast'
        $command += "-Duration:$ToastDuration"
    }

    $psExeArguments = @(
        '-NoLogo'
        '-NoProfile'
    )

    if ($VerbosePreference -ne 0) {
        $command += '-Verbose'
        Write-Debug "$(_@) Command in verbose mode: $command"
    }
    if ($DebugPreference -eq 0) {
        # $psExeArguments += '-NonInteractive'
        $psExeArguments += '-WindowStyle Hidden'
    }
    else {
        $psExeArguments += '-NoExit'
        $command += '-Debug'
        Write-Debug "$(_@) Command in debug mode: $command"
    }

    $psExeArguments += "-Command ```"$($command -join ' ')```""

    Write-Debug "$(_@) psExeArguments: $psExeArguments"

    $scriptParams = @{
        TaskName        = $taskName
        TaskPath        = $taskPath
        TaskDescription = $taskDescription
        UserName        = $UserName
        Command         = $psExe
        Argument        = "`"$($psExeArguments -join ' ')`""
        AnyUserLogOn    = $AnyUserLogOn
    }

    if ($RunWhetherUserLoggedOnOrNot) {
        $credential = Get-WslScheduledTaskCredential -UserName $FullUserName -MaxNumberOfAttempts 5
        $scriptParams.RunAsUserName = $credential.UserName
        $scriptParams.EncryptedSecureString = $credential.Password | ConvertFrom-SecureString
    }

    $registerTaskScript = Join-Path $PSScriptRoot 'Scripts\Powershell\Set-ScheduledTask.ps1' -Resolve
    $commonParameters = @{}
    if ($VerbosePreference -eq 'Continue') { $commonParameters.Verbose = $true }
    if ($DebugPreference -eq 'Continue') { $commonParameters.Debug = $true }
    Write-Debug "$(_@) `$commonParameters $(& { $args } @commonParameters)"

    Write-Debug "$(_@) Invoke-ScriptElevated -Encode -ScriptPath $registerTaskScript -ScriptParameters $(& {$args} @scriptParams) $(& {$args} @commonParams)"
    Invoke-ScriptElevated -Encode -ScriptPath $registerTaskScript -ScriptParameters $scriptParams @commonParams
}

function Remove-WslScheduledTask {
    <#
    .SYNOPSIS
    Removes WSL-IpHandlerTask Scheduled Task created with Set-WslScheduledTask command.

    .PARAMETER CheckRemoval
    If this switch parameter is specified after the task was removed the command will check that the task does not actually exist.

    .PARAMETER Timeout
    Scheduled Task removal takes some time for the system to complete.
    This parameter specifies time in seconds for how long to keep checking that task was actually removed before assuming failure. Defaults to 15 seconds.

    .EXAMPLE
    Remove-WslScheduledTask
    #>
    param (
        [Parameter()]
        [switch]$CheckRemoval,

        [Parameter()]
        [int]$Timeout = 15
    )

    $elevationScript = Join-Path $PSScriptRoot 'Scripts\Powershell\FunctionsPSElevation.ps1' -Resolve
    . $elevationScript

    $taskName = Get-ScheduledTaskName
    $taskPath = Get-ScheduledTaskPath

    Write-Debug "$(_@) Checking if $taskName exists..."

    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

    if (-not $existingTask) {
        Write-Debug "$(_@) $taskName does not exist - nothing to remove."
        return
    }

    Write-Verbose "Removing Scheduled Task: ${taskPath}${taskName}"
    if (IsElevated) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
    else {
        $arguments = "-TaskName '$taskName' -TaskPath '$taskPath' -Confirm:`$false -ErrorAction SilentlyContinue"
        Invoke-CommandElevated "Unregister-ScheduledTask $arguments"
    }

    if (-not $CheckRemoval) { return }

    $waitingMessage = ''
    $eventLabel = 'WSL-IpHandler Scheduled Task Removal'
    $waitParams = @{
        ValidationScript = {
            $null -eq (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue)
        }
        EventLabel       = $eventLabel
        Timeout          = $Timeout
        MessageVariable  = ([ref]$waitingMessage)
    }
    if (Wait-ForExpressionTimeout @waitParams) {
        Write-Debug "$(_@)) Successfully removed Scheduled Task: ${taskPath}${taskName}"
    }
    else {
        Write-Debug "$(_@)) Failed to remove Scheduled Task: ${taskPath}${taskName}"
        if ($waitingMessage) { Write-Error "$waitingMessage" }
        else { Write-Error "Error waiting for $eventLabel - operation timed out." }
    }
}

function Test-WslInstallation {
    <#
    .SYNOPSIS
    Tests if WSL Handler has been installed successfully.

    .DESCRIPTION
    Tests if WSL Handler has been installed successfully. This command is run automatically during execution of Install-WslHandler command. The tests are made by pinging once WSL instance and Windows host to/from each other.

    .PARAMETER WslInstanceName
    Required. Name of WSL Instance as listed by `wsl.exe -l` command.

    .PARAMETER WslHostName
    Optional. Defaults to WslInstanceName. The name to use to access the WSL Instance on WSL SubNet.

    .PARAMETER WindowsHostName
    Optional. Defaults to `windows`. Name of Windows Host that can be used to access windows host from WSL Instance.

    .EXAMPLE
    Test-WslInstallation -WslInstanceName Ubuntu
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$WslInstanceName,

        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [ValidateNotNullOrEmpty()]
        [string]$WindowsHostName
    )
    $networkSectionName = (Get-NetworkSectionName)
    $failed = $false

    if (-not $PSBoundParameters.ContainsKey('WindowsHostName')) {
        $WindowsHostName = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-WindowsHostNameKeyName) -DefaultValue 'windows'
    }

    $error_message = @()

    $bashTestCommand = "ping -c1 $WindowsHostName 2>&1"
    Write-Verbose "Testing Ping from WSL instance ${WslInstanceName}: `"$bashTestCommand`" ..."
    $wslTest = (Invoke-WslExe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$bashTestCommand`") -join "`n"

    Write-Debug "$(_@) `$wslTest: $wslTest"

    if ($wslTest -notmatch ', 0% packet loss') {
        Write-Verbose "Ping from WSL Instance $WslInstanceName failed:`n$wslTest"
        Write-Debug "$(_@) TypeOf `$wslTest: $($wslTest.Gettype())"

        $failed = $true
        $error_message += "Pinging $WindowsHostName from $WslInstanceName failed:`n$wslTest"
    }

    Write-Debug "$(_@) Starting WSL instance $WslInstanceName for testing ping from Windows."
    $runCommand = 'sleep 60; exit'
    $wslJob = Invoke-WslExe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c "`"$runCommand`"" &
    Start-Sleep -Seconds 7  # let WSL startup before pinging

    Write-Verbose "Testing Ping from Windows to WSL instance ${WslInstanceName} ..."
    $windowsTest = $(ping -n 1 $WslHostName) -join "`n"

    Write-Debug "$(_@) `$windowsTest result: $windowsTest"

    if ($windowsTest -notmatch 'Lost = 0 \(0% loss\)') {
        Write-Verbose "Ping from Windows to WSL instance ${WslInstanceName} failed:`n$windowsTest"
        $failed = $true
        $error_message += "`nPinging $WslHostName from Windows failed:`n$windowsTest"
    }

    $wslJob.StopJob()
    $wslJob.Dispose()

    if ($failed) {
        Write-Verbose "$($MyInvocation.MyCommand.Name) on $WslInstanceName Failed!"
        Write-Error ($error_message -join "`n") -ErrorAction Stop
    }
    else {
        Write-Host "Test of WSL-IpHandler Installation on $WslInstanceName Succeeded!" -ForegroundColor Green
    }
}

function Update-WslIpHandlerModule {
    <#
    .SYNOPSIS
    Downloads latest master.zip from this Modules repository at github.com and updates local Module's files

    .DESCRIPTION
    Updates local Module's files to the latest available at Module's repository at github.com.
    If `git` is available uses `git pull origin master`, otherwise Invoke-WebRequest will be used to download master.zip and expand it to Module's directory replacing all files with downloaded ones.

    .PARAMETER GitExePath
    Path to git.exe if it can not be located with environment's PATH variable.

    .PARAMETER DoNotUseGit
    If given will update module using Invoke-WebRequest command (built-in in Powershell) even if git.exe is on PATH.

    .PARAMETER Force
    If given will update module even if there is version mismatch between installed version and version in repository.

    .EXAMPLE
    Update-WslIpHandlerModule

    Will update this module using git.exe if it can be located, otherwise will use Invoke-WebRequest to download latest master.zip from repository and overwrite all existing file in WSL-IpHandler module's folder.

    .NOTES
    The default update mode is to use git.exe if it can be located with PATH.
    Adding -GitExePath parameter will allow to use git.exe that is not on PATH.
    All files in this Module's folder will be removed before update!
    #>
    param(
        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [Alias('Git')]
        [string]$GitExePath,

        [Parameter()]
        [switch]$NoGit,

        [Parameter()]
        [switch]$Force
    )
    $modulePath = $MyInvocation.MyCommand.Module.ModuleBase

    $params = @{
        ModuleNameOrPath = $modulePath
        GithubUserName   = $MyInvocation.MyCommand.Module.Author
        Branch           = 'master'
        Force            = $Force
        NoGit            = $NoGit
    }
    if ($GitExePath) { $params.GitExePath = $GitExePath }

    $updaterModuleName = 'Update-ModuleFromGithub'
    $updaterModulePath = Join-Path $PSScriptRoot 'SubModules' "$updaterModuleName.psm1" -Resolve
    Import-Module $updaterModulePath -Function Update-ModuleFromGithub

    Update-ModuleFromGithub @params @PSBoundParameters

    Remove-Module $updaterModulePath -Force -ErrorAction SilentlyContinue

    Import-Module $modulePath -Function Update-WslBashScripts -Force

    $staticIps = Get-WslConfigStaticIpSection
    if ($staticIps.Count -gt 0) {
        $staticIps.GetEnumerator() | ForEach-Object {
            $wslHost = (Get-HostForIpAddress $_.Value) ?? $_.Key
            Update-WslBashScripts -WslInstanceName $_.Key -WslHostName $wslHost
        }
    }
}

function Uninstall-WslIpHandlerModule {
    [CmdletBinding()]
    param()
    $moduleLocation = Split-Path $MyInvocation.MyCommand.Module.Path
    $prompt = 'Please confirm that the following directory should be irreversibly DELETED:'
    if ($PSCmdlet.ShouldContinue($moduleLocation, $prompt)) {
        $moduleName = $MyInvocation.MyCommand.ModuleName
        Remove-Module $moduleName -Force
        if ((Get-Location).Path.Contains($moduleLocation)) {
            Set-Location (Split-Path $moduleLocation)
        }
        Write-Verbose "Removing $moduleLocation..."
        Remove-Item -Path $moduleLocation -Recurse -Force
    }
    else {
        Write-Verbose 'Uninstall operation was canceled!'
    }
}

function Invoke-WslExe {
    <#
    .SYNOPSIS
    Takes any parameters and passes them transparently to wsl.exe. If parameter(s) requires actually starting up WSL Instance - will set up WSL Network Adapter using settings in .wslconfig. Requires administrator privileges if required adapter is not active.

    .DESCRIPTION
    This command acts a wrapper around `wsl.exe` taking all it's parameters and passing them along.
    Before actually executing `wsl.exe` this command checks if WSL Network Adapter with required parameters is active (i.e. checks if network parameters in .wslconfig are in effect). If active adapter parameters are different from those in .wslconfig - active adapter is removed and new one with required parameters is activated. Requires administrator privileges if required adapter is not active.

    .PARAMETER Timeout
    Number of seconds to wait for vEthernet (WSL) Network Connection to become available when WSL Hyper-V Network Adapter had to be created.

    .EXAMPLE
    wsl -l -v

    Will list all installed WSL instances with their detailed status.

    wsl -d Ubuntu

    Will check if WSL Network Adapter is active and if not initialize it. Then it will execute `wsl.exe -d Ubuntu`. Thus allowing to use WSL instances with static ip addressed without manual interaction with network settings, etc.

    .NOTES
    During execution of Install-WslHandler, when a static mode of operation is specified, there will be an alias created: `wsl` for Invoke-WslExe. When working in Powershell this alias shadows actual windows `wsl` command to enable effortless operation in Static IP Mode. When there is a need to execute actual windows `wsl` command from withing Powershell use `wsl.exe` (i.e. with extension) to execute native Windows command.
    #>
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
    $argsCopy = $args.Clone()
    $setWslAdapterParams = @{}

    $DebugPreferenceOriginal = $DebugPreference

    if ('-timeout' -in $argsCopy) {
        $timeoutIndex = $argsCopy.IndexOf('-timeout')
        [int]$Timeout = $argsCopy[$timeoutIndex + 1]
        $argsCopy = $argsCopy[0..($timeoutIndex - 1)]
        $argsCopy += $argsCopy[($timeoutIndex + 2)..($timeoutIndex.Count)]
    }
    else {
        $Timeout = 30
    }
    if ('-debug' -in $argsCopy) {
        $DebugPreference = 'Continue'
        $argsCopy = ($argsCopy | Where-Object { $_ -notlike '-debug' }) ?? @()
        $setWslAdapterParams.Debug = $true
    }

    if ('-verbose' -in $argsCopy) {
        $VerbosePreference = 'Continue'
        $argsCopy = ($argsCopy | Where-Object { $_ -notlike '-verbose' }) ?? @()
        $setWslAdapterParams.Verbose = $true
    }

    if ($argsCopy.Count -eq 0 -or (ArgsAreExec $argsCopy)) {
        Write-Debug "$(_@) `$args: $argsCopy"
        Write-Debug "$(_@) Passed arguments require Setting WSL Network Adapter."

        Set-WslNetworkAdapter @setWslAdapterParams -WaitForWslNetworkConnection -Timeout $Timeout
    }

    $GetWslNetworkConnection = { Get-NetIPAddress -InterfaceAlias $vEthernetWsl -AddressFamily IPv4 -ErrorAction SilentlyContinue }
    $GetWslNetworkStatus = { if ($null -eq (& $GetWslNetworkConnection)) { $false } else { $true } }

    $waitingMessage = ''
    $eventLabel = "$vEthernetWsl Network Connection Setup"
    $waitingParams = @{
        ValidationScript = $GetWslNetworkStatus
        EventLabel       = $eventLabel
        MessageVariable  = ([ref]$waitingMessage)
        Timeout          = $Timeout
    }
    Write-Debug "$(_@) Waiting Params: $(& {$args} @waitingParams)"

    if (Wait-ForExpressionTimeout @waitingParams) {
        if ($waitingMessage) { Write-Verbose "$waitingMessage" }
        & wsl.exe @argsCopy @PSBoundParameters
    }
    else {
        if ($waitingMessage) { Write-Error "$waitingMessage" }
        else { Write-Error "Error waiting for $eventLabel - operation timed out." }
    }
    $DebugPreference = $DebugPreferenceOriginal
}

function Get-WslScheduledTaskCredential {
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter()]
        [int]$MaxNumberOfAttempts
    )
    $getCredential = {
        $getCredParams = @{
            Title   = 'WSL-IpHandler'
            Message = 'To Create Scheduled Task That Can Run Whether User Logged On Or Not, Please Enter'
        }
        if ($UserName) {
            $FullUserName = if ($UserName.Contains('\')) { $UserName } else { "$env:USERDOMAIN\$UserName" }
            $getCredParams.UserName = $FullUserName
        }
        Get-Credential @getCredParams
    }
    $credentialValidator = {
        param([System.Management.Automation.PSCredential]$credential)
        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine, $env:USERDOMAIN)
        $networkCredential = $credential.GetNetworkCredential()
        $context.ValidateCredentials($networkCredential.UserName, $networkCredential.Password)
    }

    $waitingMessage = ''
    [System.Management.Automation.PSCredential]$validCredential = $null
    $waitParams = @{
        ValidationScript      = $credentialValidator
        ValidationInputScript = $getCredential
        Countdown             = $MaxNumberOfAttempts
        EventLabel            = 'Getting credential for WSL-IpHandler Scheduled Task'
        OutputVariable        = ([ref]$validCredential)
        MessageVariable       = ([ref]$waitingMessage)
    }

    if (Wait-ForExpressionCountdown @waitParams) {
        Write-Debug "$(_@) Valid Credential: $(& {$args} @validCredential)"
        $validCredential
    }
    else {
        Throw "$waitingMessage"
    }

}

function Wait-ForExpressionTimeout {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [scriptblock]$ValidationInputScript,

        [Parameter(Mandatory)]
        [int]$Timeout,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventLabel,

        [Parameter()]
        [int]$SleepTime = 3,

        [Parameter()]
        [ref]$OutputVariable,

        [Parameter()]
        [ref]$MessageVariable,

        [Parameter()]
        [switch]$ThrowOnFail
    )
    $timer = [system.diagnostics.stopwatch]::StartNew()

    $validated = $false
    while ($timer.Elapsed.TotalSeconds -lt $Timeout) {
        if ($ValidationInputScript) {
            $outValue = & $ValidationInputScript
            $validatedValue = & $ValidationScript $outValue
        }
        else {
            $outValue = $null
            $validatedValue = & $ValidationScript
        }
        if ($validatedValue) {
            $validated = $true
            if ($OutputVariable) { $OutputVariable.Value = $outValue }
            break
        }
        else {
            $totalSecs = [math]::Round($timer.Elapsed.TotalSeconds, 0)
            Write-Debug "$(_@) $EventLabel unsuccessful after [$totalSecs] seconds..."
            Start-Sleep -Seconds $SleepTime
        }
    }

    if ($validated) {
        $successMessage = "$EventLabel succeeded after [$([math]::Round($timer.Elapsed.TotalSeconds, 0))] seconds."
        if ($MessageVariable) { $MessageVariable.Value = $successMessage }
        Write-Debug "$(_@) $successMessage"
        $true
    }
    else {
        $failedMessage = "$EventLabel did not succeed after [$Timeout] seconds. Try increasing timeout with '-Timeout' parameter."
        if ($MessageVariable) { $MessageVariable.Value = $failedMessage }
        if ($ThrowOnFail) {
            Throw "$failedMessage"
        }
        else {
            Write-Debug "$(_@) $failedMessage"
            $false
        }
    }
}

function Wait-ForExpressionCountdown {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [scriptblock]$ValidationInputScript,

        [Parameter(Mandatory, ParameterSetName = 'CountDown')]
        [int]$Countdown,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventLabel,

        [Parameter()]
        [ref]$OutputVariable,

        [Parameter()]
        [ref]$MessageVariable,

        [Parameter()]
        [switch]$ThrowOnFail
    )

    $validated = $false
    foreach ($attempt in (1..$Countdown)) {
        if ($ValidationInputScript) {
            $outValue = & $ValidationInputScript
            $validatedValue = & $ValidationScript $outValue
        }
        else {
            $outValue = $null
            $validatedValue = & $ValidationScript
        }
        if ($validatedValue) {
            $validated = $true
            if ($OutputVariable) { $OutputVariable.Value = $outValue }
            break
        }
        else {
            Write-Debug "$(_@) $EventLabel unsuccessful after [$attempt] out of [$CountDown] attempts..."
        }
    }

    if ($validated) {
        $successMessage = "$EventLabel succeeded after [$attempt] out of [$CountDown] attempts."
        if ($MessageVariable) { $MessageVariable.Value = $successMessage }
        Write-Debug "$(_@) $successMessage"
        $true
    }
    else {
        $failedMessage = "$EventLabel did not succeed after [$attempt] out of [$CountDown] attempts."
        if ($MessageVariable) { $MessageVariable.Value = $failedMessage }
        if ($ThrowOnFail) {
            Throw "$failedMessage"
        }
        else {
            Write-Debug "$(_@) $failedMessage"
            $false
        }
    }
}

function Wait-ForExpression {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [scriptblock]$ValidationInputScript,

        [Parameter(Mandatory, ParameterSetName = 'Timer')]
        [int]$Timeout,

        [Parameter(Mandatory, ParameterSetName = 'CountDown')]
        [int]$Countdown,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventLabel,

        [Parameter(ParameterSetName = 'Timer')]
        [int]$SleepTime = 3,

        [Parameter()]
        [ref]$OutputVariable,

        [Parameter()]
        [ref]$MessageVariable,

        [Parameter()]
        [switch]$ThrowOnFail
    )
    switch ($PSCmdlet.ParameterSetName) {
        'Timer' {
            $timer = [system.diagnostics.stopwatch]::StartNew()
            $condition = { $timer.Elapsed.TotalSeconds -lt $Timeout }
            $whileAction = {
                $totalSecs = [math]::Round($timer.Elapsed.TotalSeconds, 0)
                Write-Debug "$(_@) $EventLabel unsuccessful after [$totalSecs] seconds..."
                Start-Sleep -Seconds $SleepTime
            }
            $getSuccessMessage = {
                "$EventLabel succeeded after [$([math]::Round($timer.Elapsed.TotalSeconds, 0))] seconds."
            }
            $getFailedMessage = {
                "$EventLabel did not succeed after [$Timeout] seconds. Try increasing timeout with '-Timeout' parameter."
            }
        }
        'CountDown' {
            $attempt = 1
            $condition = { $attempt -le $Countdown }
            $whileAction = {
                Write-Debug "$(_@) $EventLabel unsuccessful after [$attempt] out of [$CountDown] attempts..."
                $attempt = + 1
            }
            $getSuccessMessage = {
                "$EventLabel succeeded after [$attempt] out of [$CountDown] attempts."
            }
            $getFailedMessage = {
                "$EventLabel did not succeed after [$attempt] out of [$CountDown] attempts."
            }
        }
        Default { Throw "$(_@) Unexpected ParameterSetName '$_', expected 'Timer' or 'CountDown'." }
    }

    $validated = $false
    while ((& $condition)) {
        if ($ValidationInputScript) {
            $outValue = & $ValidationInputScript
            $validatedValue = & $ValidationScript $outValue
        }
        else {
            $outValue = $null
            $validatedValue = & $ValidationScript
        }
        if ($validatedValue) {
            $validated = $true
            if ($OutputVariable) { $OutputVariable.Value = $outValue }
            break
        }
        else {
            & $whileAction
        }
    }

    if ($validated) {
        $successMessage = & $getSuccessMessage
        if ($MessageVariable) { $MessageVariable.Value = $successMessage }
        Write-Debug "$(_@) $successMessage"
        $true
    }
    else {
        $failedMessage = & $getFailedMessage
        if ($MessageVariable) { $MessageVariable.Value = $failedMessage }
        if ($ThrowOnFail) {
            Throw "$failedMessage"
        }
        else {
            Write-Debug "$(_@) $failedMessage"
            $false
        }
    }
}

Set-Alias -Name wsl -Value Invoke-WslExe

Register-ArgumentCompleter -CommandName Install-WslIpHandler -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Uninstall-WslIpHandler -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Install-WslBashScripts -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Uninstall-WslBashScripts -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Update-WslBashScripts -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Set-WslInstanceStaticIpAddress -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Remove-WslInstanceStaticIpAddress -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Test-WslInstallation -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter
