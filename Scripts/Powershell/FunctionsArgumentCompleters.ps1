function Get-WslInstancesNames {
    wsl.exe -l | ConvertFrom-UTF16toUTF8 | Select-Object -Skip 1 |
        ForEach-Object { $_ -split ' ' | Select-Object -First 1 }
}

function WslNameCompleter {
    <#
    .SYNOPSIS
    Completes WSL name

    .PARAMETER commandName
    The name of the command for which the script block is providing tab completion.

    .PARAMETER parameterName
    The parameter whose value requires tab completion

    .PARAMETER wordToComplete
    The value the user has provided before they pressed Tab

    .PARAMETER commandAst
    The Abstract Syntax Tree (AST) for the current input line

    .PARAMETER fakeBoundParameter
    A hashtable containing the $PSBoundParameters for the cmdlet, before the user pressed Tab

    .EXAMPLE
    As part of ArgumentCompleterAttribute (seems not to work when function is in .psm1 file):
    [ArgumentCompleter({ WslNameCompleter @args })]

    .EXAMPLE
    With Register-ArgumentCompleter Command (works even for functions in .psm1 files):
    Register-ArgumentCompleter -CommandName SomeCommand -ParameterName SomeParameter -ScriptBlock $Function:WslNameCompleter
    #>
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    Get-WslInstancesNames |
        Where-Object { $_ -like "*${wordToComplete}*" } |
        ForEach-Object { New-Object System.Management.Automation.CompletionResult ($_) }
}

function Test-WslInstanceIsRunning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ArgumentCompleter({ WslNameCompleter @args })]
        [string]$WslInstanceName
    )
    (wsl.exe -l --running |
        ConvertFrom-UTF16toUTF8 |
        Select-Object -Skip 1 |
        ForEach-Object { $_ -split ' ' | Select-Object -First 1 } |
        Where-Object { $_ -eq $WslInstanceName } |
        Measure-Object |
        Select-Object -ExpandProperty Count) -gt 0
}

function Get-CommandOutputInUTF16AsUTF8 {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter()]
        [array]$ArgumentsList
    )
    $utf16 = [System.Text.Encoding]::GetEncoding('utf-16')

    $prevIn, $prevOut = [Console]::InputEncoding, [Console]::OutputEncoding
    $OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = $utf16

    try {
        # & $Command @ArgumentsList | Where-Object { $utf16.GetBytes($_) -ne [byte]0 }
        & $Command @ArgumentsList | Where-Object { $_.Length -gt 0 }
    }
    finally {
        [Console]::InputEncoding, [Console]::OutputEncoding = $prevIn, $prevOut
    }
}

function ConvertFrom-UTF16toUTF8 {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()][AllowNull()]
        [string[]]$CommandOutput,

        [Parameter()]
        [switch]$IncludeEmptyLines
    )
    $array = @($input)
    if ($array.Count) { $CommandOutput = $array }
    if (!(Test-Path variable:CommandOutput)) { $CommandOutput = @() }

    $utf8 = [System.Text.Encoding]::GetEncoding('utf-8')
    $utf16 = [System.Text.Encoding]::GetEncoding('utf-16')

    $output = $utf8.GetString([System.Text.Encoding]::Convert($utf16, $utf8, $utf8.GetBytes($CommandOutput -join "`n"))) -split "`n"
    if ($IncludeEmptyLines) { $output }
    else { $output | Where-Object { $_.Length -gt 0 } }
}
