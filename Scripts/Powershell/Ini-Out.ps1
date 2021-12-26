##region Debug Functions
if (!(Test-Path function:/_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

Function ConvertTo-IniContent {
    <#
    .SYNOPSIS
    Convert hashtable to INI content

    .DESCRIPTION
    Convert hashtable to Array of strings with INI content

    .PARAMETER InputObject
    Specifies the Hashtable to parse. Enter a variable that contains the objects or type a command or expression that gets the objects.

    .PARAMETER Loose
    Adds spaces around the equal sign when writing the key = value

    .PARAMETER Pretty
    Adds an extra linebreak between Sections

    .PARAMETER NoSection
    How to label sections without name

    .NOTES
    Original Author      : Oliver Lipkau <oliver@lipkau.net>
    Source               : https://github.com/lipkau/PsIni
                           http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91

    .INPUTS
    System.String
    System.Collections.IDictionary

    .OUTPUTS
    System.String[]

    .EXAMPLE
    $Category1 = @{"Key1"="Value1";"Key2"="Value2"}
    $Category2 = @{"Key1"="Value1";"Key2"="Value2"}
    $NewINIContent = @{"Category1"=$Category1;"Category2"=$Category2}
    ConvertTo-IniContent -InputObject $NewINIContent
    -----------
    Description
    Creating a custom Hashtable

    .LINK
    ConvertFom-IniContent
    #>
    [OutputType([string[]])]
    Param(
        [Parameter( Mandatory, ValueFromPipeline )]
        [System.Collections.IDictionary]$InputObject,

        [Parameter()]
        [Switch]$Loose,

        [Parameter()]
        [Switch]$Pretty,

        [Parameter()]
        [string]$NoSection = '_'
    )
    Begin {
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function started"
        Write-Debug "$(_@) PsBoundParameters: $(& {$args} @PSBoundParameters)"

        function Out-Keys {
            param(
                [Parameter( Mandatory, ValueFromPipeline )]
                [ValidateNotNullOrEmpty()]
                [System.Collections.IDictionary]
                $InputObject,

                [Parameter( Mandatory )]
                [ref]$OutputObject,

                [Parameter( Mandatory )]
                [string]$Delimiter
            )
            Process {
                Foreach ($key in $InputObject.get_keys()) {
                    if ($key -match '^Comment\d+') {
                        Write-Debug "$(_@) Adding comment: $key"
                        $OutputObject.Value.Add("$($InputObject[$key])")
                    }
                    else {
                        Write-Debug "$(_@) Adding key: $key"
                        $InputObject[$key] | ForEach-Object { $OutputObject.Value.Add("${key}${delimiter}${_}") }
                    }
                }
            }
        }
        $delimiter = '='
        if ($Loose) { $delimiter = ' = ' }

        $noSectionOutput = New-Object System.Collections.Generic.List[string]
        $sectionsOutput = New-Object System.Collections.Generic.List[string]

        # Splatting Parameters
        $noSectionParams = @{ OutputObject = ([ref]$noSectionOutput) }
        $sectionsParams = @{ OutputObject = ([ref]$sectionsOutput) }
    }

    Process {
        Write-Debug "$(_@) InputObject: $($InputObject | Out-String)"
        $extraLF = ''

        foreach ($key in $InputObject.get_keys()) {
            if (!($InputObject[$key].GetType().GetInterface('IDictionary'))) {
                #Key value pair
                Write-Verbose "$($MyInvocation.MyCommand.Name): Adding key: $key"
                $noSectionOutput.Add("$key$delimiter$($InputObject[$key])")
            }
            elseif ($key -eq $NoSection) {
                #Key value pair of NoSection
                Out-Keys $InputObject[$key] @noSectionParams -Delimiter $delimiter
            }
            else {
                #Sections
                Write-Verbose "$($MyInvocation.MyCommand.Name): Adding Section: [$key]"

                # Only write section, if it is not a dummy ($NoSection)
                $sectionsOutput.Add("${extraLF}[$key]")
                if ($Pretty) { $extraLF = "`n" }

                if ( $InputObject[$key].Count) {
                    Out-Keys $InputObject[$key] @sectionsParams -Delimiter $delimiter
                }
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name): Finished adding entries to Ini Content."
    }

    End {
        if ($Pretty -and $noSectionOutput.Count) {
            $noSectionOutput.Add('')
        }
        if ($Pretty -and $sectionsOutput.Count) {
            $sectionsOutput.Add('')
        }

        $output = $noSectionOutput.ToArray() + $sectionsOutput.ToArray()
        Write-Debug "$(_@) output:`n$($output | Out-String)"
        Write-Output $output
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function ended"
    }
}

Function Write-IniFile {
    <#
    .SYNOPSIS
    Write hashtable content to INI file

    .DESCRIPTION
    Write hashtable content to INI file

    .NOTES
    Original Author      : Oliver Lipkau <oliver@lipkau.net>
    Source               : https://github.com/lipkau/PsIni
                           http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91

    .PARAMETER FilePath
    Specifies the path to the output file.

    .PARAMETER InputObject
    Specifies the Hashtable to be written to the file. Enter a variable that contains the objects or type a command or expression that gets the objects.

    .PARAMETER Loose
    Adds spaces around the equal sign when writing the key = value

    .PARAMETER Pretty
    Adds an extra linebreak between Sections

    .PARAMETER NoSection
    How to label sections without name

    .PARAMETER Append
    Adds the output to the end of an existing file, instead of replacing the file contents.

    .PARAMETER Encoding
    Specifies the file encoding. The default is UTF8. Valid values are:
    - ASCII:            Uses the encoding for the ASCII (7-bit) character set.
    - BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
    - Byte:             Encodes a set of characters into a sequence of bytes.
    - String:           Uses the encoding type for a string.
    - Unicode:          Encodes in UTF-16 format using the little-endian byte order.
    - UTF7:             Encodes in UTF-7 format.
    - UTF8:             Encodes in UTF-8 format.

    .PARAMETER Force
    Overrides the read-only attribute and overwrites an existing read-only file. The Force parameter does not override security restrictions.

    .PARAMETER PassThru
    Passes an FileInfo object representing the location to the pipeline.
    By default, this cmdlet does not generate any output.

    .INPUTS
    System.String
    System.Collections.IDictionary

    .OUTPUTS
    System.IO.FileSystemInfo

    .EXAMPLE
    Write-IniFile $IniVar "C:\MyIniFile.ini"
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini

    .EXAMPLE
    $IniVar | Write-IniFile "C:\MyIniFile.ini" -Force
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini and overwrites the file if it is already present

    .EXAMPLE
    $file = Write-IniFile $IniVar "C:\MyIniFile.ini" -PassThru
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini and saves the file into $file

    .EXAMPLE
    $Category1 = @{"Key1"="Value1";"Key2"="Value2"}
    $Category2 = @{"Key1"="Value1";"Key2"="Value2"}
    $NewINIContent = @{"Category1"=$Category1;"Category2"=$Category2}
    Write-IniFile -InputObject $NewINIContent -FilePath "C:\MyNewFile.ini"
    -----------
    Description
    Creating a custom Hashtable and saving it to C:\MyNewFile.ini

    .LINK
    Read-IniFile
    #>
    [OutputType([System.IO.FileSystemInfo])]
    Param(
        [ValidateNotNullOrEmpty()][ValidateScript( { Test-Path $_ -IsValid } )]
        [Parameter( Position = 0, Mandatory )]
        [String]$FilePath,

        [Parameter( Mandatory, ValueFromPipeline )]
        [System.Collections.IDictionary]$InputObject,

        [Parameter()]
        [Switch]$Loose,

        [Parameter()]
        [Switch]$Pretty,

        [Parameter()]
        [string]$NoSection = '_',

        [Parameter()]
        [switch]$Append,

        [Parameter()]
        [ValidateSet('Unicode', 'UTF7', 'UTF8', 'ASCII', 'BigEndianUnicode', 'Byte', 'String')]
        [String]$Encoding = 'UTF8',

        [Parameter()]
        [Switch]$Force,

        [Parameter()]
        [Switch]$PassThru
    )
    Begin {
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function started"
        Write-Debug "$(_@) PsBoundParameters: $($PSBoundParameters | Out-String)"
    }

    Process {
        Write-Verbose "$($MyInvocation.MyCommand.Name): Writing to file: $Filepath"

        $InputObject | ConvertTo-IniContent -Loose:$Loose -Pretty:$Pretty -NoSection $NoSection | ForEach-Object { Write-Debug "$(_@) $_"; $_ } | Out-File -FilePath $FilePath -Append:$Append -Encoding $Encoding -Force:$Force

        Write-Verbose "$($MyInvocation.MyCommand.Name): Finished Writing to file: $FilePath"
    }

    End {
        if ($PassThru) {
            Write-Debug "$(_@) PassThru argument passed - Returning FileInfo."
            Get-Item $FilePath
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function ended"
    }
}

<#
.Synopsis
    Write hash content to INI file

.Description
    Write hash content to INI file

.Notes
    Author      : Oliver Lipkau <oliver@lipkau.net>
    Blog        : http://oliver.lipkau.net/blog/
    Source      : https://github.com/lipkau/PsIni
                    http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91

    #Requires -Version 2.0

.Inputs
    System.String
    System.Collections.IDictionary

.Outputs
    System.IO.FileSystemInfo

.Example
    Out-IniFile $IniVar "C:\MyIniFile.ini"
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini

.Example
    $IniVar | Out-IniFile "C:\MyIniFile.ini" -Force
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini and overwrites the file if it is already present

.Example
    $file = Out-IniFile $IniVar "C:\MyIniFile.ini" -PassThru
    -----------
    Description
    Saves the content of the $IniVar Hashtable to the INI File c:\MyIniFile.ini and saves the file into $file

.Example
    $Category1 = @{"Key1"="Value1";"Key2"="Value2"}
    $Category2 = @{"Key1"="Value1";"Key2"="Value2"}
    $NewINIContent = @{"Category1"=$Category1;"Category2"=$Category2}
    Out-IniFile -InputObject $NewINIContent -FilePath "C:\MyNewFile.ini"
    -----------
    Description
    Creating a custom Hashtable and saving it to C:\MyNewFile.ini
.Link
    Get-IniContent
#>
<# Function Out-IniFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileSystemInfo])]
    Param(
        # Adds the output to the end of an existing file, instead of replacing the file contents.
        [switch]
        $Append,

        # Specifies the file encoding. The default is UTF8.
        #
        # Valid values are:
        # -- ASCII:  Uses the encoding for the ASCII (7-bit) character set.
        # -- BigEndianUnicode:  Encodes in UTF-16 format using the big-endian byte order.
        # -- Byte:   Encodes a set of characters into a sequence of bytes.
        # -- String:  Uses the encoding type for a string.
        # -- Unicode:  Encodes in UTF-16 format using the little-endian byte order.
        # -- UTF7:   Encodes in UTF-7 format.
        # -- UTF8:  Encodes in UTF-8 format.
        [ValidateSet('Unicode', 'UTF7', 'UTF8', 'ASCII', 'BigEndianUnicode', 'Byte', 'String')]
        [Parameter()]
        [String]
        $Encoding = 'UTF8',

        # Specifies the path to the output file.
        [ValidateNotNullOrEmpty()]
        [ValidateScript( { Test-Path $_ -IsValid } )]
        [Parameter( Position = 0, Mandatory )]
        [String]
        $FilePath,

        # Allows the cmdlet to overwrite an existing read-only file. Even using the Force parameter, the cmdlet cannot override security restrictions.
        [Switch]
        $Force,

        # Specifies the Hashtable to be written to the file. Enter a variable that contains the objects or type a command or expression that gets the objects.
        [Parameter( Mandatory, ValueFromPipeline )]
        [System.Collections.IDictionary]
        $InputObject,

        # Passes an object representing the location to the pipeline. By default, this cmdlet does not generate any output.
        [Switch]
        $Passthru,

        # Adds spaces around the equal sign when writing the key = value
        [Switch]
        $Loose,

        # Writes the file as "pretty" as possible
        #
        # Adds an extra linebreak between Sections
        [Switch]
        $Pretty,

        # How to label sections without name
        [string]
        $NoSection = '_'
    )

    Begin {
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function started"

        Write-Debug 'PsBoundParameters:'
        $PSBoundParameters.GetEnumerator() | ForEach-Object { Write-Debug "$_" }
        Write-Debug "DebugPreference: $DebugPreference"

        function Out-Keys {
            param(
                [ValidateNotNullOrEmpty()]
                [Parameter( Mandatory, ValueFromPipeline )]
                [System.Collections.IDictionary]
                $InputObject,

                [ValidateSet('Unicode', 'UTF7', 'UTF8', 'ASCII', 'BigEndianUnicode', 'Byte', 'String')]
                [string]
                $Encoding = 'UTF8',

                [ValidateNotNullOrEmpty()]
                [ValidateScript( { Test-Path $_ -IsValid })]
                [Parameter( Mandatory, ValueFromPipelineByPropertyName )]
                [Alias('Path')]
                [string]
                $FilePath,

                [Parameter( Mandatory )]
                $Delimiter,

                [Parameter( Mandatory )]
                $Invocation
            )

            Process {
                if (!($InputObject.get_keys())) {
                    Write-Warning ("No data found in '{0}'." -f $FilePath)
                }
                Foreach ($key in $InputObject.get_keys()) {
                    if ($key -match '^Comment\d+') {
                        Write-Verbose "$($Invocation.MyCommand.Name): Writing comment: $key"
                        "$($InputObject[$key])" | Out-File -Encoding $Encoding -FilePath $FilePath -Append
                    }
                    else {
                        Write-Verbose "$($Invocation.MyCommand.Name): Writing key: $key"
                        $InputObject[$key] |
                            ForEach-Object { "$key$delimiter$_" } |
                            Out-File -Encoding $Encoding -FilePath $FilePath -Append
                    }
                }
            }
        }

        $delimiter = '='
        if ($Loose) {
            $delimiter = ' = '
        }

        # Splatting Parameters
        $parameters = @{
            Encoding = $Encoding;
            FilePath = $FilePath
        }

    }

    Process {
        $extraLF = ''

        if ($Append) {
            Write-Debug ("Appending to '{0}'." -f $FilePath)
            $outfile = Get-Item $FilePath
        }
        else {
            Write-Debug ("Creating new file '{0}'." -f $FilePath)
            $outFile = New-Item -ItemType file -Path $Filepath -Force:$Force
        }

        if (!(Test-Path $outFile.FullName)) { Throw 'Could not create File' }

        Write-Verbose "$($MyInvocation.MyCommand.Name): Writing to file: $Filepath"
        foreach ($i in $InputObject.get_keys()) {
            if (!($InputObject[$i].GetType().GetInterface('IDictionary'))) {
                #Key value pair
                Write-Verbose "$($MyInvocation.MyCommand.Name): Writing key: $i"
                "$i$delimiter$($InputObject[$i])" | Out-File -Append @parameters

            }
            elseif ($i -eq $NoSection) {
                #Key value pair of NoSection
                Out-Keys $InputObject[$i] `
                    @parameters `
                    -Delimiter $delimiter `
                    -Invocation $MyInvocation
            }
            else {
                #Sections
                Write-Verbose "$($MyInvocation.MyCommand.Name): Writing Section: [$i]"

                # Only write section, if it is not a dummy ($NoSection)
                if ($i -ne $NoSection) { "$extraLF[$i]" | Out-File -Append @parameters }
                if ($Pretty) {
                    $extraLF = "`r`n"
                }

                if ( $InputObject[$i].Count) {
                    Out-Keys $InputObject[$i] `
                        @parameters `
                        -Delimiter $delimiter `
                        -Invocation $MyInvocation
                }
            }
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name): Finished Writing to file: $FilePath"
    }

    End {
        if ($PassThru) {
            Write-Debug ('Returning file due to PassThru argument.')
            Write-Output (Get-Item $outFile)
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name): Function ended"
    }
}
 #>
# Set-Alias oif Out-IniFile
