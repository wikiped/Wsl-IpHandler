using namespace System.Management.Automation
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest

#region Debug Functions
if (!(Test-Path function:/_@)) {
    function script:_@ {
        $parentInvocationInfo = Get-Variable MyInvocation -Scope 1 -ValueOnly
        $parentCommandName = $parentInvocationInfo.MyCommand.Name ?? $MyInvocation.MyCommand.Name
        "$parentCommandName [$($MyInvocation.ScriptLineNumber)]:"
    }
}
#endregion Debug Functions

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Write-ModuleNameNotFoundError {
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [string]$ModuleName
    )
    # $modulePaths = ($env:PSModulePath -split ';') -join "`n"
    Write-Error "Powershell cannot find module '$ModuleName' in any of the locations listed in `$env:PSModulePath."
}

function Write-ModulePathInvalidError {
    param (
        [Parameter()]
        [Alias('Path')]
        [string]$ModulePath
    )
    if ([string]::IsNullOrWhiteSpace($ModulePath)) {
        Write-Error "Module Path cannot be `$null or empty."
    }
    elseif (Test-Path $ModulePath -PathType Container) {
        Write-Error "'$ModulePath' is NOT a valid path, because no valid module file was found in that directory."
    }
    elseif (Test-Path $ModulePath -PathType Leaf -Include '*.psd1') {
        Write-Error "'$ModulePath' is NOT valid here or is malformed."
    }
    elseif (Test-Path $ModulePath -PathType Leaf -Include '*.psm1') {
        Write-Error "PSM1 file: '$ModulePath' is NOT valid here."
    }
    else {
        Write-Error "'$ModulePath' is NOT a valid module path."
    }
}

function Get-GitExePath {
    param([switch]$Throw)
    $gitCmd = Get-Command 'git.exe' -ErrorAction Ignore
    if ($gitCmd) { $gitCmd.Path }
    else {
        $msg = "Git.exe cannot be found on PATH. If it is installed try using '-GitExePath' parameter to specify git.exe location."
        if ($Throw) { Write-Error "$msg" }
        else { Write-Warning "$msg" }
    }
}

function Get-RepoUri {
    param (
        [Parameter(Mandatory)][Alias('Name')][ValidateNotNullOrEmpty()]
        [string]$RepoName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$GithubUserName
    )
    "https://github.com/${GithubUserName}/${RepoName}"
}

function Get-ZipUri {
    param (
        [Parameter(Mandatory)][Alias('Name')][ValidateNotNullOrEmpty()]
        [string]$RepoName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$GithubUserName,

        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$Branch = 'master'
    )
    "https://codeload.github.com/${GithubUserName}/${RepoName}/zip/refs/heads/${Branch}"
}

function Get-PsdUri {
    param (
        [Parameter(Mandatory)][Alias('Name')][ValidateNotNullOrEmpty()]
        [string]$RepoName,

        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [string]$GithubUserName,

        [Parameter()][ValidateNotNullOrEmpty()]
        [string]$Branch = 'master'
    )
    "https://raw.githubusercontent.com/${GithubUserName}/${RepoName}/${Branch}/${RepoName}.psd1"
}

function Assert-UriIsAccessible {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [uri]$Uri
    )
    if (-not (Test-Connection -ComputerName $Uri.Host -Quiet)) {
        $errorMessage = "Cannot connect to $($uri.Host). Either the site is down or there is no internet connection."
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                ([System.ApplicationException]$errorMessage),
                'WSLIpHandler.UriIsNotAccessible',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $Uri
            )
        )
    }
}

function Get-FileContentFromGithub {
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [uri]$Uri,

        [Parameter()]
        [int]$TimeoutSec = 10
    )
    Assert-UriIsAccessible $Uri

    try {
        $webResponse = Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSec -ErrorAction Stop
        $webResponse.Content
    }
    catch {
        if ($response = $_.Exception.Response) {
            $errMsg = "Error $($response.StatusCode.value__): $($response.ReasonPhrase) - While getting content of file at: '$($response.RequestMessage.RequestUri.AbsoluteUri)'"

            if ($response.StatusCode.value__ -eq 404) {
                $errMsg += "`nCheck spelling and / or case of repository name (if it is used as the name of the file), because file names at GitHub are case sensitive!"
            }
            Write-Error $errMsg
        }
        else {
            Write-Error $_.Exception.Message
        }
    }
}

