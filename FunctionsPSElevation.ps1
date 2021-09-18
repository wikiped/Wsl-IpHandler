function IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { $true }
    else { $false }
}

function EncodeCommand {
    param ($Command)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    [Convert]::ToBase64String($bytes)
}

function GetPowerShellExecutablePath {
    $psName = If ($PSVersionTable.PSVersion.Major -le 5) { 'powershell' } Else { 'pwsh' }
    $psexe = Join-Path $PSHOME "${psName}.exe"
    if (!(Test-Path -Path $psexe -PathType Leaf)) {
        Write-Error "PowerShell Executable Cannot be located: $psexe" -ErrorAction Stop
    }
    $psexe
}

function Invoke-ScriptElevated {
    [CmdLetBinding()]
    param(
        [string][ValidateScript( { Test-Path -PathType Leaf $_ })]
        $FilePath,

        [object[]]$ArgumentList
    )
    $fn = $MyInvocation.MyCommand.Name

    Write-Debug "${fn}: `$FilePath: $FilePath"

    $psexe = (GetPowerShellExecutablePath)
    Write-Debug "${fn}: PowerShellExecutablePath: '$psexe'"

    $processArgs = @{
        FilePath = "$psexe"
        Verb     = 'RunAs'
    }

    $psArgs = '-NoLogo'

    if ($DebugPreference -eq 'Continue') {
        $psArgs += '-NoExit '
    }
    else {
        $processArgs['WindowStyle'] = 'Hidden'
        $psArgs = '-WindowStyle Hidden'
    }

    $psArgs += " -File `"$FilePath`""

    if ($ArgumentList) {
        $psArgs += " $ArgumentList"
    }

    $processArgs['ArgumentList'] = "$psArgs"

    Write-Debug "Start-Process @Args: $([PSCustomObject]$processArgs | Out-String)"
    Start-Process @processArgs
}

function Invoke-CommandEncodedElevated {
    [CmdLetBinding()]
    param(
        $CommandToEncode
    )
    $fn = $MyInvocation.MyCommand.Name
    Write-Debug "${fn}: `$CommandToEncode: $CommandToEncode"

    $encodedCommand = EncodeCommand $CommandToEncode
    $argList = '-WindowStyle', 'Hidden', '-EncodedCommand', $encodedCommand
    $psexe = (GetPowerShellExecutablePath)
    Write-Debug "${fn}: PowerShellExecutablePath: '$psexe'"
    Start-Process $psexe -WindowStyle Hidden -Verb RunAs -ArgumentList $argList
}
