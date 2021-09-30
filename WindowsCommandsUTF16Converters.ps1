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
    if ($IncludeEmptyLines.IsPresent) { $output }
    else { $output | Where-Object { $_.Length -gt 0 } }
}

function Get-WslIsRunning {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'isRunning', Justification = 'False Positive')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [ArgumentCompleter( { WslNameCompleter } )]
        [string]$WslInstanceName
    )
    $isRunning = $false
    $patternRunning = ".*\b${WslInstanceName}\b\s+\brunning\b\.*"
    wsl.exe -l -v |
        ConvertFrom-UTF16toUTF8 |
        Select-Object -Skip 1 |
        ForEach-Object { if ($_ -match $patternRunning) { $isRunning = $true } }
    $isRunning
}
