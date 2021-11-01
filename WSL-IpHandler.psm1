$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ArgumentsCompleters.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'WindowsCommandsUTF16Converters.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'FunctionsWslConfig.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'FunctionsHostsFile.ps1' -Resolve) | Out-Null
. (Join-Path $PSScriptRoot 'FunctionsPrivateData.ps1' -Resolve) | Out-Null

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
        c) Powershell profile file (CurrentUserAllHosts) will be modified: This module will be imported and an alias `wsl` to Invoke-WslStatic will be created).

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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'Dynamic')]
        [Parameter(ParameterSetName = 'Static')]
        [Alias('Name')]
        # [ArgumentCompleter({ WslNameCompleter $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter })]
        [string]$WslInstanceName,

        [Parameter(Mandatory, ParameterSetName = 'Static')][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter(ParameterSetName = 'Static')][Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Parameter(ParameterSetName = 'Static')][Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Parameter(ParameterSetName = 'Static')][Alias('IpAddress')]
        [ipaddress]$WslInstanceIpAddress,

        [ValidateNotNullOrEmpty()]
        [string]$WslHostName = $WslInstanceName,

        [string]$WindowsHostName = 'windows',

        [Parameter(ParameterSetName = 'Static')]
        [switch]$DontModifyPsProfile,

        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name

    Write-Host "PowerShell installing WSL-IpHandler to $WslInstanceName..."
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

    #region Save Network Parameters to .wslconfig and Setup Network Adapters
    $configModified = $false

    Set-WslConfigValue -SectionName (Get-NetworkSectionName) -KeyName (Get-WindowsHostNameKeyName) -Value $WindowsHostName -Modified ([ref]$configModified)

    if ($null -ne $GatewayIpAddress) {
        Set-WslNetworkConfig -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $DNSServerList -Modified ([ref]$configModified)

        Set-WslNetworkAdapter

        Write-Verbose "Setting Static IP Address: $($WslInstanceIpAddress.IPAddressToString) for $WslInstanceName."
        Set-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength -WslInstanceIpAddress $WslInstanceIpAddress.IPAddressToString -Modified ([ref]$configModified)

        $WslHostIpOrOffset = $WslInstanceIpAddress.IPAddressToString
    }
    else {
        $WslIpOffset = Get-WslIpOffset $WslInstanceName
        Write-Verbose "Setting Automatic IP Offset: $WslIpOffset for $WslInstanceName."
        Set-WslIpOffset $WslInstanceName $WslIpOffset -Modified ([ref]$configModified)

        $WslHostIpOrOffset = $WslIpOffset
    }


    if ($configModified) {
        Write-Verbose "Saving Configuration in .wslconfig $($BackupWslConfig ? 'with Backup ' : '')..."
        Write-WslConfig -Backup:$BackupWslConfig
    }
    #endregion  Save Network Parameters to .wslconfig and Setup Network Adapters

    #region Run Bash Installation Script
    $BashInstallScriptWslPath = '$(wslpath "' + "$BashInstallScript" + '")'
    $BashInstallParams = @("`"$BashAutorunScriptSource`"", "$BashAutorunScriptTarget",
        "`"$WinHostsEditScript`"", "$WindowsHostName", "$WslHostName", "$WslHostIpOrOffset"
    )
    Write-Verbose "Running Bash WSL installation script: $BashInstallScript"

    $debug_var = if ($DebugPreference -gt 0) { 'DEBUG=1' } else { '' }
    $verbose_var = if ($VerbosePreference -gt 0) { 'VERBOSE=1' } else { '' }

    $bashInstallScriptOutput = wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' $debug_var $verbose_var bash $BashInstallScriptWslPath @BashInstallParams

    Write-Debug "${fn}: Head and tail from Bash Installation Script Output:"
    Write-Debug "$($bashInstallScriptOutput | Select-Object -First 5)"
    Write-Debug "$($bashInstallScriptOutput | Select-Object -Last 5)"

    if ($bashInstallScriptOutput -and ($bashInstallScriptOutput | Where-Object { $_.StartsWith('[Error') } | Measure-Object).Count -gt 0) {
        Write-Error "Error(s) occurred while running Bash Installation script: $BashInstallScriptWslPath with parameters: $($BashInstallParams | Out-String)`n$($bashInstallScriptOutput -join "`n")"
        return
    }
    #endregion Run Bash Installation Script

    #region Set Content to Powershell Profile
    if ($PSCmdlet.ParameterSetName -eq 'Static' -and -not $DontModifyPsProfile.IsPresent) {
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
        Write-Debug "${fn} ScriptStackTrace: $($_.ScriptStackTrace)"
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
    [CmdletBinding()]
    param (
        [AllowNull()][AllowEmptyString()]
        [Alias('Name')]
        [string]$WslInstanceName,

        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name

    Write-Host "PowerShell Uninstalling WSL-IpHandler from $WslInstanceName..."
    #region Bash UnInstallation Script Path
    $BashUninstallScript = Get-SourcePath 'BashUninstall'
    #endregion Bash InInstallation Script Path

    #region WSL Autorun
    # Get Path to bash script that assigns IP to wsl instance and launches PS autorun script
    $BashAutorunScriptName = Split-Path -Leaf (Get-SourcePath 'BashAutorun')
    $BashAutorunScriptTarget = Get-ScriptLocation 'BashAutorun'
    #endregion WSL Autorun

    #region Remove Bash Autorun
    $BashUninstallScriptWslPath = '$(wslpath "' + "$BashUninstallScript" + '")'
    $BashUninstallParams = "$BashAutorunScriptName", "$BashAutorunScriptTarget"

    Write-Verbose "Running Bash WSL Uninstall script $BashUninstallScript"
    Write-Debug "${fn}: `$DebugPreference=$DebugPreference"
    Write-Debug "${fn}: `$VerbosePreference=$VerbosePreference"

    $debug_var = if ($DebugPreference -gt 0) { 'DEBUG=1' } else { '' }
    $verbose_var = if ($VerbosePreference -gt 0) { 'VERBOSE=1' } else { '' }

    $bashUninstallScriptOutput = wsl.exe -d $WslInstanceName sudo -E env '"PATH=$PATH"' $debug_var $verbose_var bash $BashUninstallScriptWslPath @BashUninstallParams

    if ($bashUninstallScriptOutput -and ($bashUninstallScriptOutput | Where-Object { $_.StartsWith('[Error') } | Measure-Object).Count -gt 0) {
        Write-Debug "Bash Uninstall Script returned:`n$bashUninstallScriptOutput"
    }

    Write-Debug "${fn}: Removed Bash Autorun scripts."
    #endregion Remove Bash Autorun

    #region Restart WSL Instance
    wsl.exe -t $WslInstanceName
    Write-Debug "${fn}: Restarted $WslInstanceName"
    #endregion Restart WSL Instance

    #region Remove WSL Instance Static IP from .wslconfig
    $wslconfigModified = $false
    Remove-WslInstanceStaticIpAddress -WslInstanceName $WslInstanceName -Modified ([ref]$wslconfigModified)
    #endregion Remove WSL Instance Static IP from .wslconfig

    #region Remove WSL Instance IP Offset from .wslconfig
    Write-Debug "${fn}: Removing IP address offset for $WslInstanceName from .wslconfig..."
    Remove-WslConfigValue (Get-WslIpOffsetSectionName) $WslInstanceName -Modified ([ref]$wslconfigModified)
    #endregion Remove WSL Instance IP Offset from .wslconfig

    #region Remove WSL Network Configuration from .wslconfig
    Write-Debug "${fn}: Removing WSL Network Configuration for $WslInstanceName ..."
    Remove-WslNetworkConfig -Modified ([ref]$wslconfigModified)
    #endregion Remove WSL Network Configuration from .wslconfig

    #region Remove WSL Instance IP from windows hosts file
    $hostsModified = $false
    Write-Debug "${fn}: Removing record for $WslInstanceName from Windows Hosts ..."
    $content = (Get-HostsFileContent)
    Write-Debug "${fn}: Removing Host: $WslInstanceName from $($content.Count) Windows Hosts records ..."
    $content = Remove-HostFromRecords -Records $content -HostName $WslInstanceName -Modified ([ref]$hostsModified)
    Write-Debug "${fn}: Setting Windows Hosts file with $($content.Count) records ..."
    #endregion Remove WSL Instance IP from windows hosts file

    #region Save Modified .wslconfig and hosts Files
    if ($wslconfigModified) { Write-WslConfig -Backup:$BackupWslConfig }
    if ($hostsModified) { Write-HostsFileContent -Records $content }
    #endregion Save Modified .wslconfig and hosts Files

    #region Remove Content from Powershell Profile
    # Remove Profile Content if there are no more Static IP assignments
    if ((Get-WslConfigSectionCount (Get-StaticIpAddressesSectionName)) -le 0) {
        Write-Debug "${fn}: Removing Powershell Profile Modifications ..."
        Remove-ProfileContent
    }
    #endregion Remove Content from Powershell Profile

    Write-Host "PowerShell successfully uninstalled WSL-IpHandler from $WslInstanceName!"
}

