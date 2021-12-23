$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest

#region Debug Functions
if (!(Test-Path function:\_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

if (-not (Test-Path 'function:Get-ArgsArray')) {
    . (Join-Path $PSScriptRoot 'FunctionsParametersHelpers.ps1' -Resolve) | Out-Null
}

function IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { $true }
    else { $false }
}

function GetPowerShellExecutablePath {
    $psName = If ($PSVersionTable.PSVersion.Major -le 5) { 'powershell' } Else { 'pwsh' }
    $psexe = Join-Path $PSHOME "${psName}.exe"
    if (!(Test-Path -Path $psexe -PathType Leaf)) {
        Throw "PowerShell Executable Cannot be located: $psexe"
    }
    $psexe
}

function Test-ArgumentsNeedEncoding {
    param (
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()]
        [string[]]$Arguments
    )
    if ($Arguments) {
        ($Arguments -replace '-\w+:' -match "^[^'`"]\S+\s+|\s+\S+[^'`"]$|^@\(").Count -ne 0
    }
    else { $false }
}

function Invoke-ScriptElevated {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include '*.ps1' })]
        $ScriptPath,
        [Parameter(Position = 1)]
        [string[]]$ScriptArguments = @(),
        [Parameter()]
        [object]$ScriptParameters = @{},
        [Parameter()]
        [string]$WindowStyle = 'Hidden',
        [Parameter()]
        [switch]$Wait,
        [Parameter()]
        [switch]$PassThruResult,
        [Parameter()]
        [switch]$Exit,
        [Parameter()]
        [switch]$Encode
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    Write-Debug "$(_@) `$ScriptArguments: $ScriptArguments"
    Write-Debug "$(_@) `$ScriptParameters: $(& {$args} @ScriptParameters)"

    $scriptArgsArray = Get-ArgsArray -Arguments @($ScriptArguments) -Parameters $ScriptParameters
    Write-Debug "$(_@) `$scriptArgsArray: $scriptArgsArray"

    if (-not $Encode -and (Test-ArgumentsNeedEncoding $scriptArgsArray)) {
        $Encode = $true
        Write-Debug "$(_@) Encode after Test-ArgumentsNeedEncoding: $Encode"
    }

    $psexe = GetPowerShellExecutablePath
    Write-Debug "$(_@) PowerShellExecutablePath: `"$psexe`""

    $debugMode = $DebugPreference -ne 0
    # $verboseMode = $VerbosePreference -ne 0
    Write-Debug "$(_@) `$debugMode=$debugMode"

    $startProcessParams = [ordered]@{ Verb = 'RunAs' }

    if ($Wait) { $startProcessParams.Wait = $true }

    $psExeArgs = @()

    $psExeArgs += '-NoLogo', '-NoProfile'

    # if ($verboseMode -and (-not ($Encode -or $PassThruResult)) -and '-Verbose' -notin $scriptArgsArray) {
    #     $scriptArgsArray += '-Verbose'
    # }
    if ($debugMode) {
        $psExeArgs += '-NoExit'
        # if (-not ($Encode -or $PassThruResult) -and '-Debug' -notin $scriptArgsArray) {
        #     $scriptArgsArray += '-Debug'
        # }
    }
    else {
        $startProcessParams.WindowStyle = $WindowStyle
        $psExeArgs += '-NonInteractive'
        $psExeArgs += "-WindowStyle $WindowStyle"
    }

    if ($Encode -or $PassThruResult) {
        $commandToEncode = @('&', "`"$ScriptPath`"")
        $commandToEncode += $scriptArgsArray -join ' '
        Write-Debug "$(_@) `Command to Encode: '$commandToEncode'"
        Invoke-CommandElevated $commandToEncode -Encode -Wait:$Wait -PassThru:$PassThruResult -IgnoreCommonParameters
    }
    else {
        $psExeArgs += "-File `"$ScriptPath`" $($scriptArgsArray -join ' ')"
        $startProcessParams.ArgumentList = $psExeArgs -join ' '
        Write-Debug "$(_@) Start-Process $psexe $(& {$args} @startProcessParams)"
        Start-Process $psexe @startProcessParams
    }
}

function Invoke-CommandElevated {
    param(
        [Parameter()]
        [string[]]$Command,
        [switch]$Encode,
        [switch]$Wait,
        [switch]$PassThruResult,
        [switch]$IgnoreCommonParameters
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"
    Write-Debug "$(_@) Command: $Command"
    if (-not $Encode -and (Test-ArgumentsNeedEncoding $Command)) {
        $Encode = $true
        Write-Debug "$(_@) Encode after Test-ArgumentsNeedEncoding: $Encode"
    }

    $psexe = (GetPowerShellExecutablePath)
    Write-Debug "$(_@) PowerShellExecutablePath: '$psexe'"

    $psExeArgsList = '-NoLogo', '-NoProfile', '-NonInteractive'
    $startProcessParams = @{ Verb = 'RunAs' }

    if ($Wait) { $startProcessParams.Wait = $true }

    if ($DebugPreference -eq 0) {
        $startProcessParams.WindowStyle = 'Hidden'
        $psExeArgsList += @('-WindowStyle Hidden')
    }
    else {
        $psExeArgsList += '-NoExit'
    }
    Write-Debug "$(_@) `$psExeArgsList after DebugPreference adjustments: $psExeArgsList"

    $commonParameters = @{}
    if ($VerbosePreference -eq 'Continue') { $commonParameters.Verbose = $true }
    if ($DebugPreference -eq 'Continue') { $commonParameters.Debug = $true }
    Write-Debug "$(_@) `$commonParameters: $(& {$args} @commonParameters)"

    if (-not $IgnoreCommonParameters) {
        $commonParametersAsArgs = ConvertParametersToArgsArray $commonParameters
        Write-Debug "$(_@) `$commonParametersAsArgs: $commonParametersAsArgs"
        $Command += "$commonParametersAsArgs"
        Write-Debug "$(_@) `$Command + `$commonParametersAsArgs: $Command"
    }

    if ($PassThruResult) {
        $Encode = $true
        $pipeName = 'wsl-iphandler'
        $encoding = 'UTF-8'
        $bufferSize = 1024 * 20
        $pipeClientCommandParams = @{
            Command    = $Command -join ' '
            PipeName   = $pipeName
            Encoding   = $encoding
            BufferSize = $bufferSize
        }
        $ipcModule = Join-Path $PSScriptRoot '..\..\SubModules\IPC.psm1'
        Import-Module $ipcModule -Verbose:$false -Debug:$false
        $Command = Get-CommandStringToSendOutputToPipe @pipeClientCommandParams @commonParameters
        Write-Debug "$(_@) `$Command to send output to pipe: $Command"
    }

    if ($Encode) {
        if (-not (Get-Module Encoders -ErrorAction 'Continue')) {
            $encodeModule = Join-Path $PSScriptRoot '..\..\SubModules\Encoders.psm1'
            Import-Module $encodeModule -Verbose:$false -Debug:$false
        }
        $encodedCommand = Get-EncodedCommand ($Command -join ' ')
        if ($encodedCommand.Length -gt 8100) {
            Write-Warning 'Length of Encoded command is over 8100 and may be too long to run via -EncodedCommand of Powershell'
        }
        $psExeArgsList += @('-EncodedCommand', $encodedCommand)
    }
    else {
        $psExeArgsList += @('-Command', $Command)
    }

    $startProcessParams.ArgumentList = $psExeArgsList -join ' '
    Write-Debug "$(_@) `$startProcessParams: $($startProcessParams | Out-String)"
    Write-Debug "$(_@) Start-Process $psexe -ArgumentList $psExeArgsList"

    try {
        Start-Process $psexe @startProcessParams
    }
    catch {
        Write-Debug "$(_@) Exception.Message: $($_.Exception.Message)"
        Throw
    }
    if ($PassThruResult) {
        $receiveParams = @{
            PipeName   = $pipeName
            BufferSize = $bufferSize
            Encoding   = $encoding
        }
        Write-Debug "$(_@) Invoking Receive-ObjectFromPipe with params: $($receiveParams | Out-String)"
        $result = Receive-ObjectFromPipe @receiveParams
        if ($result -is [Exception]) {
            Throw $result
        }
        return $result
    }

}
