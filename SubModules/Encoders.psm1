$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-EncodedCommand {
    param ([string]$Command)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    [Convert]::ToBase64String($bytes)
}

function Get-DecodedCommand {
    param ([string]$EncodedCommand)
    $bytes = [Convert]::FromBase64String($EncodedCommand)
    [System.Text.Encoding]::Unicode.GetString($bytes)
}

Export-ModuleMember -Function Get-EncodedCommand
Export-ModuleMember -Function Get-DecodedCommand
