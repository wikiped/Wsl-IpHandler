param(
    [Parameter(Mandatory)][string]$ModulePathOrName,
    [Parameter(Mandatory)][version]$VersionBeforeUpdate,
    [Parameter(Mandatory)][version]$VersionAfterUpdate
)

$n = Split-Path $PSScriptRoot -Leaf
[version]$VersionToMigrateConfig = '0.20'

if ($VersionBeforeUpdate -lt $VersionToMigrateConfig -and $VersionAfterUpdate -ge $VersionToMigrateConfig) {
    $script = Join-Path (Split-path $PSScriptRoot) '.\Scripts\Powershell\MigrateConfigFiles.ps1' -Resolve
    Write-Debug "${n}: Invoking '$script'..."
    & $script @PSBoundParameters
}
