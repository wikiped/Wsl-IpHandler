# WSL IP Handler

<details>
<summary>
<strong>CONTENT</strong>
<p></p>
</summary>

[Overview](#overview)

[How to get this module?](#how-to-get-this-module)

[Where the module is installed?](#where-the-module-is-installed)

<details>
<summary>
<a href="#how-does-it-work">How does it work?</a>
<p></p>
</summary>

&emsp;&emsp;[WSL2 Configuration Requirements](#wsl2-configuration-requirements)

&emsp;&emsp;[How On-Demand mode works?](#how-on-demand-mode-works)

&emsp;&emsp;[How On-Logon mode works?](#how-on-logon-mode-works)

&emsp;&emsp;[What happens during WSL Instance startup?](#what-happens-during-wsl-instance-startup)

&emsp;&emsp;[What happens when WSL Hyper-V Network Adapter is being setup?](#what-happens-when-wsl-hyper-v-network-adapter-is-being-setup)

&emsp;&emsp;[Powershell Profile Modification](#powershell-profile-modification)

</details>

[How to use this module?](#how-to-use-this-module)

[How to deactivate this module?](#how-to-deactivate-this-module)

[How to update this module?](#how-to-update-this-module)

[How to completely remove this module?](#how-to-completely-remove-this-module)

[How to enable Unicode UTF-8 support on Windows?](#how-to-enable-unicode-utf-8-support-on-windows)

[Getting help](#getting-help)

[Credits](#credits)

[What's new\?](./CHANGELOG.md)

</details>

---

## Overview

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

---

## How to get this module

### Prerequisites

1. PowerShell 7.1+.

    [How to install Powershell Core.](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.1)

1. [WSL 2](https://github.com/microsoft/WSL) (This module has not been tested with WSL 1)

1. Administrative access on the windows machine, where the module will be used.

1. Ubuntu or Fedora family os on WSL instance.

1. Unicode UTF-8 support enabled in Windows Settings.

To download and copy the module to Modules folder of Powershell profile for Current User run the following commands from Powershell prompt:

### Universal web installer

Command below will download the installation script and will prompt you to choose whether to use `git.exe` (if `git` can be found in `PATH`) or use zippied repository:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/wikiped/Wsl-IpHandler/master/Install-WslIpHandlerFromGithub.ps1 | Select -ExpandProperty Content | Invoke-Expression
```

Otherwise you can use any of the below two methods to install the module.

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
Invoke-WebRequest -Uri https://codeload.github.com/wikiped/Wsl-IpHandler/zip/refs/heads/master -OutFile 'Wsl-IpHandler.zip'
Expand-Archive -Path 'Wsl-IpHandler.zip' -DestinationPath '.'
Remove-Item -Path 'Wsl-IpHandler.zip'
Rename-Item -Path 'Wsl-IpHandler-master' -NewName 'Wsl-IpHandler'
```

---

## Where the module is installed?

After executing above commands in [How to get this module](#how-to-get-this-module) the module is installed in a Powershell profile directory for the current user.

Run `Split-Path $Profile` to see location of this profile directory.

When `Import-Module SomeModule` command is executed, Powershell looks for `SomeModule` in this directory (among others).

> __It is important__ to be aware of the fact that WSL2 does not yet support windows network shares within linux, so if the module is installed on a network share it will NOT be working correctly. To mitigate this issue the module checks where it is installed and warns the user of the problem.

---

## How does it work?

When WSL IP Handler is activated (with `Install-WslIpHandler` command) it stores required network configuration in `.wslconfig` file. This configuration is then used by Powershell scripts on Windows host and Bash scripts on WSL Instance where it has been activated to ensure IP Addresses determinism.

There are two ways how IP Address persistance of WSL Hyper-V Network Adapter can be achieved with this module:

- On-Demand: The adapter is created (if it is not present) or modified (if was created beforehand by Windows) to match the required network configuration when the user runs `wsl` command through Powershell session.

- On-Logon: The adapter is created by a Scheduled Task that runs on user logon. This way the user does not have to use Powershell (interactively) to ensure WSL adapter's network configuration matches required.

The following sections describe which files are modified (outside of module's directory) on Windows host and WSL instance(s).

---

### WSL2 Configuration Requirements

WSL uses two configuration files:

- `~/.wslconfig` on Windows

- `/etc/wsl.conf` on Linux

Wsl-IpHandler module requires default configuration of some of the settings in linux `/etc/wsl.conf` to work correctly (settings below do not have to be present in the file!):

  ```ini
  [interop]
  enabled = true
  appendWindowsPath = true
  [automount]
  enabled = true
  [network]
  generateResolvConf = true
  ```

On Windows side in `/.wslconfig` there is one setting which has side effect on WSL2 networking and which affects this module operation:

  ```ini
  [wsl2]
  swap = ...
  ```

The problem appears when swap setting is enabled and the swap file in use is using NTFS compression.
This is a known WSL2 issue ([#4731](https://github.com/microsoft/WSL/issues/4731), [#5286](https://github.com/microsoft/WSL/issues/5286), [#5336](https://github.com/microsoft/WSL/issues/5336), [#5437](https://github.com/microsoft/WSL/issues/5437)) causing linux `eth0` interface to be in a `DOWN` state when WSL instance starts. This makes the WSL network unavailable and hence the module non-operational.

The solution to this problem is to either disable swap or disable NTFS compression on a swap file. This module by default opts for disabling swap in `.wslconfig`:

  ```ini
  [wsl2]
  swap = 0
  ```

For these reasons the module validates WSL configuration both on windows side and linux side to ensure correct behavior.

---

### Files created or modified on Windows Host (outside of modules directory)

- File modified during module activation: `~\.wslconfig`
- File modified (optionally) during module activation: `$Profile.CurrentUserAllHosts` (Powershell Profile file)
- File modified (if necessary) during startup of WSL Instance: `%WINDOWS%\System32\Drivers\etc\hosts`

---

### Files created or modified on WSL Instance system

- New file created during module activation: `/usr/local/bin/wsl-iphandler.sh`
- New file created during module activation: `/etc/profile.d/run-wsl-iphandler.sh`
- New file created during module activation: `/etc/sudoers.d/wsl-iphandler`
- File modified during module activation: `/etc/wsl.conf`
- File modified (if necessary) during startup of WSL Instance: `/etc/hosts`

---

### Files modified during [Module Activation](#module-activation)

- Bash scripts are copied to the specified WSL Instance and `wsl.conf` file is modified to save Windows host name.
- Network configuration parameters are saved to `.wslconfig` on Windows host:
  - In [Static Mode](#how-to-use-this-module) if WSL Instance IP address is not specified - the first available IP address will be selected automatically;
  - In [Dynamic Mode](#how-to-use-this-module) IP address offset (1-254) will be selected automatically based on those already used (if any) or 1;
- Powershell profile file is modified (if not opted out) to ensure on demand availability of WSL Hyper-V Network Adapter with required configuration.
- New Scheduled Task created (optionally) to ensure WSL Hyper-V Network Adapter is configured at logon.

---

### How On-Demand mode works?

When `wsl` [alias](#powershell-profile-modification) is executed from Powershell prompt:

- All arguments of the call are checked for presence of "informational" parameters (i.e. those parameters that do not require launch (initialization) of WSL Instance).
  - If present:
    - `wsl.exe` is executed with all arguments passed 'as is'.
  - Otherwise:
    - ~/.wslconfig is checked for Gateway IP Address:
      - If found - Static Mode detected:
        - If WSL Hyper-V Adapter is present - it is checked to have network properties matching those saved during activation. If there is a mismatch - adapter is removed and new one created.
        - If adapter is not present - it is created.
    - `wsl.exe` is executed with all arguments passed 'as is'.
  - Before starting `wsl.exe` and after WSL Network Adapter had to be created the module will poll for `vEthernet (WSL)` Network Connection availability every 3 seconds and when network connection becomes available then actually invoke `wsl.exe`. There is a timeout of 30 seconds to wait for the connection to become available.
  - If `vEthernet (WSL)` Network Connection is not available after specified Timeout (30 seconds by default) Exception will be thrown.
  - Timeout can be changed by setting `-Timeout` parameter: `wsl -Timeout 60`.

> Note that `wsl` command (not the same as `wsl.exe`) in this section refers to Powershell Alias that is created by this module and which is available only when this module is imported into current Powershell session, either manually or automatically through [modified Powershell profile](#powershell-profile-modification).

---

### How On-Logon mode works?

When `Install-WslIpHandler` is executed with parameter `-UseScheduledTaskOnUserLogOn` the module creates a new Scheduled Task named `Wsl-IpHandlerTask` under `Wsl-IpHandler` folder. The task has a trigger to run at user logon.

If parameter `-AnyUserLogOn` was specified to `Install-WslIpHandler` (along with `-UseScheduledTaskOnUserLogOn`) then the task will run at logon of ANY user. Otherwise the task will run only at logon of specific user - the one who executed `Install-WslIpHandler` command.

Since Scheduled Task runs the script in non-interactive mode in a hidden terminal window there will be no usual messages from the script. To be informed of the success/failures during execution of  Scheduled Task there are Toast Notifications which are enabled by default when `Install-WslIpHandler` is executed with parameter `-UseScheduledTaskOnUserLogOn`. To disable toast notifications run `Set-WslScheduledTask` without `-ShowToast` parameter. See `Get-Help Set-WslScheduledTask` for more information.

> Note that it takes some time for Windows to execute its startup process (including logon tasks among other things). So it will take some time before WSL Hyper-V Network Adapter will become available.

---

### What happens during WSL Instance startup?

IP Address handling at WSL instance's side is done with user's profile file modification. Therefore it will not work when WSL instance has been launched after `wsl.exe --shutdown` with a command like this: `wsl ping windows.host` (which is an example of non-interactive session). The reason for this is that Bash does not execute user's profile script in non-interactive sessions.

In all other cases when `wsl` is executed to open a terminal (i.e. interactive session) profile script will run:

- Bash script `wsl-iphandler.sh` will be executed to:
  - Add WSL Instance IP address to eth0 interface. In Dynamic Mode IP address is obtained first from IP offset and Windows Host gateway IP address.
  - Add Windows host gateway IP address to `/etc/hosts` if not already added.
  - Run Powershell script on Windows host to add WSL Instance IP address with its name to Windows `hosts` if not already added.

> A workaround to ensure execution of profile script in non-interactive Bash session is to run command like this (from Powershell):

```powershell
wsl.exe env BASH_ENV=/etc/profile bash -c `"ping windows.host`"
```

---

### What happens when WSL Hyper-V Network Adapter is being setup?

Regardless of whether the module operates in On-Demand or On-Logon mode there a several steps taken to ensure the adapter is properly configured:

1. Check if the adapter exists and is already configured as required. If yes - nothing is done.

1. If the adapter does not exist yet or is mis-configured - it is removed (`wsl --shutdown` is executed beforehand).

1. Check if there are any other network connections having IP network configuration that overlaps (conflicts) with the one specified for WSL adater (through parameters or from `.wslconfig` file).

1. If there are conflicts and overlapping network is from one of Hyper-V adapters (`Ethernet` or `Default Switch`) - conflicting adapter will be recreated to take IP network subnet that does not conflict with WSL Adapter.

1. Any other conflicting network will cause the module to throw an error and it is up to the user to either choose a different IP Subnet for WSL adapter of reconfigure IP settings of conflicting network connection.

1. When no conflicts are found (or they have been resolved) WSL adapter is created.

---

### Powershell Profile Modification

By default, if Static mode of operation has been specified, activation script will modify Powershell profile file (by default $Profile.CurrentUserAllHosts). The only thing that is being added is `wsl` command alias. Actual command that will be executed is `Invoke-WslExe`. If modification of the profile is not desirable there is a parameter `-DontModifyPsProfile` to `Install-WslIpHandler` command to disable this feature.

To modify / restore profile manually at any time there is `Set-ProfileContent` and `Remove-ProfileContent` commands to add or remove modifications.

Created alias works ONLY from within Powershell sessions with user profile loading enabled (which is the default behavior).

See [Execution of command alias](#what-happens-during-wsl-instance-startup) for details on what happens when it is executed.

  > Profile modification takes effect after Powershell session restarts!

---

## How to use this module?

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

---

### Module Activation

1. Import Module.

    ```powershell
    Import-Module Wsl-IpHandler
    ```

   > All commands that follow below require that the module has been imported with above command.

1. Activate Module.

    - Activate in Dynamic Mode:

      ```powershell
      Install-WslIpHandler Ubuntu
      ```

    - Activate in Static Mode:

      To get WSL Instance IP address assigned automatically:

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1
      ```

      To assign static IP address to WSL Instance manually:

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.2
      ```

    - Activate in Static Mode without modifying Powershell profile

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.2 -DontModifyPsProfile
      ```

    - Activate in Static Mode without modifying Powershell profile and enabling WSL adapter setup during logon

      ```powershell
      Install-WslIpHandler -WslInstanceName Ubuntu -GatewayIpAddress 172.16.0.1 -WslInstanceIpAddress 172.16.0.2 -UseScheduledTaskOnUserLogOn -DontModifyPsProfile
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

1. Do I have to use Powershell to benefit from this module?

If Powershell is not part of day-to-day use it is still possible to benefit from this module's features.

Powershell is need to 1) install (i.e. download) and 2) activate the module for all WSL instances where IP address control is required.

For this to work the module has to activated with two switch parameters to `Install-WslIpHandler`:

```powershell
Install-WslIpHandler <...other parameters...> -DontModifyPsProfile -UseScheduledTaskOnUserLogOn
```

This will setup WSL Hyper-V Network Adapter configuration during user logon, without any need to use Powershell to start any WSL instance.

---

## How to deactivate this module?

From Powershell prompt execute:

```powershell
Uninstall-WslIpHandler -WslInstanceName Ubuntu
```

If WSL Instance being removed had Static IP address and it is the only one remaining all network configuration settings (Windows Host Name and Gataway IP Address) will also be removed along with Scheduled Task and Powershell profile modifications.

Even after Wsl-IpHandler was deactivated on all WSL instances WSL Hyper-V Network Adapter will remain active until next reboot or manual removal with `Remove-WslNetworkAdapter` command.

---

## How to update this module

To update this module to the latest version in github repository run in Powershell prompt:

```powershell
Update-WslIpHandlerModule
```

---

## How to completely remove this module

> Before completely removing the module it is recommended to make sure the module has been [deactivated](#how-to-deactivate-this-module) on all WSL instances.

To remove the module - delete the module's folder. It's location can be checked with:

```powershell
(Import-Module Wsl-IpHandler -PassThru | Get-Module).ModuleBase
```

Or execute from Powershell prompt:

```powershell
Import-Module Wsl-IpHandler
Uninstall-WslIpHandlerModule
```

---

## How to enable Unicode UTF-8 support on Windows

Run / Execute command:

```powershell
control international
```

Then in the opened window select tab: <kbd>Administrative</kbd> -> <kbd>Change system locale...</kbd>.

Select option `Beta: Use Unicode UTF-8 for worldwide language support` in the opened window.

---

## Getting Help

To see list of all available commands from this module, execute in Powershell::

```powershell
Get-Command -Module Wsl-IpHandler
```

To get help on any of the commands, execute `Get-Help <Command-Name>`, i.e.:

```powershell
Get-Help Install-WslIpHandler
```

To get help on a particular parameter of a command add `-Parameter <ParameterName>`, i.e.:

```powershell
Get-Help Install-WslIpHandler -Parameter UseScheduledTaskOnUserLogOn
```

---

## Credits

This module is using the code (sometimes partially or with modifications) from the following projects (in no particular order):

[Create a known IP address for WSL2 VM](https://github.com/microsoft/WSL/discussions/7395) by Biswa96

[wsl2-custom-network](https://github.com/skorhone/wsl2-custom-network) by Sami Korhonen

[wsl2ip2hosts](https://github.com/hndcrftd/wsl2ip2hosts) by Jakob Wildrain

[PsIni](https://github.com/lipkau/PsIni) by Oliver Lipkau

[IP-Calc](https://sawfriendship.wordpress.com/) by saw-friendship
