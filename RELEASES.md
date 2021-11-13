# WSL-IpHandler versions release history

[Back to Overview](./README.md)

## `0.9.0`

- Added ability to change existing Hyper-V Network Adapters IP Addresses if they overlap with required IP Address for WSL. This happens automatically and does not require any user interaction.

- Added Parameter `DynamicAdapters` to `Install-WslIpHandler` and `Set-WslNetworkAdapter` to control which Hyper-V Network Adapters can be moved (i.e. within IP Networking space) to free required IP Address for WSL Adapter. By default this only applies to `Ethernet` and `Default Switch` adapters.

[Back to Overview](./README.md)