function Get-ModuleVersionFromGithub {
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [uri]$PsdUri,

        [Parameter()]
        [int]$TimeoutSec = 10,

        [Parameter()][ValidateNotNullOrEmpty()]
        [version]$DefaultVersion = '0.0'
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    try {
        $psdContent = Get-FileContentFromGithub -Uri $PsdUri -TimeoutSec $TimeoutSec
    }
    catch {
        Write-Error "$($_.Exception.Message)"
        Write-Debug "$(_@) Using default version: $DefaultVersion"
        return $DefaultVersion
    }

    try {
        $psdData = Invoke-Expression $psdContent -ErrorAction Stop
    }
    catch {
        Write-Error "$($_.Exception.Message)"
        Write-Debug "$(_@) Using default version: '$DefaultVersion'."
        return $DefaultVersion
    }

    if (-not $psdData) {
        Write-Error "Cannot parse content of psd file at: '$PsdUri'"
        Write-Debug "$(_@) Using default version: '$DefaultVersion'."
        return $DefaultVersion
    }

    if ($psdData.ModuleVersion) {
        [version]($psdData.ModuleVersion)
    }
    else {
        Write-Error "ModuleVersion is not specified in PSD file: '$PsdUri'"
        Write-Debug "$(_@) Using default version: '$DefaultVersion'."
        $DefaultVersion
    }
}

function Get-ModuleInfoFromNameOrPath {
    [OutputType([PSModuleInfo])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleNameOrPath
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $moduleInfo = @{}

    if (Test-Path $ModuleNameOrPath -PathType Container) {
        $moduleInfo = Test-ModuleManifest (Join-Path $ModuleNameOrPath ((Split-Path $ModuleNameOrPath -Leaf) + '.psd1')) -ErrorAction SilentlyContinue -Verbose:$false -Debug:$false
        if (-not $moduleInfo) {
            Write-ModulePathInvalidError $ModuleNameOrPath
        }
    }
    elseif (Test-Path $ModuleNameOrPath -PathType Leaf -Include '*.psd1') {
        $moduleInfo = Test-ModuleManifest $ModuleNameOrPath -ErrorAction SilentlyContinue -Verbose:$false -Debug:$false
        if (-not $moduleInfo) {
            Write-ModulePathInvalidError $ModuleNameOrPath
        }
    }
    elseif (Test-Path $ModuleNameOrPath -PathType Leaf -Include '*.psm1') {
        Write-ModulePathInvalidError $ModuleNameOrPath
    }
    else {
        $moduleInfo = Get-Module -Name $ModuleNameOrPath -ErrorAction SilentlyContinue
        if (-not $moduleInfo) {
            $moduleInfo = Get-Module -Name $ModuleNameOrPath -ListAvailable -ErrorAction SilentlyContinue
        }
        if (-not $moduleInfo) {
            Write-ModuleNameNotFoundError "$ModuleNameOrPath"
        }
    }
    $moduleInfo
}

function Test-DirectoryIsGitRepository {
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [Alias('Git')]
        [string]$GitExePath
    )
    Push-Location -LiteralPath $Path
    try {
        (. $GitExePath rev-parse --is-inside-work-tree 2>$null) -eq 'true'
    }
    finally {
        Pop-Location
    }
}

function Update-WithGit {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [Alias('Path')]
        [string]$ModuleFolderPath,

        [Parameter(Mandatory, ParameterSetName = 'Clone')]
        [ValidateNotNullOrEmpty()]
        [string]$RepoName,

        [Parameter(Mandatory, ParameterSetName = 'Clone')]
        [ValidateNotNullOrEmpty()]
        [string]$GithubUserName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Branch = 'master',

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [Alias('Git')]
        [string]$GitExePath
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $isRepoDirectory = Test-DirectoryIsGitRepository -Path $ModuleFolderPath -GitExePath $GitExePath

    Push-Location $ModuleFolderPath

    $currentBranch = . $GitExePath symbolic-ref --short HEAD 2>$null  # v2.22+ (. $GitExePath branch --show-current)

    if ($isRepoDirectory -and $Branch -eq $currentBranch) {
        $result = ''

        if ($PSCmdlet.ShouldProcess($Branch, "$GitExePath pull origin")) {
            $result = . $GitExePath pull origin $Branch 2>&1
        }

        Pop-Location

        if ($result) {
            if ("$result".StartsWith('fatal:')) {
                Write-Error "Command failed: $GitExePath pull origin $Branch" -ea Continue
                Write-Error "With error:`n$result" -ErrorAction Stop
            }
            else {
                Write-Verbose "$result"
            }
        }
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'Clone') {
        $RepoUri = Get-RepoUri -RepoName $RepoName -GithubUserName $GithubUserName

        Assert-UriIsAccessible $RepoUri

        Push-Location ..

        if ($PSCmdlet.ShouldProcess("$(Join-Path $ModuleFolderPath '*')", 'Remove-Item -Recurse -Force')) {
            Remove-Item (Join-Path $ModuleFolderPath '*') -Recurse -Force -Confirm:$false
        }

        $result = ''

        if ($PSCmdlet.ShouldProcess($RepoUri, "$GitExePath clone --branch $Branch")) {
            $result = . $GitExePath clone --branch $Branch $RepoUri 2>&1
        }

        Pop-Location
        Pop-Location

        if ($result) {
            if ("$result".StartsWith('fatal:')) {
                Write-Error "Command failed: $GitExePath clone --branch $Branch $RepoUri" -ea Continue
                Write-Error "With error:`n$result" -ErrorAction Stop
            }
            else {
                Write-Verbose "$result"
            }
        }
    }
    else {
        Pop-Location
        Write-Error 'Update-WithGit requires parameters -RepoName and -GithubUserName when -ModuleFolderPath parameter is not a git repository' -ErrorAction Stop
    }
}

