$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest

function ConvertTo-Clixml {
    <#
    .SYNOPSIS
    Converts an object to Clixml.

    .DESCRIPTION
    Converts an object to Clixml.

    .PARAMETER InputObject
    The input object to serialize

    .PARAMETER Depth
    The depth of the members to serialize

    .EXAMPLE
    $string = 'A string'
    ConvertTo-Clixml -InputObject $string

    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>A string</S>
    </Objs>

    .EXAMPLE
    $string = 'A string'
    $string | ConvertTo-Clixml

    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>A string</S>
    </Objs>

    .EXAMPLE
    $string1 = 'A string'
    $string2 = 'Another string'
    ConvertTo-Clixml -InputObject $string1,$string2

    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>A string</S>
    </Objs>
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>Another string</S>
    </Objs>

    .EXAMPLE
    $string1 = 'A string'
    $string2 = 'Another string'
    $string1,$string2 | ConvertTo-Clixml

    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>A string</S>
    </Objs>
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>Another string</S>
    </Objs>

    .OUTPUTS
    [String[]]

    .LINK
    http://convert.readthedocs.io/en/latest/functions/ConvertTo-Clixml/
    #>
    [CmdletBinding(HelpUri = 'http://convert.readthedocs.io/en/latest/functions/ConvertTo-Clixml/')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [AllowNull()][AllowEmptyCollection()]
        [PSObject]
        $InputObject,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int32]
        $Depth = 2
    )
    $collectionType = [System.Collections.ICollection]
    if ($PSCmdlet.MyInvocation.ExpectingInput) {
        if ($input -is $collectionType -and $input.Count -eq 0) {
            return [System.Management.Automation.PSSerializer]::Serialize($input, $Depth)
        }
    }
    else {
        if ($InputObject -is $collectionType -and $InputObject.Count -eq 0) {
            return [System.Management.Automation.PSSerializer]::Serialize($InputObject, $Depth)
        }
    }
    $inputArray = @($input)
    if ($inputArray.Count) { $InputObject = $inputArray }
    if (!(Test-Path variable:InputObject)) { $InputObject = $null }

    try {
        [System.Management.Automation.PSSerializer]::Serialize($InputObject, $Depth)
    }
    catch {
        Write-Error -ErrorRecord $_
    }
}

function ConvertFrom-Clixml {
    <#
    .SYNOPSIS
    Converts Clixml to an object.

    .DESCRIPTION
    Converts Clixml to an object.

    .PARAMETER String
    Clixml as a string object.

    .EXAMPLE
    $xml = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>ThisIsMyString</S>
    </Objs>
    "@
    ConvertFrom-Clixml -String $xml

    ThisIsMyString

    .EXAMPLE
    $xml = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>ThisIsMyString</S>
    </Objs>
    "@
    $xml | ConvertFrom-Clixml

    ThisIsMyString

    .EXAMPLE
    $xml = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>ThisIsMyString</S>
    </Objs>
    "@
    $xml2 = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>This is another string</S>
    </Objs>
    "@
    ConvertFrom-Clixml -String $xml,$xml2

    ThisIsMyString
    This is another string

    .EXAMPLE
    $xml = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>ThisIsMyString</S>
    </Objs>
    "@
    $xml2 = @"
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
    <S>This is another string</S>
    </Objs>
    "@
    $xml,$xml2 | ConvertFrom-Clixml

    ThisIsMyString
    This is another string

    .OUTPUTS
    [Object[]]

    .LINK
    http://convert.readthedocs.io/en/latest/functions/ConvertFrom-Clixml/
    #>
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ClixmlString
    )
    $inputArray = @($input)
    if ($inputArray.Count) { $ClixmlString = $inputArray }
    if (!(Test-Path variable:ClixmlString)) {
        $ClixmlString = '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"></Objs>' 
    }

    try {
        [System.Management.Automation.PSSerializer]::Deserialize($ClixmlString)
    }
    catch {
        Write-Error -ErrorRecord $_
    }
}

Export-ModuleMember -Function ConvertTo-Clixml
Export-ModuleMember -Function ConvertFrom-Clixml
