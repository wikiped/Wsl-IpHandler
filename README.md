# WSL IP Handler

This project is an attempt to address WSL networking issues that can be viewed in details in numerous posts over several long standing issues at [WSL project](https://github.com/microsoft/WSL/issues). Here are a couple of them:

- [WSL2 Set static ip?](https://github.com/microsoft/WSL/issues/4210)

- [WSL IP address & Subnet is never deterministic (Constantly changing)](https://github.com/microsoft/WSL/issues/4467)

Main points of frustration are:

1. WSL SubNet is changing after every Windows system reboot varying within wide range of [Private IPv4 addresses:](https://www.wikiwand.com/en/Private_network) `172.16.0.0/12, 192.168.0.0/16, 10.0.0.0/8`.

1. All running WSL Instances have the same random IP address within WSL SubNet although default SubNet prefix length for some reason is 16 (which is enough for 65538 ip addresses!).

1. There is no documented way to control IP address of WSL network adapter and / or of a specific WSL instance.

WSL IP Handler is a Powershell Module which puts together several of the "fixes" / scripts that have been posted over time in the issues mentioned above and aims to provide easy, percistant and automated control over:

1. IPv4 properties of vEthernet (WSL) network adapter.

1. IP addresses assignments within WSL SubNet to WSL instances.

1. DNS resolution for Windows host and WSL instances within WSL SubNet.

In other words what WSL should have been doing out-of-the-box.

## How to get this module

### Prerequisites

1. PowerShell 7.1+ (recommended).

    [How to install Powershell Core.](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.1)

1. [WSL](https://github.com/microsoft/WSL)

To download and copy the module to Modules folder of Powershell profile for Current User run the following commands from Powershell prompt:

### If `Git` is installed

```powershell
New-Item "$(split-path $Profile)\Modules" -Type Directory -ea SilentlyContinue
cd "$(split-path $Profile)\Modules"
git clone https://github.com/wikiped/Wsl-IpHandler
```

### If `Git` is NOT installed

```powershell
New-Item "$(split-path $Profile)\Modules" -Type Directory -ea SilentlyContinue
cd "$(split-path $Profile)\Modules"
Invoke-WebRequest -Uri https://codeload.github.com/wikiped/WSL-IpHandler/zip/refs/heads/master -OutFile 'Wsl-IpHandler.zip'
Expand-Archive -Path 'Wsl-IpHandler.zip' -DestinationPath '.'
Remove-Item -Path 'Wsl-IpHandler.zip'
Rename-Item -Path 'Wsl-IpHandler-master' -NewName 'Wsl-IpHandler'
```

## Where the module is installed?

After executing above commands in [How to get this module](#how-to-get-this-module) the module is installed in a Powershell profile directory for the current user.

Run `Split-Path $Profile` to see location of this profile directory.

When `Import-Module SomeModule` command is executed, Powershell looks for `SomeModule` in this directory (among others).

## How does it work?

WSL IP Handler operates by keeping user configuration and running powershell scripts on Windows host and bash script on WSL Instance where it has been activated.

### On Windows Host (outside of modules directory)

- File modified during activation: `~\.wslconfig`
- File modified (optionally) during activation: `$Profile.CurrentUserAllHosts` (Powershell Profile file)
- File modified (if necessary) during startup of WSL Instance: `%WINDOWS%\System32\Drivers\etc\hosts`

### On WSL Instance system

- New file created during activation: `/usr/local/bin/wsl-iphandler.sh`
- New file created during activation: `/etc/profile.d/run-wsl-iphandler.sh`
- New file created during activation: `/etc/sudoers.d/wsl-iphandler`
- File modified during activation: `/etc/wsl.conf`
- File modified (if necessary) during startup of WSL Instance: `/etc/hosts`

### During [Module Activation](#module-activation)

- Bash scripts are copied to the specified WSL Instance and `wsl.conf` file is modified to save Windows host name.
- Network configuration parameters are saved to `.wslconfig` on Windows host:
  - In [Static Mode](#how-to-use-this-module) if WSL Instance IP address is not specified - the first available IP address will be selected automatically;
  - In [Dynamic Mode](#how-to-use-this-module) IP address offset (1-254) will be selected automatically based on those already used (if any) or 1.

### Execution of command alias

When `wsl` [alias](#powershell-profile-modification) is executed from Powershell prompt:

- All arguments of the call are checked for presence of "informational" parameters (i.e. those parameters that do not require launch of WSL Instance).
  - If present:
    - `wsl.exe` is executed with all arguments passed 'as is'.
  - Otherwise:
    - Configuration is checked for Gateway IP address:
      - If found - Static Mode detected:
        - If WSL Hyper-V Adapter is present - it is checked to have network properties matching those saved during activation. If there is a mismatch - adapter is removed and new one created.
        - If adapter is not present - it is created.
    - `wsl.exe` is executed with all arguments passed 'as is'.

### During WSL Instance startup process

- Bash script `wsl-iphandler.sh` is executed to:
  - Add WSL Instance IP address to eth0 interface. In Dynamic Mode IP address is obtained first from IP offset and Windows Host gateway IP address.
  - Add Windows host gateway IP address to `/etc/hosts` if not already added.
  - Run Powershell script to add WSL Instance IP address with its name to Windows `hosts` if not already added.

### Powershell Profile Modification

By default, if Static mode of operation has been specified, activation script will modify Powershell profile file (by default $Profile.CurrentUserAllHosts). The only thing that is being added is `wsl` command alias. Actual command that will be executed is `Invoke-WslStatic`. If modification of the profile is not desirable there is a parameter `-DontModifyPsProfile` to `Install-WslIpHandler` command to suppress this behavior.

To modify profile manually at any time there is `Set-ProfileContent` and `Remove-ProfileContent` commands to add or remove modifications.

Created alias work ONLY from within Powershell sessions.

See [Execution of command alias](#execution-of-command-alias) for details on what happens when it is executed.

  > NOTE: Profile modification takes effect after Powershell session restarts!

## How to use this module

### Modes of operation

WSL IP Handler operates in two modes:

- Dynamic
- Static

Mode selection is based on configuration parameters provided when running activation command `Install-WslIpHandler`.

In table below `No` - means `Parameter NOT specified` and `Yes` - means `Parameter has some value specified`):

|🡇 Parameter ⋰ Mode 🡆|Dynamic|Static|Invalid|
|-|:-:|:-:|:-:|
|GatewayIpAddress|No|Yes|No|
|WslInstanceIpAddress|No|Yes \| No|Yes|

Available capabilities depend on the Mode of operation:

|🡇 Feature ⋰ Mode 🡆 |Dynamic|Static|
|-|:-----:|:----:|
|Static WSL Network Adapter IP Address|No|Yes|
|Static WSL Instance IP Address|No|Yes|
|Unique IP Address of WSL Instance|Yes|Yes|
|DNS Records|Yes|Yes|

In Static mode WSL IP Handler creates or replaces (if necessary) WSL Hyper-V Network adapter with properties specified during module activation.

In Dynamic mode WSL IP Handler does not interfere with how Windows manages WSL network properties.

### Module Activation

1. Import Module.

    ```powershell
    Import-Module Wsl-IpHandler
    ```

   > All commands that follow below require that the module has been imported with above command!

1. Activate Module.

   1. Activate in Dynamic Mode:

      ```powershell
      Install-WslIpHandler Ubuntu
      ```

   1. Activate in Static Mode:

      To get WSL Instance IP address assigned automatically:

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1
      ```

      To assign WSL Instance IP address manually:

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.2
      ```

1. Use WSL Instance.

   Execute from Powershell prompt:

   (Feel free to reboot the computer or execute `Remove-WslNetworkAdapter` beforehand to see that the changes are persistent after system reboot)

   ```powershell
   wsl -d Ubuntu
   ```

   From shell prompt within WSL Instanace of Ubuntu:

   ```bash
   > ping -c 1 windows
   PING windows (172.16.0.1) 56(84) bytes of data.
   64 bytes from windows (172.16.0.1): icmp_seq=1 ttl=128 time=0.417 ms

   --- windows ping statistics ---
   1 packets transmitted, 1 received, 0% packet loss, time 0ms
   rtt min/avg/max/mdev = 0.417/0.417/0.417/0.000 ms
   ```

   From Powershell in Windows Host:

   ```powershell
   > ping -n 1 Ubuntu

   Pinging Ubuntu [172.16.0.2] with 32 bytes of data:
   Reply from 172.16.0.2: bytes=32 time<1ms TTL=64

   Ping statistics for 172.16.0.2:
       Packets: Sent = 1, Received = 1, Lost = 0 (0% loss),
   Approximate round trip times in milli-seconds:
       Minimum = 0ms, Maximum = 0ms, Average = 0ms
   ```

## How to deactivate this module

From Powershell prompt execute:

```powershell
Uninstall-WslIpHandler -WslInstanceName Ubuntu
```

If WSL Instance being removed had Static IP address and it is the only one remaining WSL Network Adapter will also be removed along with Powershell profile modifications.

## How to update this module

To update this module to the latest version in github repository run in Powershell prompt:

```powershell
Update-WslIpHandlerModule
```

## How to completely remove this module

> Before doing that make sure you have [deactivated](#how-to-deactivate-this-module) the module on all WSL instances.

Simply delete the module's folder. It's location can be checked with:

```powershell
(Import-Module Wsl-IpHandler -PassThru | Get-Module).ModuleBase
```

Or execute from Powershell prompt outside of module's directory:

```powershell
$ModulePath = (Import-Module Wsl-IpHandler -PassThru | Get-Module).ModuleBase
Remove-Module Wsl-IpHandler
Remove-Item $ModulePath -Recurse -Force
```

## Credits

This module is using the code (sometimes partially or with modifications) from the following projects (in no particular order):

[wsl2ip2hosts](https://github.com/hndcrftd/wsl2ip2hosts) by Jakob Wildrain

[wsl2-custom-network](https://github.com/skorhone/wsl2-custom-network) by Sami Korhonen

[PsIni](https://github.com/lipkau/PsIni) by Oliver Lipkau

[IP-Calc](https://sawfriendship.wordpress.com/) by saw-friendship