function Update-WithWebRequest {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)][ValidateNotNull()]
        [uri]$Uri,

        [Parameter(Mandatory)][Alias('Path')][ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ModuleFolderPath
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    $outputDir = New-TemporaryDirectory
    $outputName = Split-Path $ModuleFolderPath -Leaf
    $outputPath = Join-Path $outputDir "${outputName}.zip"

    try {
        Invoke-WebRequest -Uri $Uri -OutFile $outputPath
    }
    catch {
        $response = $_.Exception.Response

        $errMsg = "Error $($response.StatusCode.value__): $($response.ReasonPhrase) - While trying to download update from: '$($response.RequestMessage.RequestUri.AbsoluteUri)'."

        if ($response.StatusCode.value__ -eq 404) {
            $errMsg += 'Check Repository name, GitHub User name and Branch name!'
        }
        Write-Error "$errMsg"
    }

    Write-Debug "$(_@) Expand-Archive -Path $outputPath -DestinationPath $outputDir"
    if ($PSCmdlet.ShouldProcess("$outputPath to: $outputDir", 'Expand-Archive')) {
        Expand-Archive -Path $outputPath -DestinationPath $outputDir
    }

    $expandedDirectory = $outputDir.GetDirectories() | Select-Object -First 1 -ExpandProperty FullName
    Write-Debug "$(_@) Remove-Item -Path $(Join-Path $ModuleFolderPath '*') -Recurse -Force"
    if ($PSCmdlet.ShouldProcess("$(Join-Path $ModuleFolderPath '*')", 'Remove-Item -Recurse -Force')) {
        Remove-Item -Path (Join-Path $ModuleFolderPath '*') -Recurse -Force -Confirm:$false
    }

    Write-Debug "$(_@) Move-Item -Path $(Join-Path $expandedDirectory '*') -Destination $ModuleFolderPath -Force"
    if ($PSCmdlet.ShouldProcess("$(Join-Path $expandedDirectory '*') to '$ModuleFolderPath'", 'Move-Item -Force')) {
        Move-Item -Path (Join-Path $expandedDirectory '*') -Destination $ModuleFolderPath -Force
    }

    if ($PSCmdlet.ShouldProcess("$outputDir", 'Remove-Item -Recurse -Force')) {
        Remove-Item -LiteralPath $outputDir -Recurse -Force
    }
}

