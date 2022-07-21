##region Debug Functions
if (!(Test-Path function:/_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

Function ConvertFrom-IniContent {
    <#
    .Synopsis
    Parses content of an INI file into OrderedDictionary

    .Description
    Gets the content of an INI file and returns it as a hashtable

    .Notes
    Original Author		: Oliver Lipkau <oliver@lipkau.net>
    Source		        : https://github.com/lipkau/PsIni
                          http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91

    .Inputs
    System.String[]

    .Outputs
    System.Collections.Specialized.OrderedDictionary

    .Example
    $FileContent = ConvertFrom-IniContent (Get-Content "C:\MyIniFile.ini")
    -----------
    Description
    Saves the content of the c:\MyIniFile.ini in a hashtable called $FileContent

    .Example
    $inifilepath | Get-Content | $FileContent = ConvertFrom-IniContent
    -----------
    Description
    Gets the content of the ini file passed through the pipe into a hashtable called $FileContent

    .Example
    C:\PS>$FileContent = ConvertFrom-IniContent (Get-Content "c:\settings.ini")
    C:\PS>$FileContent["Section"]["Key"]
    -----------
    Description
    Returns the key "Key" of the section "Section" from the C:\settings.ini file

    .Link
    Write-IniFile
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param(
        # Specifies input array of strings.
        [AllowEmptyCollection()][AllowEmptyString()][AllowNull()]
        [Parameter( Mandatory, ValueFromPipeline )]
        [String[]]
        $InputContent,

        # Specify what characters should be describe a comment.
        # Lines starting with the characters provided will be rendered as comments.
        # Default: ";"
        [Char[]]
        $CommentChar = @(';', '#'),

        # How to label sections without name
        [string]
        $NoSection = '_',

        # Remove lines determined to be comments from the resulting dictionary.
        [Switch]
        $IgnoreComments
    )

    Begin {
        Write-Debug "$(_@) Function started"
        Write-Debug "$(_@) PsBoundParameters: $($PSBoundParameters | Out-String)"

        $commentRegex = "^(?<comment>\s*[$(-join $CommentChar)].*)$"
        $sectionRegex = '^\s*\[(?<section>.+)\]\s*$'
        $keyRegex = "^\s*(?<name>.+?)\s*=\s*(?<quote>['`"]?)(?<value>.*)\2\s*$"

        Write-Debug "$(_@) commentRegex is: $commentRegex"
        Write-Debug "$(_@) sectionRegex is: $sectionRegex"
        Write-Debug "$(_@) keyRegex is: $keyRegex"

        $ini = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
        $commentCount = 0
    }

    Process {
        if (-not $InputContent) { return }

        Write-Debug "$(_@) Started Processing $($InputContent.Count) Lines of Content."

        switch -regex ($InputContent) {
            $sectionRegex {
                # Section
                Write-Debug "$(_@) sectionRegex Matches: $(& {$args} @Matches)"
                $section = $matches.section
                Write-Debug "$(_@) Adding section : $section"
                $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
                $CommentCount = 0
                continue
            }
            $commentRegex {
                # Comment
                Write-Debug "$(_@) commentRegex Matches: $(& {$args} @Matches)"
                if ($IgnoreComments) {
                    Write-Debug "$(_@) Ignoring comment $($matches[1])"
                }
                else {
                    if (!(Test-Path 'variable:local:section')) {
                        $section = $NoSection
                        Write-Debug "$(_@) Adding NoSection : $section"
                        $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
                    }
                    $value = $matches.comment
                    $CommentCount++
                    Write-Debug "$(_@) Incremented CommentCount is now: $CommentCount"
                    $name = "Comment$CommentCount"
                    Write-Debug "$(_@) Adding $name with value: $value"
                    $ini[$section][$name] = $value
                }
                continue
            }
            $keyRegex {
                # Key
                Write-Debug "$(_@) keyRegex Matches: $(& {$args} @Matches)"
                if (!(Test-Path 'variable:local:section')) {
                    $section = $NoSection
                    Write-Debug "$(_@) Adding NoSection : $section"
                    $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
                }
                $name = $matches.name
                $value = $matches.value
                Write-Debug "$(_@) Adding key $name with value: $value"
                if ($ini[$section][$name]) {
                    if ($ini[$section][$name] -is [System.Collections.IList]) {
                        $ini[$section][$name].Add($value) | Out-Null
                    }
                    else {
                        $newValue = New-Object System.Collections.ArrayList
                        $newValue.Add($ini[$section][$name]) | Out-Null
                        $ini[$section][$name] = $newValue
                        $ini[$section][$name].Add($value) | Out-Null
                    }
                }
                else {
                    $ini[$section][$name] = $value
                }
                continue
            }
        }
        Write-Debug "$(_@) Finished Processing $($InputContent.Count) Lines of Content."
    }

    End {
        Write-Debug "$(_@) Function ended"
        Write-Output $ini
    }
}

Function Read-IniFile {
    <#
    .Synopsis
    Gets the content of an INI file

    .Description
    Gets the content of an INI file and returns it as a hashtable

    .Notes
    Original Author		: Oliver Lipkau <oliver@lipkau.net>
    Source		        : https://github.com/lipkau/PsIni
                          http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91

    .Inputs
    System.String

    .Outputs
    System.Collections.Specialized.OrderedDictionary

    .Example
    $FileContent = Read-IniFile "C:\MyIniFile.ini"
    -----------
    Description
    Saves the content of the c:\MyIniFile.ini in a hashtable called $FileContent

    .Example
    $inifilepath | $FileContent = Read-IniFile
    -----------
    Description
    Gets the content of the ini file passed through the pipe into a hashtable called $FileContent

    .Example
    C:\PS>$FileContent = Read-IniFile "c:\settings.ini"
    C:\PS>$FileContent["Section"]["Key"]
    -----------
    Description
    Returns the key "Key" of the section "Section" from the C:\settings.ini file

    .Link
    Write-IniFile
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    Param(
        # Specifies the path to the input file.
        [ValidateNotNullOrEmpty()]
        [Parameter( Mandatory, ValueFromPipeline )]
        [String]
        $FilePath,

        # Specify what characters should be describe a comment.
        # Lines starting with the characters provided will be rendered as comments.
        # Default: ";"
        [Char[]]
        $CommentChar = @(';', '#'),

        # How to label sections without name
        [string]
        $NoSection = '_',

        # Remove lines determined to be comments from the resulting dictionary.
        [Switch]
        $IgnoreComments
    )
    Begin {
        Write-Debug "$(_@) Function started"
        Write-Debug "$(_@) PsBoundParameters: $(& {$args} @PSBoundParameters)"
    }

    Process {
        Write-Debug "$(_@) Processing file: $Filepath"

        if (!(Test-Path $Filepath)) {
            Write-Warning ("`"{0}`" was not found." -f $Filepath)
            return New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)
        }

        $ini = Get-Content $FilePath | ConvertFrom-IniContent -CommentChar $CommentChar -NoSection $NoSection -IgnoreComments:$IgnoreComments

        Write-Debug "$(_@) Finished Processing file: $FilePath"
        Write-Output $ini
    }

    End {
        Write-Debug "$(_@) Function ended"
    }
}

# Set-Alias gic ConvertFrom-IniContent
