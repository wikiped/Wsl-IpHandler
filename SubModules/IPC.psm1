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

Function Compress-Payload {
    [OutputType([string])]
    param(
        [Parameter(Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0)]
        [string]$Payload
    )
    $inputArray = @($input)
    if ($inputArray.Count) { $Payload = $inputArray }
    if (!(Test-Path variable:Payload)) { $Payload = @() }
    if (-not $Payload) { return '' }
    try {
        $memoryStream = New-Object System.IO.MemoryStream
        $gZipStream = New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
        $streamWriter = New-Object System.IO.StreamWriter($gZipStream)
        $strPayload = [System.Collections.Generic.List[string]]::new()
        $Payload | ForEach-Object { $null = $strPayload.Add($Payload) }
        $streamWriter.Write([string]$strPayload)
        $compressedPayload = [Convert]::ToBase64String($memoryStream.ToArray())
        return $compressedPayload
    }
    catch {
        Throw
    }
    finally {
        if ($null -ne $streamWriter) { $streamWriter.Dispose() }
        if ($null -ne $gZipStream) { $gZipStream.Dispose() }
        if ($null -ne $memoryStream) { $memoryStream.Dispose() }
    }
}

Function Expand-Payload {
    [OutputType([string])]
    param(
        [Parameter(Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0)]
        [string]$CompressedPayload
    )
    $inputArray = @($input)
    if ($inputArray.Count) { $CompressedPayload = $inputArray }
    if (!(Test-Path variable:CompressedPayload)) { $CompressedPayload = @() }
    if (-not $CompressedPayload) { return '' }

    $CompressedPayload | ForEach-Object {
        try {
            $memoryStream = New-Object System.IO.MemoryStream
            $gZipStream = New-Object System.IO.Compression.GZipStream($memoryStream, [System.IO.Compression.CompressionMode]::Decompress)
            $streamReader = New-Object System.IO.StreamReader($gZipStream)
            $data = [Convert]::FromBase64String($_)
            $memoryStream.Write($data, 0, $data.Length)
            $memoryStream.Seek(0, 0) | Out-Null
            $payload = $streamReader.ReadToEnd()
            $payload
        }
        catch { Throw }
        finally {
            if ($null -ne $streamReader) { $streamReader.Dispose() }
            if ($null -ne $gZipStream) { $gZipStream.Dispose() }
            if ($null -ne $memoryStream) { $memoryStream.Dispose() }
        }
    }
}

function Receive-ObjectFromPipe {
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$PipeName,

        [Parameter()][ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$BufferSize,

        [Parameter()]
        [ValidateScript({ $_ -in ([System.Text.Encoding]::GetEncodings().Name) })]
        [string]$Encoding = 'UTF-8'
    )
    try {
        $pipeServer = New-Object -TypeName System.IO.Pipes.NamedPipeServerStream -ArgumentList "\\.\pipe\$PipeName", ([System.IO.Pipes.PipeDirection]::In), 1, ([System.IO.Pipes.PipeTransmissionMode]::Message)
        Write-Debug "$(_@) Server Pipe created: $($pipeServer | Out-String)"

        $readerArgs = @( $pipeServer, ([System.Text.Encoding]::GetEncoding($Encoding)))
        if ($BufferSize -gt 0) { $readerArgs += @($true, $BufferSize) }
        $pipeServerReader = New-Object -TypeName System.IO.StreamReader -ArgumentList $readerArgs
        Write-Debug "$(_@) Server Pipe Reader created: $($pipeServerReader | Out-String)"

        Write-Debug "$(_@) Server Pipe waiting for connection..."
        $pipeServer.WaitForConnection()
        Write-Debug "$(_@) Server Pipe Connected."

        $cliXml = $pipeServerReader.ReadToEnd()
        Write-Debug "$(_@) Server Pipe Reader read message"
        Write-Debug "$(_@) $cliXml"

        $clixmlModule = Join-Path $PSScriptRoot 'CliXml.psm1'
        Import-Module $clixmlModule
        $result = $cliXml | ConvertFrom-Clixml
        Write-Debug "$(_@) Deserialized message:"
        Write-Debug "$(_@) $($result | Out-String)"

        return $result
    }
    catch {
        Write-Debug "$(_@) $($_.Exception.Message)"
        Throw
    }
    finally {
        if ($null -ne $pipeServerReader) { $pipeServerReader.Dispose() }
        if ($null -ne $pipeServer) { $pipeServer.Dispose() }
    }
}