function Get-ModuleVersions {
    <#
    .SYNOPSIS
    Returns PSCustomObject with two Properties: LocalVersion and RemoteVersion of Powershell module. Where RemoteVersion is version of the module available at github.com.

    .DESCRIPTION
    Uses psd1 file at github repository to query for latest version at a specified branch (defaults to master).
    It is assumed that the modules repository has main module's files (.psd1 and .psm1) located at the root of the repository.

    .PARAMETER ModuleInfo
    PSModuleInfo object from Get-Module or Import-Module -PassThru or Test-ModuleManifest commands

    .PARAMETER ModuleNameOrPath
    Name of the module to be check as it appears in github address uri to repository. It is case sensitive since it is used as the name for PSD file to get latest version information.

    Path to folder where module is located or to the module manifest file. i.e:
    'C:\Documents\My Modules\SomeModuleToBeUpdated'
    'C:\Documents\My Modules\SomeModuleToBeUpdated\SomeModuleToBeUpdated.psd1'

    .PARAMETER GithubUserName
    User name as it appears in GitHub address uri to repository. Case insensitive.

    .PARAMETER Branch
    Branch name. Defaults to master.

    .PARAMETER TimeoutSec
    Timeout in seconds to wait for response from github.com

    .EXAMPLE
    Get-ModuleVersions 'C:\Documents\My Modules\SomeModuleToBeUpdated' -GithubUserName theusername

    .EXAMPLE
    Get-ModuleVersions SomeModuleToBeUpdated githubuser
    #>
    [CmdletBinding(DefaultParameterSetName = 'ModuleInfo')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ModuleInfo')]
        [ValidateNotNull()]
        [PSModuleInfo]$ModuleInfo,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'NameOrPath')]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleNameOrPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('User')]
        [string]$GithubUserName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Branch = 'master',

        [Parameter()]
        [int]$TimeoutSec = 10
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if ($PSCmdlet.ParameterSetName -eq 'NameOrPath') {
        $ModuleInfo = Get-ModuleInfoFromNameOrPath $ModuleNameOrPath
    }

    $result = [PSCustomObject]@{
        LocalVersion  = $ModuleInfo.Version
        RemoteVersion = $null
    }

    if (-not $GithubUserName) { $GithubUserName = $ModuleInfo.Author }

    $uriParams = @{
        RepoName       = $ModuleInfo.Name
        GithubUserName = $GithubUserName
        Branch         = $Branch
    }

    $psdUri = Get-PsdUri @uriParams
    Write-Debug "$(_@) Get-PsdUri $( &{ $args } @uriParams )"
    Write-Debug "$(_@) `$psdUri: $psdUri"
    $remoteVersion = Get-ModuleVersionFromGithub $psdUri -DefaultVersion $ModuleInfo.Version -TimeoutSec $TimeoutSec
    Write-Debug "$(_@) Installed version: $($ModuleInfo.Version)"
    Write-Debug "$(_@) Github version:    $remoteVersion"
    $result.RemoteVersion = $remoteVersion
    $result
}

function Get-ModuleQualifiedName {
    param([Parameter()][System.Management.Automation.PSModuleInfo]$ModuleInfo)
    $psModulePathMatches = $env:PSModulePath -split ';' |
        Where-Object { $ModuleInfo.ModuleBase.ToLower() -match [regex]::Escape($_.ToLower()) } |
        Measure-Object |
        Select-Object -ExpandProperty Count
    $psModulePathMatches -eq 0 ? "`"$($ModuleInfo.ModuleBase)`"" : $($ModuleInfo.Name)
}

function Invoke-PostUpdateCommand {
    <#
    .SYNOPSIS
    Invokes in a separate process (with Start-Process) specified PostUpdateCommand.

    .DESCRIPTION
    Invokes in a separate process (with Start-Process) specified PostUpdateCommand.
    The following arguments will be passed to the specified command: $PathToModule, $VersionBeforeUpdate, $VersionAfterUpdate.

    .PARAMETER ModuleBase
    Path to the module being updated

    .PARAMETER VersionBefore
    Version of the module before update

    .PARAMETER VersionAfter
    Version of the module after update

    .PARAMETER PostUpdateCommand
    Specifies Command to execute.
    Can be almost the same types as pwsh.exe parameters: -File and -Command, except for '-' (i.e. standard input is not supported).
    PostUpdateCommand can be also a web address to a valid powershell script file (i.e. ps1 file in github repository).
    The following arguments will be passed to the specified command: $PathToModule, $VersionBeforeUpdate, $VersionAfterUpdate.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleBase,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [version]$VersionBefore,

        [Parameter(Mandatory, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [version]$VersionAfter,

        [Parameter(Position = 3)]
        [object]$PostUpdateCommand = $null
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if (-not $PostUpdateCommand) { return }

    if (-not $PSBoundParameters.ContainsKey('InformationAction')) {
        $InformationPreference = 'Continue'
    }

    Write-Verbose 'Running Post Update Command...'

    $pwsh = Get-Command 'pwsh' -ErrorAction Ignore | Select-Object -ExpandProperty Source

    if ($pwsh) {
        $argsArray = @('-NoLogo', '-NoProfile')
        $noExit = $false
        $argsString = "`"$($ModuleBase)`" $VersionBefore $VersionAfter"

        if ($VerbosePreference -eq 'Continue') { $argsString += ' -Verbose'; $noExit = $true }
        if ($DebugPreference -eq 'Continue') { $argsString += ' -Debug'; $noExit = $true }
        if ($noExit) { $argsArray += '-NoExit' }

        Write-Debug "$(_@) `$argsString: $argsString"

        try {
            if (Test-Path $PostUpdateCommand -PathType Leaf) {
                $argsArray += "-File `"$PostUpdateCommand`" $argsString"
            }
            elseif ($content = Get-FileContentFromGithub $PostUpdateCommand -ErrorAction Ignore) {
                if ($content) {
                    $argsArray += "-Command `"& { $content } $argsString`""
                }
                else {
                    $argsArray += "-Command `"& { $PostUpdateCommand } $argsString`""
                }
            }
            else {
                $argsArray += "-Command `"& { $PostUpdateCommand } $argsString`""
            }
            $argsArrayString = $argsArray -join ' '
            Write-Debug "$(_@) Post Update Command: $pwsh $argsArrayString"
            if ($noExit) {
                Write-Information "Post Update Command has been started in a new window.`nPlease close the opened window manually to continue..."
            }
            Start-Process -FilePath $pwsh -ArgumentList $argsArrayString -Wait
        }
        catch {
            Write-Error "Error executing Post Update Command: $($_.Exception.Message)"
        }
    }
    else {
        Write-Error 'Cannot execute Post Update Command: Powershell Core (pwsh.exe) not found.'
    }
}

