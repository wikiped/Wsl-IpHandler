param(
    [Parameter(Mandatory)][string]$ModulePathOrName,
    [Parameter(Mandatory)][version]$VersionBeforeUpdate,
    [Parameter(Mandatory)][version]$VersionAfterUpdate
)

Set-StrictMode -Version Latest

$wslConfigScript = Join-Path $PSScriptRoot '.\FunctionsWslConfig.ps1' -Resolve
$privateDataScript = Join-Path $PSScriptRoot '.\FunctionsPrivateData.ps1' -Resolve
. $privateDataScript
. $wslConfigScript

Get-PrivateData -Force | Out-Null
Read-WslConfig -ConfigType Wsl -Force | Out-Null
Read-WslConfig -ConfigType WslIpHandler -Force | Out-Null

Write-Debug "WSL Config Before Migration: $(Read-WslConfig -ConfigType Wsl | Out-String)"
Write-Debug "Module Config Before Migration: $(Read-WslConfig -ConfigType WslIpHandler | Out-String)"

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

    Write-Verbose 'Migrating [network] settings in Windows config file...'
    $gatewayIpAddress = Get-WslConfigGatewayIpAddress -ConfigType Wsl -ReadOnly
    Write-Debug "$($MyInvocation.MyCommand.Name): `$gatewayIpAddress: $gatewayIpAddress"
    $prefixLength = Get-WslConfigPrefixLength -ConfigType Wsl -ReadOnly
    Write-Debug "$($MyInvocation.MyCommand.Name): `$prefixLength: $prefixLength"
    $dnsServerList = Get-WslConfigDnsServers -ConfigType Wsl -ReadOnly
    Write-Debug "$($MyInvocation.MyCommand.Name): `$dnsServerList: $dnsServerList"
    $dynamicAdapters = Get-WslConfigDynamicAdapters -ConfigType Wsl -ReadOnly
    Write-Debug "$($MyInvocation.MyCommand.Name): `$dynamicAdapters: $dynamicAdapters"
    $windowsHostName = Get-WslConfigWindowsHostName -ConfigType Wsl -ReadOnly
    Write-Debug "$($MyInvocation.MyCommand.Name): `$windowsHostName: $windowsHostName"

    $modifiedWslConf = $false
    $modifiedModConf = $false
    $wslParams = @{ Modified = [ref]$modifiedWslConf; ConfigType = 'Wsl' }
    $modParams = @{ Modified = [ref]$modifiedModConf; ConfigType = 'WslIpHandler' }

    if ($gatewayIpAddress) {
        Write-Verbose "Migrating Network Configuration..."

        Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigWindowsHostName $windowsHostName $(& { $args } @modParams)"
        Set-WslConfigWindowsHostName $windowsHostName @modParams
        Remove-WslConfigWindowsHostName @wslParams

        Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigGatewayIpAddress $gatewayIpAddress $(& { $args } @modParams)"
        Set-WslConfigGatewayIpAddress $gatewayIpAddress @modParams
        Remove-WslConfigGatewayIpAddress @wslParams

        Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigPrefixLength $prefixLength $(& { $args } @modParams)"
        Set-WslConfigPrefixLength $prefixLength @modParams
        Remove-WslConfigPrefixLength @wslParams

        Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigDnsServers $dnsServerList $(& { $args } @modParams)"
        Set-WslConfigDnsServers $dnsServerList @modParams
        Remove-WslConfigDnsServers @wslParams

        Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigDynamicAdapters $dynamicAdapters $(& { $args } @modParams)"
        Set-WslConfigDynamicAdapters $dynamicAdapters @modParams
        Remove-WslConfigDynamicAdapters @wslParams

        Write-Debug "$($MyInvocation.MyCommand.Name): Module Config after Set-WslNetworkConfig: $(Read-WslConfig -ConfigType WslIpHandler | Out-String)"
    }

    if ($WslInstanceName) {
        Write-Verbose 'Migrating IP address settings in Windows config file...'
        $WslInstanceName | ForEach-Object {
            #region Migrate WSL Instance Static IP from config file
            $wslIpAddress = Get-WslConfigStaticIpAddress -WslInstanceName $_ -ConfigType Wsl
            if ($wslIpAddress -and $gatewayIpAddress) {
                Write-Verbose "Migrating static IP address $wslIpAddress for $_ ..."

                Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigStaticIpAddress -WslInstanceName $_ -WslInstanceIpAddress $wslIpAddress $(& { $args } @modParams)"
                Set-WslConfigStaticIpAddress -WslInstanceName $_ -WslInstanceIpAddress $wslIpAddress @modParams
                Remove-WslConfigStaticIpAddress -WslInstanceName $_ @wslParams

                Write-Debug "$($MyInvocation.MyCommand.Name): Module Config after Set-WslConfigStaticIpAddress: $(Read-WslConfig -ConfigType WslIpHandler | Out-String)"
            }
            #endregion Migrate WSL Instance Static IP from config file

            #region Migrate WSL Instance IP Offset from config file
            $wslIpOffset = Get-WslConfigIpOffset -WslInstanceName $_ -ConfigType Wsl
            if ($wslIpOffset) {
                Write-Verbose "Migrating IP address offset $wslIpOffset for $_ ..."

                Write-Debug "$($MyInvocation.MyCommand.Name): Invoking Set-WslConfigIpOffset -WslInstanceName $_ -IpOffset $wslIpOffset $(& { $args } @modParams)"
                Set-WslConfigIpOffset -WslInstanceName $_ -IpOffset $wslIpOffset @modParams
                Remove-WslConfigIpOffset -WslInstanceName $_ @wslParams

                Write-Debug "$($MyInvocation.MyCommand.Name): Module Config after Set-WslConfigIpOffset $(Read-WslConfig -ConfigType WslIpHandler | Out-String)"
            }
            #endregion Migrate WSL Instance IP Offset from config file
        }
    }

    Remove-WslConfigWindowsHostName @wslParams
    Remove-WslConfigGatewayIpAddress @wslParams
    Remove-WslConfigPrefixLength @wslParams
    Remove-WslConfigDnsServers @wslParams
    Remove-WslConfigDynamicAdapters @wslParams

    Write-Debug "$($MyInvocation.MyCommand.Name): Module Config before Write-WslConfig: $(Read-WslConfig -ConfigType WslIpHandler | Out-String)"

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

    . (Join-Path $PSScriptRoot '.\FunctionsArgumentCompleters.ps1' -Resolve) | Out-Null

    Write-Verbose "Migrating config file at WSL Instance: $WslInstanceName ..."

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
        $module = Import-Module $ModulePathOrName -Force -PassThru -ErrorAction Stop -Verbose:$false -Debug:$false

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
