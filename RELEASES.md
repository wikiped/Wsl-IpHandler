# WSL-IpHandler versions release history

[Back to Overview](./README.md)

## `0.10.0`

- Added `Set-WslScheduledTask` and `Remove-WslScheduledTask` commands:

  - `Set-WslScheduledTask` creates a new Scheduled Task: WSL-IpHandlerTask that will be triggered at user LogOn. This task execution is equivalent to running `Set-WslNetworkAdapter` command. It will create WSL Hyper-V Network Adapter when user logs on. Run `Get-Help Set-WslScheduledTask` to see full description and parameters for this command.

  - `Remove-WslScheduledTask` removes WSL-IpHandlerTask Scheduled Task created with `Set-WslScheduledTask` command.

- Added two switch parameters `UseScheduledTaskOnUserLogOn` and `AnyUserLogOn` to `Install-WslIpHandler`:

  - When `UseScheduledTaskOnUserLogOn` is present - `Set-WslScheduledTask` command will be executed to register scheduled task.

  - When `AnyUserLogOn` is present - The scheduled task will be set to run when any user logs on. Otherwise (default behavior) - the task will run only when current user (who executed Install-WslIpHandler command) logs on.

## `0.9.0`

- Added ability to change existing Hyper-V Network Adapters IP Addresses if they overlap with required IP Address for WSL. This happens automatically and does not require any user interaction.

- Added Parameter `DynamicAdapters` to `Install-WslIpHandler` and `Set-WslNetworkAdapter` to control which Hyper-V Network Adapters can be moved (i.e. within IP Networking space) to free required IP Address for WSL Adapter. By default this only applies to `Ethernet` and `Default Switch` adapters.

[Back to Overview](./README.md)