function Update-ModuleFromGithub {
    <#
    .SYNOPSIS
    Updates local Powershell module's files using repository of the module at github.com.

    .DESCRIPTION
    Updates local Module's files to the latest available at Module's repository at github.com.
    If `git` is available (or specified as parameter) uses `git pull origin <branch>`, otherwise Invoke-WebRequest command will be used to download master.zip and expand it to Module's directory replacing all files with downloaded ones.
    For this command to work Powershell module to be updated should have been installed (or pulled / cloned) from Github in a first place. Regular Powershell modules (which are installed with Install-Module command) ARE NOT supported and command will fail!
    It is also assumed that the modules repository has main module's files (.psd1 and .psm1) located at the root of the repository.

    .PARAMETER ModuleName
    Name of the module to be update as it appears in github address uri to repository. It is case sensitive since it is used a name for PSD file to get latest version information.

    .PARAMETER ModulePath
    Path to folder where module is located or to the module file. i.e:
    'C:\Documents\My Modules\SomeModuleToBeUpdated'
    'C:\Documents\My Modules\SomeModuleToBeUpdated\SomeModuleToBeUpdated.psm1'
    'C:\Documents\My Modules\SomeModuleToBeUpdated\SomeModuleToBeUpdated.psd1'

    .PARAMETER GithubUserName
    User name as it appears in GitHub address uri to repository. Case insensitive.

    .PARAMETER Branch
    Branch name. Defaults to master.

    .PARAMETER GitExePath
    Path to git.exe if it can not be located with environment's PATH variable.

    .PARAMETER NoGit
    If given will update module using Invoke-WebRequest command (built-in in Powershell) even if git.exe is on PATH.

    .PARAMETER Force
    If given will update module even if there is version mismatch between installed version and version in repository.

    .PARAMETER TimeoutSec
    Timeout in seconds to wait for response from github.com

    .PARAMETER PostUpdateCommand
    Specifies Command to execute after the module has been updated.
    PostUpdateCommand can take almost the same types as pwsh.exe parameters: -File and -Command, except for '-'. Standard input is not supported.
    PostUpdateCommand can be a web address to a valid powershell script file (i.e. ps1 file in github repository).
    The following arguments will be passed to the specified command: $PathToModule, $VersionBeforeUpdate, $VersionAfterUpdate.

    .EXAMPLE
    Update-ModuleFromGithub 'C:\Documents\My Modules\SomeModuleToBeUpdated' -GithubUserName theusername

    Will use git.exe (that is on PATH) to update module SomeModuleToBeUpdated (if the module has been installed from GitHub in a first place!)

    .EXAMPLE
    Update-ModuleFromGithub SomeModuleToBeUpdated githubuser -NoGit

    Will download master.zip from https://github.com/githubuser/SomModuleToBeUpdated

    .NOTES
    The default update mode is to use git.exe if it can be located with PATH.
    Adding -GitExePath parameter will allow to use git.exe that is not on PATH.
    All files in this Module's folder will be removed before update!
    #>
    [CmdletBinding(DefaultParameterSetName = 'Git', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleNameOrPath,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [Alias('User')]
        [string]$GithubUserName,

        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch = 'master',

        [Parameter(ParameterSetName = 'Git')]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [Alias('Git')]
        [string]$GitExePath,

        [Parameter(Mandatory, ParameterSetName = 'Http')]
        [switch]$NoGit,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [int]$TimeoutSec = 10,

        [Parameter()]
        [object]$PostUpdateCommand = $null
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if (-not $PSBoundParameters.ContainsKey('InformationAction')) {
        $InformationPreference = 'Continue'
    }

    $result = [PSCustomObject]@{
        Module     = $null
        ModulePath = $null
        Method     = $null
        Status     = $null
        Error      = $null
        PSTypeName = 'UpdateModuleResult'
    }

    $moduleInfo = Get-ModuleInfoFromNameOrPath $ModuleNameOrPath

    if ($moduleInfo) {
        $result.Module = $moduleInfo.Name
        $result.ModulePath = $moduleInfo.ModuleBase
    }
    else {
        Write-Error "Cannot get PSModuleInfo from: $ModuleNameOrPath"
        return $result
    }

    if ($PSCmdlet.ParameterSetName -eq 'Git') {
        if (-not $GitExePath) {
            $GitExePath = Get-GitExePath
            if (-not $GitExePath) { $NoGit = $true }
        }
    }

    $versions = Get-ModuleVersions -ModuleInfo $moduleInfo -GithubUserName $GithubUserName -Branch $Branch -TimeoutSec $TimeoutSec

    if ($Force) {
        $updateIsNeeded = $true
    }
    else {
        $updateIsNeeded = $versions.LocalVersion -lt $versions.RemoteVersion
    }
    Write-Debug "$(_@) `$updateIsNeeded: $updateIsNeeded"

    try {
        if ($updateIsNeeded) {
            $moduleToImport = Get-ModuleQualifiedName -ModuleInfo $moduleInfo
            $params = @{ ModuleFolderPath = $moduleInfo.ModuleBase; WhatIf = $WhatIfPreference }
            if ($NoGit) {
                $result.Method = 'http'
                $params.Uri = Get-ZipUri -RepoName $moduleInfo.Name -GithubUserName $GithubUserName -Branch $Branch
                Write-Debug "$(_@) Invoking Update-WithWebRequest with parameters: $($params | Out-String)"
                Write-Verbose 'Updating via HTTP protocol...'

                Assert-UriIsAccessible $params.Uri

                Update-WithWebRequest @params | Out-Null
            }
            else {
                $result.Method = 'git'
                $params.GitExePath = $GitExePath
                $params.RepoName = $moduleInfo.Name
                $params.GithubUserName = $GithubUserName

                Write-Debug "$(_@) Invoking Update-WithGit with parameters: $($params | Out-String)"
                Write-Verbose 'Updating with git.exe ...'

                Update-WithGit -Branch $Branch @params | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($moduleInfo.ModuleBase, "Invoke-PostUpdateCommand -PostUpdateCommand $PostUpdateCommand")) {
                $result.Status = 'Updated'
                Invoke-PostUpdateCommand -ModuleBase $moduleInfo.ModuleBase -VersionBefore $versions.LocalVersion -VersionAfter $versions.RemoteVersion -PostUpdateCommand $PostUpdateCommand
                # Attempting to Import-Module ... -Force here will fail.
                # The user has to Import-Module ... -Force manually!
                Write-Information "$($moduleInfo.Name) was successfully updated from version: $($moduleInfo.Version) to: $($versions.RemoteVersion)!"
                Write-Warning "To use updated version of $($moduleInfo.Name) in current session execute:`nImport-Module $moduleToImport -Force"
            }
            else {
                $result.Status = 'What if: Updated'
            }
        }
        else {
            $result.Status = 'UpToDate'
            Write-Information "The latest version of '$($moduleInfo.Name)' is already installed: $($moduleInfo.Version)"
        }
    }
    catch {
        $result.Status = 'Error'
        $result.Error = $_
        Write-Error "There was an error while updating '$($moduleInfo.Name)': $($_.Exception.Message)"
    }
    Write-Debug "$(_@) `$result: $($result | Out-String)"
    $result
}

$functionsToExport = @(
    'Update-ModuleFromGithub'
    'Get-ModuleVersions'
    'Get-ModuleInfoFromNameOrPath'
    'Invoke-PostUpdateCommand'
)

Export-ModuleMember -Function $functionsToExport -Verbose:$false -Debug:$false
