param(
    [Parameter(Mandatory)][string]$ModulePathOrName,
    [Parameter(Mandatory)][version]$VersionBeforeUpdate,
    [Parameter(Mandatory)][version]$VersionAfterUpdate
)

Set-StrictMode -Version Latest

$wslConfigScript = Join-Path $PSScriptRoot '.\FunctionsWslConfig.ps1' -Resolve
. $wslConfigScript

function Invoke-MigrateWslConfig {
    [CmdletBinding()]param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$WslInstanceName
    )
    $inputArray = @($input)
    if ($inputArray.Count) { $WslInstanceName = $inputArray }
    if (!(Test-Path variable:WslInstanceName)) { $WslInstanceName = @() }

    Write-Verbose 'Migrating Windows config file...'
    Read-WslConfig -ConfigType Wsl -Force | Out-Null
    Read-WslConfig -ConfigType WslIpHandler -Force | Out-Null

    Write-Verbose 'Migrating [network] settings in Windows config file...'
    $gatewayIpAddress = Get-WslConfigGatewayIpAddress -ConfigType Wsl
    $PrefixLength = Get-WslConfigPrefixLength -ConfigType Wsl
    $dnsServerList = Get-WslConfigDnsServers -ConfigType Wsl
    $dynamicAdapters = Get-WslConfigDynamicAdapters -ConfigType Wsl
    $windowsHostName = Get-WslConfigWindowsHostName -ConfigType Wsl

    $modifiedWslConf = $false
    $modifiedModConf = $false
    $wslParams = @{ Modified = [ref]$modifiedWslConf; ConfigType = 'Wsl' }
    $modParams = @{ Modified = [ref]$modifiedModConf; ConfigType = 'WslIpHandler' }

    if ($gatewayIpAddress) {
        Set-WslNetworkConfig -GatewayIpAddress $gatewayIpAddress -PrefixLength $PrefixLength -DNSServerList $dnsServerList -DynamicAdapters $dynamicAdapters -WindowsHostName $windowsHostName -Modified ([ref]$modifiedModConf)
    }

    if ($WslInstanceName) {
        Write-Verbose 'Migrating IP address settings in Windows config file...'
        $WslInstanceName | ForEach-Object {
            #region Migrate WSL Instance Static IP from config file
            $wslIpAddress = Get-WslConfigStaticIpAddress -WslInstanceName $_ -ConfigType Wsl
            if ($wslIpAddress) {
                Write-Verbose "Migrating static IP address $wslIpAddress for $_ ..."
                Set-WslInstanceStaticIpAddress -WslInstanceName $_ -WslInstanceIpAddress $wslIpAddress -Modified ([ref]$modifiedModConf)
                Remove-WslConfigStaticIpAddress -WslInstanceName $_ @wslParams
            }
            #endregion Migrate WSL Instance Static IP from config file

            #region Migrate WSL Instance IP Offset from config file
            $wslIpOffset = Get-WslConfigIpOffset -WslInstanceName $_ -ConfigType Wsl
            if ($wslIpOffset) {
                Write-Verbose "Migrating IP address offset $wslIpOffset for $_ ..."
                Set-WslConfigIpOffset -WslInstanceName $_ -IpOffset $wslIpOffset @modParams
                Remove-WslConfigIpOffset -WslInstanceName $_ @wslParams
            }
            #endregion Migrate WSL Instance IP Offset from config file
        }
    }

    Remove-WslConfigWindowsHostName @wslParams
    Remove-WslConfigGatewayIpAddress @wslParams
    Remove-WslConfigPrefixLength @wslParams
    Remove-WslConfigDnsServers @wslParams
    Remove-WslConfigDynamicAdapters @wslParams

    if ($modifiedWslConf) { Write-WslConfig -ConfigType Wsl -Backup }
    if ($modifiedModConf) { Write-WslConfig -ConfigType WslIpHandler -Backup }
    Write-Verbose 'Finished migrating Windows config file'
}

