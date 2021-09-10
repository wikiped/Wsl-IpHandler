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

function Get-WslIsRunning {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'isRunning', Justification = 'False Positive')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$WslInstanceName
    )
    $isRunning = $false
    $patternRunning = ".*\b${WslInstanceName}\b\s+\brunning\b\.*"
    Get-CommandOutputInUTF16AsUTF8 'wsl.exe' '-l', '-v' |
        Select-Object -Skip 1 |
        ForEach-Object { if ($_ -match $patternRunning) { $isRunning = $true } }
    $isRunning
}
