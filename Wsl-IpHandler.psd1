#
# Module manifest for module 'Wsl-IpHandler'
#
# Generated on: 2021.08.24
#

@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'Wsl-IpHandler'

    # Version number of this module.
    ModuleVersion     = '0.14.7'

    # Supported PSEditions
    # CompatiblePSEditions = @()

    # ID used to uniquely identify this module
    GUID              = '63f4f045-5cf0-4252-9c79-328dc0e3b6a8'

    # Author of this module
    Author            = 'wikiped'

    # Company or vendor of this module
    CompanyName       = 'Unknown'

    # Copyright statement for this module
    Copyright         = '(c) wikiped@ya.ru. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'Assigns IP addresses to WSL instances and adds those IPs to hosts file.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules   = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess  = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @(
    #     '.\SubModules\CliXml.psm1'
    #     '.\SubModules\Encoders.psm1'
    #     '.\SubModules\GithubPsModulesUpdater.psm1'
    #     '.\SubModules\HNS.psm1'
    #     '.\SubModules\IPC.psm1'
    #     '.\SubModules\IPNetwork.psm1'
    #     '.\SubModules\Show-ToastMessages.psm1'
    # )

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    # FunctionsToExport = '*'
    FunctionsToExport = @(
        'Install-WslIpHandler'
        'Uninstall-WslIpHandler'
        'Set-ProfileContent'
        'Remove-ProfileContent'
        'Set-WslNetworkConfig'
        'Remove-WslNetworkConfig'
        'Set-WslInstanceStaticIpAddress'
        'Remove-WslInstanceStaticIpAddress'
        'Set-WslNetworkAdapter'
        'Remove-WslNetworkAdapter'
        'Set-WslScheduledTask'
        'Remove-WslScheduledTask'
        'Test-WslInstallation'
        'Invoke-WslExe'
        'Update-WslIpHandlerModule'
        'Uninstall-WslIpHandlerModule'
        'Install-WslBashScripts'
        'Update-WslBashScripts'
        'Uninstall-WslBashScripts'
        'Get-WslStatus'
        'Get-WslInstanceStatus'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    # CmdletsToExport   = '*'
    CmdletsToExport   = @()

    # Variables to export from this module
    # VariablesToExport = '*'
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    # AliasesToExport   = '*'
    AliasesToExport   = @('wsl')

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    FileList          = @(
        'functions.sh'
        'install-wsl-iphandler.sh'
        'uninstall-wsl-iphandler.sh'
        'update-wsl-iphandler.sh'
        'wsl-iphandler.sh'
        'README.md'
        'RELEASES.md'
        'LICENSE.txt'
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{
        ScriptNames     = @{
            WinHostsEdit  = 'Scripts\Powershell\WSL-WinHostsEdit.ps1'
            BashInstall   = 'Scripts\Bash\install-wsl-iphandler.sh'
            BashUninstall = 'Scripts\Bash\uninstall-wsl-iphandler.sh'
            BashUpdate    = 'Scripts\Bash\update-wsl-iphandler.sh'
            BashAutorun   = 'Scripts\Bash\wsl-iphandler.sh'
        }

        ScriptLocations = @{
            BashAutorun = '/usr/local/bin'
        }

        WslConfig       = @{
            GlobalSectionName            = 'wsl2'
            NetworkSectionName           = 'network'
            StaticIpAddressesSectionName = 'static_ips'
            IpOffsetSectionName          = 'ip_offsets'
            SwapSizeKeyName              = 'swap'
            SwapFileKeyName              = 'swapFile'
            GatewayIpAddressKeyName      = 'gateway_ip'
            PrefixLengthKeyName          = 'prefix_length'
            DnsServersKeyName            = 'dns_servers'
            WindowsHostNameKeyName       = 'windows_host_name'
            DynamicAdaptersKeyName       = 'dynamic_adapters'
        }

        ScheduledTask   = @{
            Name        = 'Wsl-IpHandlerTask'
            Path        = '\Wsl-IpHandler\'
            Description = 'Task created by Wsl-IpHandler Powershell module to set Hyper-V Network Adapter WSL to predefined IP Address.'
        }

        ProfileContent  = @(
            '# Start of Wsl-IpHandler Section'
            'Import-Module Wsl-IpHandler'
            '# End of Wsl-IpHandler Section'
        )

        PSData          = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('WSL', 'IP', 'IPAddress', 'Network', 'Subnet')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/wikiped/Wsl-IpHandler/blob/master/LICENSE.txt'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/wikiped/Wsl-IpHandler'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'https://github.com/wikiped/Wsl-IpHandler/blob/master/RELEASES.txt'

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()

        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    HelpInfoURI       = 'https://github.com/wikiped/Wsl-IpHandler'

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''

}
