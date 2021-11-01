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
    As part of ArgumentCompleterAttribute:
    [ArgumentCompleter({ WslNameCompleter $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter })]

    Or with Register-ArgumentCompleter Command:
    Register-ArgumentCompleter -CommandName SomeCommand -ParameterName SomeParameter -ScriptBlock $Function:WslNameCompleter
    #>
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
