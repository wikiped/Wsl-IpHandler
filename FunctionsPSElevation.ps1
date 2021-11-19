function IsElevated {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { $true }
    else { $false }
}

function EncodeCommand {
    param ([string]$Command)
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
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include '*.ps1' })]
        $ScriptPath,
        [Parameter(Position = 1)]
        [string[]]$ScriptArguments = @(),
        [hashtable]$ScriptParameters = @{},
        [string]$WindowStyle = 'Hidden',
        [switch]$Exit,
        [switch]$Encode
    )


    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$ScriptPath: $ScriptPath"
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$ScriptArguments: $ScriptArguments"
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$ScriptParameters: $(& {$args} @ScriptParameters)"
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $scriptArgsArray = @($ScriptArguments)
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$scriptArgsArray: $scriptArgsArray"

    $ScriptCommonParameters = FilterCommonParameters $PSBoundParameters
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$ScriptCommonParameters: $(& {$args} @ScriptCommonParameters)"

    $psexe = GetPowerShellExecutablePath
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: PowerShellExecutablePath: '$psexe'"

    $debugMode = $DebugPreference -ne 0
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$debugMode=$debugMode"

    $startProcessParams = [ordered]@{ Verb = 'RunAs' }
    $psExeArgs = @()

    $psExeArgs += '-NoLogo', '-NoProfile'

    if ($debugMode -or -not $Exit) { $psExeArgs += '-NoExit' }

    if (-not $debugMode) {
        $startProcessParams.WindowStyle = $WindowStyle
        $psExeArgs += "-WindowStyle $WindowStyle"
    }

    if ($ScriptParameters.Count) {
        $scriptParamsAsArgs = ConvertFrom-NamedParametersToArgsArray $ScriptParameters
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$scriptParamsAsArgs: $scriptParamsAsArgs"

        $scriptArgsArray += $scriptParamsAsArgs
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$scriptArgsArray + `$scriptParamsAsArgs: $scriptArgsArray"
    }

    if ($ScriptCommonParameters.Count) {
        $scriptCommonParametersAsArgs = ConvertFrom-NamedParametersToArgsArray $ScriptCommonParameters
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$scriptCommonParametersAsArgs: $scriptCommonParametersAsArgs"
        $scriptArgsArray += $scriptCommonParametersAsArgs
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `scriptArgsArray + `$scriptCommonParametersAsArgs: $scriptArgsArray"
    }

    if ($Encode) {
        $commandsToEncode = @('&', "'$ScriptPath'")
        $commandsToEncode += $scriptArgsArray

        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `Command to Encode: '$commandsToEncode'"
        Invoke-CommandElevated $commandsToEncode -Encode # @ScriptCommonParameters
    }
    else {
        $psExeArgs += "-File `"$ScriptPath`""  # Should be added BEFORE ScriptArguments are added!
        $psExeArgs += $scriptArgsArray
        $startProcessParams.ArgumentList = $psExeArgs -join ' '
        Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Start-Process $psexe $(& {$args} @startProcessParams)"
        Start-Process $psexe @startProcessParams
    }
}

function Invoke-CommandElevated {
    param(
        [Parameter()]$Command,
        [switch]$Encode,
        [switch]$IgnoreCommonParameters
    )

    if ($Command -is [array]) { $Command = $Command -join ' ' }
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$Command: '$Command'"

    $psexe = (GetPowerShellExecutablePath)
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: PowerShellExecutablePath: '$psexe'"

    $psExeArgsList = '-NoLogo', '-NoProfile'
    $startProcessParams = @{ Verb = 'RunAs' }

    if ($DebugPreference -eq 0) {
        $startProcessParams.WindowStyle = 'Hidden'
        $psExeArgsList += @('-WindowStyle Hidden')
    }
    else {
        $psExeArgsList += '-NoExit'
    }

    if (-not $IgnoreCommonParameters) {
        $commonParameters = FilterCommonParameters $PSBoundParameters
        $commonParametersAsArgs = (ConvertParametersToArgumentsArray $commonParameters) -join ' '
        $Command += " $commonParametersAsArgs"
    }

    if ($Encode) {
        $encodedCommand = EncodeCommand $Command
        $psExeArgsList += @('-EncodedCommand', $encodedCommand)
    }
    else {
        $psExeArgsList += @('-Command', $Command)
    }

    $startProcessParams.ArgumentList = $psExeArgsList -join ' '

    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: Start-Process $psexe  -ArgumentList $psExeArgsList"
    Start-Process $psexe @startProcessParams
}

function ConvertParametersToArgumentsArray {
    param([hashtable]$Dict)
    $Dict.GetEnumerator() | ForEach-Object {
        switch ($_) {
            { $_.Value -is [switch] -and $_.Value } { "-$($_.Name)"; break }
            { $_.Value -is [switch] -and -not $_.Value } { break }
            { $_.Value -is [bool] } { "-$($_.Name):`$$($_.Value))"; break }
            { $_.Value -is [array] } { "-$($_.Name):@($(($_.Value | ForEach-Object { "'$_'" }) -join ','))"; break }
            Default { "-$($_.Name):$($_.Value)" }
        }
    }
}

