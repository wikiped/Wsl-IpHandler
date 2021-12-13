[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Alias('Name')]
    [string]$TaskName,

    [Parameter()]
    [Alias('Path')]
    [string]$TaskPath,

    [Parameter()]
    [Alias('Description')]
    [string]$TaskDescription,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$UserName = $env:USERNAME,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunAsUserName = $env:USERNAME,

    [Parameter()]
    [ValidateScript({ $null -ne (ConvertTo-SecureString $_) })]
    [string]$EncryptedSecureString,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Command,

    [Parameter()]
    [string]$Argument,

    [Parameter()]
    [switch]$AnyUserLogOn,

    [Parameter()]
    [switch]$AsLocalSystem
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$elevationScript = Join-Path $PSScriptRoot 'FunctionsPSElevation.ps1' -Resolve
. $elevationScript

if (-not (IsElevated)) {
    Write-Debug "$(_@) Invoke-ScriptElevated $(& {$args} @PSBoundParameters)"
    Invoke-ScriptElevated $MyInvocation.MyCommand.Path -ScriptParameters $PSBoundParameters
}

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

$psExe = GetPowerShellExecutablePath

Write-Debug "$(_@) Task Name: $taskName"
Write-Debug "$(_@) Task Path: $taskPath"
Write-Debug "$(_@) Task Description: $taskDescription"
Write-Debug "$(_@) Powershell Executable Path: $psExe"

$FullUserName = if ($UserName.Contains('\')) { $UserName } else { "$env:COMPUTERNAME\$UserName" }
Write-Debug "$(_@) UserName: $UserName"
Write-Debug "$(_@) FullUserName: $FullUserName"

$actionParams = @{
    Execute  = "`"$($Command -replace '"', '')`""
    Argument = $Argument
}

Write-Debug "$(_@) Command: $Command"
Write-Debug "$(_@) Argument: $Argument"

$action = New-ScheduledTaskAction @actionParams

$triggerParams = @{
    AtLogOn = $true
}
if (-not $AnyUserLogOn) {
    $triggerParams.User = $FullUserName
}
$trigger = New-ScheduledTaskTrigger @triggerParams

$settingsParams = @{
    DisallowHardTerminate   = $false
    AllowStartIfOnBatteries = $true
    DontStopOnIdleEnd       = $true
    ExecutionTimeLimit      = (New-TimeSpan -Minutes 5)
    Compatibility           = 'Win8'
}
$settings = New-ScheduledTaskSettingsSet @settingsParams

$registrationParams = @{
    TaskName    = $taskName
    TaskPath    = $taskPath
    Description = $taskDescription
    Action      = $action
    Settings    = $settings
    Trigger     = $trigger
    RunLevel    = 'Highest'
    Force       = $true
}

if ($AsLocalSystem) { $registrationParams.User = 'NT AUTHORITY\SYSTEM' }

if ($EncryptedSecureString) {
    $password = ConvertTo-SecureString $EncryptedSecureString
    $credential = New-Object System.Management.Automation.PSCredential ($FullUserName, $password)
    $registrationParams.User = $credential.UserName
    $registrationParams.Password = $credential.GetNetworkCredential().Password
}

Register-ScheduledTask @registrationParams | Out-Null