function Invoke-MigrateWslInstanceConfig {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$WslInstanceName
    )
    $inputArray = @($input)
    if ($inputArray.Count) { $WslInstanceName = $inputArray }
    if (!(Test-Path variable:WslInstanceName)) { $WslInstanceName = @() }

    if (-not $WslInstanceName) { return }

    Write-Verbose "Migrating config file at WSL Instance: $WslInstanceName ..."

    $iniInScript = Join-Path $PSScriptRoot '.\Ini-In.ps1' -Resolve
    $iniOutScript = Join-Path $PSScriptRoot '.\Ini-Out.ps1' -Resolve
    $wslHelpersScript = Join-Path $PSScriptRoot '.\FunctionsArgumentCompleters.ps1' -Resolve

    . $iniInScript
    . $iniOutScript
    . $wslHelpersScript

    $wslConf = '/etc/wsl.conf'
    $modConf = '/etc/wsl-iphandler.conf'

    $WslInstanceName | ForEach-Object {
        try {
            $wslInstanceWasRunning = Test-WslInstanceIsRunning $_
            $modConfExists = (wsl.exe -d $_ test -f $modConf && 1) -eq 1
            Write-Debug "Module Config '$modConf' exists: $modConfExists"
            if (-not $modConfExists) {
                Write-Debug "$wslConf before:`n$(wsl.exe -d $_ cat $wslConf)"
                foreach ($option in @('static_ip', 'ip_offset', 'windows_host', 'wsl_host')) {
                    Write-Debug "Migrating option: $option"
                    $line = wsl.exe -d $_ grep -P "^${option}\\s*=.*$" $wslConf
                    if ($line) {
                        Write-Debug "Line with ${option}: '$line'"
                        wsl.exe -d $_ echo $line `>> $modConf
                        wsl.exe -d $_ sed -i "/${line}/d" $wslConf
                    }
                }
                Write-Debug "$wslConf after:`n$(wsl.exe -d $_ cat $wslConf)"
                if ((wsl.exe -d $_ test -f $modConf && 1) -eq 1) {
                    Write-Debug "$modConf after:`n$(wsl.exe -d $_ cat $modConf)"
                }
                else {
                    Write-Error "Error migrating config file: '$modConf' - file was not created."
                }
            }
        }
        finally { if (-not $wslInstanceWasRunning) { wsl.exe -t $_ } }
    }
    Write-Verbose "Finished migrating config file at WSL Instance: $WslInstanceName ..."
}

function Invoke-Main {
    param(
        [Parameter(Mandatory)][string]$ModulePathOrName,
        [Parameter(Mandatory)][version]$VersionBeforeUpdate,
        [Parameter(Mandatory)][version]$VersionAfterUpdate
    )

    [version]$VersionToMigrateMin = '0.20'

    if (
        $VersionBeforeUpdate -lt $VersionToMigrateMin -and
        $VersionAfterUpdate -ge $VersionToMigrateMin
    ) {
        try {
            $module = Import-Module $ModulePathOrName -Force -PassThru -ErrorAction Stop -Verbose:$false
        }
        catch {
            Write-Error $_.Exception.Message -ErrorAction Stop
        }
        if (-not $module) {
            Write-Error "Could not import module: '$ModulePathOrName'" -ErrorAction Stop
        }
        if ($module.Version -ne $VersionAfterUpdate) {
            Write-Error "Current version $($module.Version) does not match expected: $VersionAfterUpdate. Script '$($MyInvocation.MyCommand)' should be probably invoked in a new shell for the module to be imported properly." -ErrorAction Stop
        }
        Write-Verbose "Migrating config files for $($module.Name)..."
        Write-Debug "`$VersionBeforeUpdate: $VersionBeforeUpdate"
        Write-Debug "`$VersionAfterUpdate: $VersionAfterUpdate"

        $instancesToMigrate = Get-WslStatus -WslInstances -PassThru -InformationAction SilentlyContinue |
            Select-Object -ExpandProperty WslInstances |
            Where-Object {
                Get-WslInstanceStatus -WslInstanceName $_ -ModuleScript |
                    Select-Object -ExpandProperty ModuleScript
                }

        Write-Debug "Instances to migrate: $instancesToMigrate"

        Invoke-MigrateWslConfig -WslInstanceName $instancesToMigrate

        Invoke-MigrateWslInstanceConfig -WslInstanceName $instancesToMigrate
    }
    else {
        Write-Debug 'Migration of config files is not required.'
    }
}

Invoke-Main -ModulePathOrName $ModulePathOrName -VersionBeforeUpdate $VersionBeforeUpdate -VersionAfterUpdate $VersionAfterUpdate
