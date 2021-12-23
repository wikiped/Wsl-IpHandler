# Wsl-IpHandler versions release history

[Back to Overview](./README.md)

## `0.12.0`

- Added `Get-WslStatus` and `Get-WslInstanceStatus` commands:

  - `Get-WslInstanceStatus` outputs and displays information about current status of Wsl-IpHandler module activation on specified WSL instance.

    Run `Get-Help Get-WslInstanceStatus` to show full details of information it produces.

  - `Get-WslStatus` displays and optionally outputs information about status if Wsl-IpHandler module installation and it's activation on all WSL instances.

    Run `Get-Help Get-WslStatus` to show full details of information it produces.

- Added validation and warnings for the following:

  - WSL swap is enabled and swap file is compressed:

    This is a known WSL2 issue ([#4731](https://github.com/microsoft/WSL/issues/4731), [#5286](https://github.com/microsoft/WSL/issues/5286), [#5336](https://github.com/microsoft/WSL/issues/5336), [#5437](https://github.com/microsoft/WSL/issues/5437)) causing linux `eth0` interface to be in a `DOWN` state on WSL instance start. This makes the WSL network unavailable and hence the module non-operational.

    When this conditions are identified by the module the user will be prompted to either Fix, Abort or Continue current operation.

    If Fix is chosen (default choice) the module will disable WSL swap by setting `swap = 0` in `.wslconfig` and continue.

    If Continue is chosen the operation will continue, but the user should be prepared to deal with errors that will occur.

  - Wsl-IpHandler module is installed on network share:

    WSL2 does not support yet file operations with windows network shares.
    This makes this module non-operational when it is installed on a network share.

    When this condition identified by the module the user will be prompted to either about and install the module to a local drive or to continue and face the errors that follow.

## `0.11.0`

- Added Toast Notifications feature to the Scheduled Task:

  - To enable use `-ShowToast` parameter in `Set-WslScheduledTask`. When this switch parameter is specified then any exception or verbose message signaling of failure or success of operation will be shown in a Popup Toast Notification message near system tray.

  - To control Toasts duration use `-ToastDuration` parameter, which should be set to number of seconds to show Toast Notification (default is 5 seconds).

## `0.10.0`

- Added `Set-WslScheduledTask` and `Remove-WslScheduledTask` commands:

  - `Set-WslScheduledTask` creates a new Scheduled Task: Wsl-IpHandlerTask that will be triggered at user LogOn. This task execution is equivalent to running `Set-WslNetworkAdapter` command. It will create WSL Hyper-V Network Adapter when user logs on. Run `Get-Help Set-WslScheduledTask` to see full description and parameters for this command.

  - `Remove-WslScheduledTask` removes Wsl-IpHandlerTask Scheduled Task created with `Set-WslScheduledTask` command.

- Added two switch parameters `UseScheduledTaskOnUserLogOn` and `AnyUserLogOn` to `Install-WslIpHandler`:

  - When `UseScheduledTaskOnUserLogOn` is present - `Set-WslScheduledTask` command will be executed to register scheduled task.

  - When `AnyUserLogOn` is present - The scheduled task will be set to run when any user logs on. Otherwise (default behavior) - the task will run only when current user (who executed Install-WslIpHandler command) logs on.

## `0.9.0`

- Added ability to change existing Hyper-V Network Adapters IP Addresses if they overlap with required IP Address for WSL. This happens automatically and does not require any user interaction.

- Added Parameter `DynamicAdapters` to `Install-WslIpHandler` and `Set-WslNetworkAdapter` to control which Hyper-V Network Adapters can be moved (i.e. within IP Networking space) to free required IP Address for WSL Adapter. By default this only applies to `Ethernet` and `Default Switch` adapters.

[Back to Overview](./README.md)