function Send-ObjectToPipe {
    param (
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$PipeName,

        [Parameter()][ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$BufferSize,

        [Parameter()]
        [ValidateScript({ $_ -in ([System.Text.Encoding]::GetEncodings().Name) })]
        [string]$Encoding = 'UTF-8'
    )
    try {
        $clixmlModule = Join-Path $PSScriptRoot 'CliXml.psm1'
        Import-Module $clixmlModule
        $pipeClient = New-Object -TypeName System.IO.Pipes.NamedPipeClientStream -ArgumentList '.', "\\.\pipe\$PipeName", ([System.IO.Pipes.PipeDirection]::Out)
        $pipeClientWriter = New-Object -TypeName System.IO.StreamWriter -ArgumentList $pipeClient, ([System.Text.Encoding]::GetEncoding($encoding)), $BufferSize
        Write-Debug 'Client Pipe trying to connect to Pipe Server...'
        $pipeClient.Connect()
        Write-Debug 'Client Pipe connected to Pipe Server.'
        $cliXml = $Object | ConvertTo-Clixml -Depth 32
        Write-Debug "$(_@) Client Pipe converted $Object to clixml:"
        Write-Debug "$(_@) $cliXml"
        $pipeClientWriter.Write($cliXml)
        $pipeClientWriter.Flush()
        Write-Debug "$(_@) Client Pipe has written and flushed clixml."
    }
    catch {
        Write-Debug "$(_@) $($_.Exception.Message)"
        Throw
    }
    finally {
        if ($null -ne $pipeClientWriter) {
            $pipeClientWriter.Dispose()
        }
        if ($null -ne $pipeClient) {
            $pipeClient.Dispose()
        }
    }
}

function Send-CommandOutputToPipe {
    param (
        [Parameter(Mandatory, ParameterSetName = 'Command')]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(Mandatory, ParameterSetName = 'EncodedCommand')]
        [ValidateNotNullOrEmpty()]
        [string]$EncodedCommand,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PipeName,

        [Parameter()][string]$Encoding = 'UTF-8',

        [Parameter()][ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$BufferSize,

        [Parameter(Mandatory)]
        [string]$ModulesPath
    )
    try {
        if ($PSCmdlet.ParameterSetName -eq 'EncodedCommand') {
            $encoderModule = Join-Path $ModulesPath 'Encoders.psm1'
            Import-Module $encoderModule
            $Command = Get-DecodedCommand $EncodedCommand
        }
        Write-Debug "Command: $Command"

        $result = [scriptblock]::Create($Command).Invoke()
        Write-Debug "Command returned: $result"
        if ($null -eq $result) {
            $message = "Command returned unexpected `$null."
            Write-Debug "$message"
            $result = New-Object System.InvalidCastException -ArgumentList $message
        }
    }
    catch {
        Write-Debug "Command Invocation thrown exception: $($_.Exception.Message)"
        $result = $_
    }

    $sendParams = @{
        Object   = $result
        PipeName = $PipeName
        Encoding = $Encoding
    }
    if ($BufferSize -gt 0) {
        $sendParams.Buffer = $BufferSize
    }
    Import-Module (Join-Path $ModulesPath 'IPC.psm1')
    $commonParams = @{}
    if ($VerbosePreference -gt 0) { $commonParams.Verbose = $true }
    if ($DebugPreference -gt 0) { $commonParams.Debug = $true }
    Send-ObjectToPipe @sendParams @commonParams
}

function Get-CommandStringToSendOutputToPipe {
    param (
        [Parameter(Mandatory, ParameterSetName = 'Command')]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(Mandatory, ParameterSetName = 'EncodedCommand')]
        [ValidateNotNullOrEmpty()]
        [string]$EncodedCommand,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PipeName,

        [Parameter()][string]$Encoding = 'UTF-8',

        [Parameter()][ValidateRange(1, [Int32]::MaxValue)]
        [Int32]$BufferSize
    )
    $subModulesPath = Split-Path $PSCommandPath
    $encoderModule = Join-Path $subModulesPath 'Encoders.psm1'
    Import-Module $encoderModule

    if ($PSCmdlet.ParameterSetName -eq 'Command') {
        # Write-Debug "$(_@) Command: $Command"
        # if ($VerbosePreference -gt 0) {
        #     $Command += ' -Verbose'
        #     Write-Debug "$(_@) Command with Verbose: $Command"
        # }
        # if ($DebugPreference -gt 0) {
        #     $Command += ' -Debug'
        #     Write-Debug "$(_@) Command with Debug: $Command"
        # }
        $EncodedCommand = Get-EncodedCommand $Command
    }
    # else {
    #     if ($VerbosePreference -gt 0 -or $DebugPreference -gt 0) {
    #         $Command = Get-DecodedCommand $EncodedCommand
    #         Write-Debug "$(_@) Decoded Command: $Command"
    #         if ($VerbosePreference -gt 0) {
    #             $Command += ' -Verbose'
    #             Write-Debug "$(_@) Decoded Command with Verbose: $Command"
    #         }
    #         if ($DebugPreference -gt 0) {
    #             $Command += ' -Debug'
    #             Write-Debug "$(_@) Decoded Command with Debug: $Command"
    #         }
    #         $EncodedCommand = Get-EncodedCommand $Command
    #     }
    # }
    $commandArray = @(
        '&'
        ${function:Send-CommandOutputToPipe}.Ast.Body.Extent.Text
        '-EncodedCommand'
        $EncodedCommand
        '-PipeName'
        $ExecutionContext.InvokeCommand.ExpandString($PipeName)
        '-Encoding'
        $ExecutionContext.InvokeCommand.ExpandString($Encoding)
        '-BufferSize'
        $ExecutionContext.InvokeCommand.ExpandString($BufferSize)
        '-ModulesPath'
        $ExecutionContext.InvokeCommand.ExpandString("'$subModulesPath'")
    )
    if ($VerbosePreference -gt 0) { $commandArray += '-Verbose' }
    if ($DebugPreference -gt 0) { $commandArray += '-Debug' }
    $commandArray -join ' '
}

Export-ModuleMember -Function Receive-ObjectFromPipe
Export-ModuleMember -Function Get-CommandStringToSendOutputToPipe
Export-ModuleMember -Function Send-CommandOutputToPipe
Export-ModuleMember -Function Send-ObjectToPipe