function FilterParameters {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [string[]]$Include = @(),

        [string[]]$Exclude = @()
    )
    if (-not $Include.Count -and -not $Exclude.Count) { return $Parameters }
    $result = @{}
    foreach ($kv in $Parameters.GetEnumerator()) {
        if ($Include.Count -and $Exclude.Count) {
            if ($kv.Name -in $Include -and $kv.Name -notin $Exclude) {
                $result[$kv.Name] = $kv.Value
            }
        }
        elseif ($Include.Count -and -not $Exclude.Count) {
            if ($kv.Name -in $Include) {
                $result[$kv.Name] = $kv.Value
            }
        }
        elseif ($Exclude.Count -and -not $Include.Count) {
            if ($kv.Name -in $Exclude) {
                Continue
            }
            else {
                $result[$kv.Name] = $kv.Value
            }
        }
        else {
            $result[$kv.Name] = $kv.Value
        }
    }
    $result
}

function FilterCommonParameters {
    param([Parameter()][hashtable]$Parameters = @{})
    FilterParameters $Parameters -Include ([System.Management.Automation.Cmdlet]::CommonParameters)
}

function FilterNonCommonParameters {
    param([Parameter()][hashtable]$Parameters = @{})
    FilterParameters $Parameters -Exclude ([System.Management.Automation.Cmdlet]::CommonParameters)
}

function ConvertFrom-NamedParametersToArgsArray {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,
        [string[]]$Include = @()
    )

    if ($Parameters.Count -eq 0) { return @() }


    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$Parameters: $(& {$args} @Parameters)"
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$Include: $Include"

    $filteredParameters = FilterParameters $Parameters $Include
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$filteredParameters: $(& {$args} @filteredParameters)"

    $convertedParameters = ConvertParametersToArgumentsArray $filteredParameters
    Write-Debug "$($MyInvocation.MyCommand.Name) [$($MyInvocation.ScriptLineNumber)]: `$convertedParameters: $convertedParameters"
    $convertedParameters
}

function Get-CommonParametersFromArgs {
    $parameters = [System.Collections.Generic.Dictionary`2[[System.String], [System.Object]]]::new()
    $commonParameters = [System.Management.Automation.Cmdlet]::CommonParameters
    foreach ($arg in $args) {
        $normArg = $arg.Replace('-', '')
        if ($arg.StartsWith('-') -and $normArg -in $commonParameters) {
            $parameters[$normArg] = [switch]$True
        }
    }
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($param.Key -in $commonParameters) {
            $parameters[$param.Key] = $param.Value
        }
    }
    $parameters
}

function ConvertFrom-CommonParametersToArgs {
    $arguments = @()
    if (-not $args) { return $arguments }
    $commonsParams = [System.Management.Automation.Cmdlet]::CommonParameters

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
