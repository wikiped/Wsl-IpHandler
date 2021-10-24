function WslNameCompleter {
    # TODO: There must be a way to reuse this function in ArgumentCompleterAttribute
    # Plain [ArgumentCompleter({ WslNameCompleter })] -> Does not work.
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    # Get-CommandOutputInUTF16AsUTF8 'wsl.exe' '-l' |
    wsl.exe -l |
        ConvertFrom-UTF16toUTF8 |
        Select-Object -Skip 1 |
        Where-Object { $_ -like "*${wordToComplete}*" } |
        ForEach-Object {
            $res = $_ -split ' ' | Select-Object -First 1
            New-Object System.Management.Automation.CompletionResult (
                $res,
                $res,
                'ParameterValue',
                $res
            )
        }
}
