function Get-CommonParameters {
    param(
        [Parameter(ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Mandatory)]
        [System.Management.Automation.SessionState]
        [Alias('SessionState')]
        $CallerSessionState
    )
    begin {
        $paramNames = 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction'
        $commonParams = @{}
    }
    process {
        $module = [PSModuleInfo]::new($false)
        $module.SessionState = $CallerSessionState
        $paramNames | & $module { process {
                $param = $_
                $varName = "$($param -replace 'Action' -replace 'Error', 'ErrorAction')Preference"
                $value = Get-Variable $varName -ValueOnly -ErrorAction Ignore
                switch ($value) {
                    { $_ -is [System.Management.Automation.ActionPreference] } {
                        switch -wildcard ($param) {
                            '*Action' { $commonParams[$param] = $value; break }
                            Default { $commonParams[$param] = $value -eq 'Continue' }
                        }
                    }
                }
            }
        }
    }
    end { $commonParams }
}

function Get-ArgsArray {
    param(
        [Parameter()]
        [string[]]$Arguments = @(),
        [Parameter()]
        [object]$Parameters = @{}
    )
    Write-Debug "$(_@) `$Arguments: $Arguments"
    Write-Debug "$(_@) `$Parameters: $(& {$args} @Parameters)"
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $argsArray = @($Arguments)
    Write-Debug "$(_@) `$argsArray: $argsArray"

    # $commonParameters = FilterCommonParameters $Parameters
    $commonParameters = @{}
    if ($VerbosePreference -eq 'Continue') {$commonParameters.Verbose = $true}
    if ($DebugPreference -eq 'Continue') {$commonParameters.Debug = $true}
    Write-Debug "$(_@) `$commonParameters: $(& {$args} @commonParameters)"
    # $boundCommonParameters = FilterCommonParameters $PSBoundParameters
    # Write-Debug "$(_@) `$boundCommonParameters: $(& {$args} @boundCommonParameters)"
    # $commonParameters = MergeParameters $boundCommonParameters, $commonParameters
    # Write-Debug "$(_@) Merged `$commonParameters and `$boundCommonParameters: $(& {$args} @commonParameters)"

    if ($Parameters.Count) {
        $argsArray = ConvertFrom-NamedParametersToArgsArray $Parameters -InitialArray $argsArray
        Write-Debug "$(_@) `$argsArray + `$Parameters: $argsArray"
    }

    if ($commonParameters.Count) {
        $argsArray = ConvertFrom-NamedParametersToArgsArray $commonParameters -InitialArray $argsArray
        Write-Debug "$(_@) `$argsArray + `$commonParameters: $argsArray"
    }
    $argsArray
}

function MergeParameters {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ValidateCount(2, [Int16]::MaxValue)]
        [psobject[]]$Parameters
    )
    $Parameters = @($Parameters)
    Write-Debug "$(_@) $($Parameters.Count) Parameters to merge."
    $mergedParams = [ordered]@{}
    foreach ($params in $Parameters) {
        Write-Debug "$(_@) Next Parameters to merge: $(& {$args} @params)"
        foreach ($kvPair in $params.GetEnumerator()) {
            $mergedParams[$kvPair.Key] = $kvPair.Value
        }
    }
    Write-Debug "$(_@) Merged Parameters: $(& {$args} @mergedParams)"
    $mergedParams
}

function FilterParameters {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [Parameter()]
        [string[]]$Include = @(),

        [Parameter()]
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
        [array]$InitialArray = @(),
        [string[]]$Include = @(),
        [string[]]$Exclude = @()
    )
    if ($Parameters.Count -eq 0) { return @() }

    Write-Debug "$(_@) `$Parameters: $(& {$args} @Parameters)"
    Write-Debug "$(_@) `$InitialArray: $InitialArray"
    Write-Debug "$(_@) `$Include: $Include"
    Write-Debug "$(_@) `$Exclude: $Exclude"

    $filteredParameters = FilterParameters $Parameters -Include $Include -Exclude $Exclude
    Write-Debug "$(_@) `$filteredParameters: $(& {$args} @filteredParameters)"

    $convertedParameters = ConvertParametersToArgsArray $filteredParameters -InitialArray $InitialArray
    Write-Debug "$(_@) `$convertedParameters: $convertedParameters"
    $convertedParameters
}

function ConvertParametersToArgsArray {
    param([object]$Parameters, [array]$InitialArray = @())
    $outputArray = @($InitialArray)
    function Append ($key, $value, [ref]$output = ([ref]$outputArray)) {
        if ("-$key" -notin $output.Value) { $output.Value += $value }
    }

    $Parameters.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $value = $_.Value
        switch ($value) {
            { $value -is [switch] -and $value } { Append $key "-${key}"; break }
            { $value -is [switch] -and -not $value } { break }
            { $value -is [bool] } { Append $key "-${key}"; break }
            { $value -is [string] -and $value.Contains('"') -and !$value.StartsWith('"') -and !$value.EndsWith('"') } {
                Append $key "-${key}:`"$($value -replace '"', '`"')`""; break
            }
            { $value -is [string] -and $value.Contains(' ') -and !$value.StartsWith('"') -and !$value.EndsWith('"') } {
                Append $key "-${key}:'$($value -replace "^'", '' -replace "'$", '')'"; break
            }
            { $value -is [System.Collections.ICollection] } { Append $key "-${key}:@($(($value | ForEach-Object { "'$_'" }) -join ','))"; break }
            Default { Append $key "-${key}:$($value)" }
        }
    }
    $outputArray
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