function Set-ProfileContent {
    <#
    .SYNOPSIS
    Modifies Powershell profile to set alias `wsl` -> Invoke-WslStatic

    .DESCRIPTION
    Modifies Powershell profile file (by default CurrentUserAllHosts) to set alias `wsl` -> Invoke-WslStatic.

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
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: ProfilePath: $ProfilePath"

    $handlerContent = Get-ProfileContent

    $modulePath = Split-Path $MyInvocation.MyCommand.Module.Path
    $modulePrefix = Split-Path $modulePath

    if (-not $Env:PSModulePath.contains($modulePrefix, 'OrdinalIgnoreCase')) {
        $handlerContent = $handlerContent -replace 'Import-Module WSL-IpHandler', "Import-Module '$modulePath'"
    }

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
        Write-Warning "Powershell profile was modified: $ProfilePath.`nThe changes will take effect after Powershell session is restarted!"
        # . $ProfilePath  # !!! DONT DO THAT -> IT Removes ALL Sourced functions (i.e. '. File.ps1')
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
    param($ProfilePath = $profile.CurrentUserAllHosts)
    $fn = $MyInvocation.MyCommand.Name

    Write-Debug "${fn}: ProfilePath: $ProfilePath"

    $handlerContent = Get-ProfileContent

    $modulePath = $MyInvocation.MyCommand.Module.Path
    $moduleFolder = Split-Path $modulePath

    if (-not $Env:PSModulePath.contains($moduleFolder, 'OrdinalIgnoreCase')) {
        $handlerContent = $handlerContent -replace 'Import-Module WSL-IpHandler', "Import-Module '$modulePath'"
    }

    $content = (Get-Content -Path $ProfilePath -ErrorAction SilentlyContinue) ?? @()
    if ($content) {
        $content = $content | Where-Object { $handlerContent -notcontains $_ }
        # $content = (($content -join "`n") -replace ($handlerContent -join "`n")) -split "`n"
        Set-Content -Path $ProfilePath -Value $content -Force
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
    $fn = $MyInvocation.MyCommand.Name

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }

    $sectionName = Get-StaticIpAddressesSectionName

    if ($null -eq $WslInstanceIpAddress) {
        $existingIp = Get-WslConfigValue -SectionName $sectionName -KeyName $WslInstanceName -DefaultValue $null -Modified $Modified
        if ($existingIp) {
            Write-Debug "${fn}: `$WslInstanceIpAddress is `$null. Using existing assignment:  for $WslInstanceName = $existingIp"
            $WslInstanceIpAddress = $existingIp
        }
        else {
            Write-Debug "${fn}: `$WslInstanceIpAddress is `$null. Getting Available Static Ip Address."
            $WslInstanceIpAddress = Get-AvailableStaticIpAddress $GatewayIpAddress
        }
    }

    Write-Debug "${fn}: `$WslInstanceName=$WslInstanceName `$GatewayIpAddress=$GatewayIpAddress `$PrefixLength=$PrefixLength `$WslInstanceIpAddress=$($WslInstanceIpAddress ? $WslInstanceIpAddress.IPAddressToString : "`$null")"

    $null = Test-ValidStaticIpAddress -IpAddress $WslInstanceIpAddress -GatewayIpAddress $GatewayIpAddress -PrefixLength $PrefixLength


    Set-WslConfigValue $sectionName $WslInstanceName $WslInstanceIpAddress.IPAddressToString -Modified $Modified -UniqueValue

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
    $fn = $MyInvocation.MyCommand.Name
    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }

    Write-Debug "${fn}: `$WslInstanceName=$WslInstanceName"
    Write-Debug "${fn}: Before Calling Remove-WslConfigValue `$Modified=$($Modified.Value)"

    Remove-WslConfigValue (Get-StaticIpAddressesSectionName) $WslInstanceName -Modified $Modified
    Write-Debug "${fn}: After Calling Remove-WslConfigValue `$Modified=$($Modified.Value)"

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere' -and $localModified) {
        Write-Debug "${fn}: Calling Write-WslConfig -Backup:$BackupWslConfig"
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
        [Parameter(Mandatory)][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Alias('Prefix')]
        [int]$PrefixLength = 24,

        [Alias('DNS')]
        [string]$DNSServerList, # String with Comma separated ipaddresses/hosts

        [Parameter(Mandatory, ParameterSetName = 'SaveExternally')]
        [ref]$Modified,

        [Parameter(ParameterSetName = 'SaveHere')]
        [switch]$BackupWslConfig
    )
    $fn = $MyInvocation.MyCommand.Name

    if ($PSCmdlet.ParameterSetName -eq 'SaveHere') {
        $localModified = $false
        $Modified = [ref]$localModified
    }

    $DNSServerList = $DNSServerList ? $DNSServerList : $GatewayIpAddress
    Write-Debug "${fn}: Seting Wsl Network Parameters: GatewayIpAddress=$GatewayIpAddress PrefixLength=$PrefixLength DNSServerList=$DNSServerList"

    Set-WslConfigValue (Get-NetworkSectionName) (Get-GatewayIpAddressKeyName) $GatewayIpAddress.IPAddressToString -Modified $Modified

    Set-WslConfigValue (Get-NetworkSectionName) (Get-PrefixLengthKeyName) $PrefixLength -Modified $Modified

    Set-WslConfigValue (Get-NetworkSectionName) (Get-DnsServersKeyName) $DNSServerList -Modified $Modified

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

    $networkSectionName = (Get-NetworkSectionName)
    $staticIpSectionName = (Get-StaticIpAddressesSectionName)

    if ( $Force.IsPresent -or (Get-WslConfigSectionCount $staticIpSectionName) -le 0) {
        Remove-WslConfigValue $networkSectionName (Get-GatewayIpAddressKeyName) -Modified $Modified

        Remove-WslConfigValue $networkSectionName (Get-PrefixLengthKeyName) -Modified $Modified

        Remove-WslConfigValue $networkSectionName (Get-DnsServersKeyName) -Modified $Modified

        Remove-WslConfigValue $networkSectionName (Get-WindowsHostNameKeyName) -Modified $Modified
    }
    else {
        $staticIpSection = Get-WslConfigSection $staticIpSectionName
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

    .EXAMPLE
    Set-WslNetworkConfig -GatewayIpAddress 172.16.0.1
    Set-WslNetworkAdapter

    First command will set Gateway IP Address to 172.16.0.1, SubNet length to 24 and DNS Servers to 172.16.0.1 saving the settings in .wslconfig file.
    Second command will actually put these settings in effect. If there was active WSL network adapter in the system - it will be removed beforehand. Any running WSL instances will be shutdown.

    .NOTES
    Executing this command with specified parameters will not save these settings to .wslconfig. To save settings use command Set-WslNetworkConfig.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][Alias('Gateway')]
        [ipaddress]$GatewayIpAddress,

        [Parameter()][Alias('Prefix')]
        [int]$PrefixLength,

        [Parameter()][Alias('DNS')]
        [string]$DNSServerList  # Comma separated ipaddresses/hosts
    )
    $fn = $MyInvocation.MyCommand.Name
    $networkSectionName = (Get-NetworkSectionName)

    $GatewayIpAddress ??= Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-GatewayIpAddressKeyName) -DefaultValue $null

    if ($null -eq $GatewayIpAddress) {
        $msg = 'Gateway IP Address is not specified neither as parameter nor in .wslconfig. WSL Hyper-V Network Adapter will be managed by Windows!'
        Write-Warning $msg
        return
    }

    $PrefixLength = $PSBoundParameters.ContainsKey('PrefixLength') ? $PrefixLength : (Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-PrefixLengthKeyName) -DefaultValue 24)

    $DNSServerList = [string]::IsNullOrWhiteSpace($DNSServerList) ? (Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-DnsServersKeyName) -DefaultValue $GatewayIpAddress) : $DNSServerList

    Write-Debug "${fn}: `$GatewayIpAddress='$GatewayIpAddress'; `$PrefixLength=$PrefixLength; `$DNSServerList='$DNSServerList'"

    $wslAlias = 'vEthernet (WSL)'
    $wslAdapter = Get-NetIPAddress -InterfaceAlias $wslAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue

    # Check if there is existing WSL Adapter
    if ($null -ne $wslAdapter) {
        Write-Verbose "${fn}: Hyper-V VM Adapter 'WSL' already exists."
        Write-Debug "${fn}: `$wslAdapter`n$($wslAdapter | Out-String)"

        # Check if existing WSL Adapter has required settings
        if ($wslAdapter.IPAddress -eq $GatewayIpAddress -and $wslAdapter.PrefixLength -eq $PrefixLength) {
            Write-Verbose "Hyper-V VM Adapter 'WSL' already has required GatewayAddress: '$GatewayIpAddress' and PrefixLength: '$PrefixLength'!"
            return
        }
    }

    # Check if any of existing adapters overlap with required subnet
    Import-Module (Join-Path $PSScriptRoot 'IP-Calc.psm1' -Resolve) -Function Get-IpCalcResult -Verbose:$false -Debug:$false | Out-Null

    $otherAdapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -Property InterfaceAlias, IPAddress, PrefixLength

    if ($otherAdapters) {
        $wslIpCalc = Get-IpCalcResult -IPAddress $GatewayIpAddress -PrefixLength $PrefixLength

        foreach ($adapter in $otherAdapters) {
            if ($adapter.InterfaceAlias -ne $wslAlias) {
                $otherIpCalc = Get-IpCalcResult -IPAddress $adapter.IPAddress -PrefixLength $adapter.PrefixLength
                if ($wslIpCalc.Overlaps($otherIpCalc)) {
                    Throw "Cannot create Hyper-V VM Adapter 'WSL' with GatewayAddress: $GatewayIpAddress and PrefixLength: $PrefixLength, because it's subnet: $($wslIpCalc.CIDR) overlaps with existing subnet of '$($adapter.InterfaceAlias)': $($otherIpCalc.CIDR)"
                }
            }
        }
    }

    # Setup required WSL adapter
    Write-Debug "${fn}: Shutting down all WSL instances..."
    wsl.exe --shutdown

    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null
    $setAdapterScript = Join-Path $PSScriptRoot 'Set-WslNetworkAdapter.ps1' -Resolve
    $scriptArguments = @($GatewayIpAddress, $PrefixLength, $DNSServerList)

    if (IsElevated) {
        & $setAdapterScript @scriptArguments
    }
    else {
        Invoke-ScriptElevated $setAdapterScript -ScriptArguments $scriptArguments -ScriptCommonParameters $PSBoundParameters
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
    . (Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve) | Out-Null
    $removeAdapterScript = Join-Path $PSScriptRoot 'Remove-WslNetworkAdapter.ps1' -Resolve

    & $removeAdapterScript
    # if (IsElevated) {
    #     & $removeAdapterScript
    # }
    # else {
    #     Invoke-ScriptElevated $removeAdapterScript -ScriptCommonParameters $PSBoundParameters
    # }
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

    $fn = $MyInvocation.MyCommand.Name
    $networkSectionName = (Get-NetworkSectionName)
    $failed = $false

    if (-not $PSBoundParameters.ContainsKey('WindowsHostName')) {
        $WindowsHostName = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-WindowsHostNameKeyName) -DefaultValue 'windows'
    }

    $error_message = @()

    $bashTestCommand = "ping -c1 $WindowsHostName 2>&1"
    Write-Verbose "Testing Ping from WSL instance ${WslInstanceName}: `"$bashTestCommand`" ..."
    $wslTest = (wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$bashTestCommand`") -join "`n"

    Write-Debug "${fn}: `$wslTest: $wslTest"

    if ($wslTest -notmatch ', 0% packet loss') {
        Write-Verbose "Ping from WSL Instance $WslInstanceName failed:`n$wslTest"
        Write-Debug "${fn}: TypeOf `$wslTest: $($wslTest.Gettype())"

        $failed = $true
        $error_message += "Pinging $WindowsHostName from $WslInstanceName failed:`n$wslTest"
    }

    # Before testing WSL IP address - make sure WSL Instance is up and running
    if (-not (Get-WslIsRunning $WslInstanceName)) {
        $runCommand = 'sleep 1; exit'  # Even after 'exit' wsl instance should be running in background
        Write-Debug "${fn}: Running WSL instance $WslInstanceName for testing ping from Windows."
        $null = (& wsl.exe -d $WslInstanceName env BASH_ENV=/etc/profile bash -c `"$runCommand`")
    }

    if (Get-WslIsRunning $WslInstanceName) {
        Write-Verbose "Testing Ping from Windows to WSL instance ${WslInstanceName} ..."
        $windowsTest = $(ping -n 1 $WslHostName) -join "`n"

        Write-Debug "${fn}: `$windowsTest: $windowsTest"

        if ($windowsTest -notmatch 'Lost = 0 \(0% loss\)') {
            Write-Verbose "Ping from Windows to WSL instance ${WslInstanceName} failed:`n$windowsTest"
            $failed = $true
            $error_message += "`nPinging $WslHostName from Windows failed:`n$windowsTest"
        }
    }
    else {
        $failed = $true
        $error_message += "Could not start WSL Instance: $WslInstanceName to test Ping from Windows"
    }

    if ($failed) {
        Write-Verbose "${fn}: on $WslInstanceName Failed!"
        Write-Error ($error_message -join "`n") -ErrorAction Stop
    }
    else {
        Write-Host "Test of WSL-IpHandler Installation on $WslInstanceName Succeeded!" -ForegroundColor Green
    }
}

