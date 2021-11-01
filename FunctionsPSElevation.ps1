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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include '*.ps1' })]
        $ScriptPath,
        [Parameter(Position = 1)]
        [array]$ScriptArguments = @(),
        [hashtable]$ScriptParameters = @{},
        [hashtable]$ScriptCommonParameters = @{},
        [string]$WindowStyle = 'Hidden',
        [switch]$Logo,
        [switch]$Exit
    )
    $fn = $MyInvocation.MyCommand.Name

    $ArgumentList = $ScriptArguments
    Write-Debug "${fn}: `$args: $args"
    Write-Debug "${fn}: `$PSBoundParameters: $($PSBoundParameters | Out-String)"
    Write-Debug "${fn}: `$ScriptPath: $ScriptPath"
    Write-Debug "${fn}: `$ScriptArguments: $ScriptArguments"
    Write-Debug "${fn}: `$ScriptParameters: $($ScriptParameters | Out-String)"
    Write-Debug "${fn}: `$ScriptCommonParameters: $($ScriptCommonParameters| Out-String)"
    Write-Debug "${fn}: `$ArgumentList: $ArgumentList"

    $psexe = (GetPowerShellExecutablePath)
    Write-Debug "${fn}: PowerShellExecutablePath: '$psexe'"

    $debugModeOn = $DebugPreference -ne 0
    Write-Debug "${fn}: `$debugModeOn=$debugModeOn"

    $startProcessParams = @{
        FilePath = "$psexe"
        Verb     = 'RunAs'
    }

    if (-not $debugModeOn) { $startProcessParams['WindowStyle'] = 'Hidden' }

    $powershellArgs = @()

    if (-not $Logo) { $powershellArgs += '-NoLogo' }

    if ($debugModeOn -or -not $Exit) { $powershellArgs += '-NoExit' }

    if (-not $debugModeOn) { $powershellArgs += "-WindowStyle $WindowStyle" }

    $powershellArgs += "-File `"$ScriptPath`""  # Should be added BEFORE ArgumentList is added!

    $ArgumentList += & { $args } @ScriptParameters
    $ArgumentList += ConvertFrom-CommonParametersToArgs @ScriptCommonParameters
    Write-Debug "${fn}: `$ArgumentList: $ArgumentList"

    if ($ArgumentList) { $powershellArgs += $ArgumentList }
    Write-Debug "${fn}: `$powershellArgs: $powershellArgs"

    $startProcessParams['ArgumentList'] = $powershellArgs -join ' '

    Write-Debug "${fn}: Start-Process $(($startProcessParams.GetEnumerator() | ForEach-Object { "-$($_.Name) $($_.Value)" }) -join ' ')"
    Start-Process @startProcessParams
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

function ConvertFrom-CommonParametersToArgs {
    $arguments = @()
    $commonsParams = [System.Management.Automation.Cmdlet]::CommonParameters
    Write-Host "`$args: $args"
    if (-not $args) { return $arguments }

    if (($args.Count % 2) -ne 0) {
        Write-Warning "$($MyInvocation.MyCommand.Name): Number of passed arguments is not even. Only splatted key-value pairs are accepted!"
        return $arguments
    }

    foreach ($i in 0..($args.Count - 1)) {
        $param = "$($args[$i])".Replace(':', '')
        if ("$param".StartsWith('-') -and $commonsParams -contains "$param".Replace('-', '')) {
            $value = $args[$i + 1]
            switch ($param) {
                { $_ -in ('-Debug', '-Verbose') } { $arguments += $param }
                { "$_".Contains('Action', 'OrdinalIgnoreCase') } {
                    $enumValue = $null
                    if ([System.Enum]::TryParse($ErrorActionPreference.GetType(), $value, $false, [ref]$enumValue)) {
                        $arguments += $param
                        $arguments += $enumValue
                    }
                }
                Default {
                    $arguments += $param
                    $arguments += $param
                }
            }
        }
    }
    $arguments
}