function Invoke-WslStatic {
    <#
    .SYNOPSIS
    Takes any parameters and passes them transparently to wsl.exe. If parameter(s) requires actually starting up WSL Instance - will set up WSL Network Adapter using settings in .wslconfig. Requires administrator privileges if required adapter is not active.

    .DESCRIPTION
    This command acts a wrapper around `wsl.exe` taking all it's parameters and passing them along.
    Before actually executing `wsl.exe` this command checks if WSL Network Adapter with required parameters is active (i.e. checks if network parameters in .wslconfig are in effect). If active adapter parameters are different from those in .wslconfig - active adapter is removed and new one with required parameters is activated. Requires administrator privileges if required adapter is not active.

    .PARAMETER arguments
    All arguments accepted by wsl.exe

    .EXAMPLE
    wsl -l -v

    Will list all installed WSL instances with their detailed status.

    wsl -d Ubuntu

    Will check if WSL Network Adapter is active and if not initialize it. Then it will execute `wsl.exe -d Ubuntu`. Thus allowing to use WSL instances with static ip addressed without manual interaction with network settings, etc.

    .NOTES
    During execution of Install-WslHandler, when a static mode of operation is specified, there will be an alias created: `wsl` for Invoke-WslStatic. When working in Powershell this alias shadows actual windows `wsl` command to enable effortless operation in Static IP Mode. When there is a need to execute actual windows `wsl` command from withing Powershell use `wsl.exe` (i.e. with extension) to execute native Windows command.
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
    $fn = $MyInvocation.MyCommand.Name
    $argsCopy = $args.Clone()

    $DebugPreferenceOriginal = $DebugPreference
    if ('-debug' -in $argsCopy) {
        $DebugPreference = 'Continue'
        $argsCopy = $argsCopy | Where-Object { $_ -notlike '-debug' }
    }

    if ($argsCopy.Count -eq 0 -or (ArgsAreExec $argsCopy)) {
        Write-Debug "${fn}: `$args: $argsCopy"
        Write-Debug "${fn}: Passed arguments require Setting WSL Network Adapter."

        $networkSectionName = (Get-NetworkSectionName)

        $GatewayIpAddress = Get-WslConfigValue -SectionName $networkSectionName -KeyName (Get-GatewayIpAddressKeyName) -DefaultValue $null

        if ($null -ne $GatewayIpAddress) {
            Set-WslNetworkAdapter
        }
    }

    Write-Debug "${fn}: Invoking wsl.exe $argsCopy"
    $DebugPreference = $DebugPreferenceOriginal
    & wsl.exe @argsCopy
}

function Update-WslIpHandlerModule {
    <#
    .SYNOPSIS
    Downloads latest master.zip from this Modules repository at github.com and updates local Module's files

    .DESCRIPTION
    Updates local Module's files to the latest available at Module's repository at github.com.
    If `git` is available uses `git pull origin master`, otherwise Invoke-WebRequest will be used to download master.zip and expand it to Module's directory replacing all files with downloaded ones.

    .EXAMPLE
    An example

    .NOTES
    All file in this Module's folder will be removed before update!
    #>
    [CmdletBinding()]
    param ()
    $script = Join-Path $PSScriptRoot 'Update-WslIpHandlerModule.ps1' -Resolve
    & $script
}

function Uninstall-WslIpHandlerModule {
    [CmdletBinding()]
    param()
    $moduleLocation = Split-Path $MyInvocation.MyCommand.Module.Path
    $prompt = 'Please confirm that the following directory should be irreversible DELETED:'
    if ($PSCmdlet.ShouldContinue($moduleLocation, $prompt)) {
        $moduleName = $MyInvocation.MyCommand.ModuleName
        Remove-Module $moduleName -Force
        if ((Get-Location).Path.Contains($moduleLocation)) {
            Set-Location (Split-Path $moduleLocation)
        }
        Write-Host "Removing $moduleLocation..."
        # Remove-Item -path $moduleLocation -recurse -force
    }
    else {
        Write-Verbose 'Uninstall operation was canceled!'
    }
}

Register-ArgumentCompleter -CommandName Install-WslIpHandler -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Uninstall-WslIpHandler -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Set-WslInstanceStaticIpAddress -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Remove-WslInstanceStaticIpAddress -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter

Register-ArgumentCompleter -CommandName Test-WslInstallation -ParameterName WslInstanceName -ScriptBlock $Function:WslNameCompleter
