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

function Test-UriIsAccessible {
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

    Test-UriIsAccessible $PsdUri

    try {
        $webResponse = Invoke-WebRequest -Uri $psdUri -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch {
        if ($response = $_.Exception.Response) {
            $errMsg = "Error $($response.StatusCode.value__): $($response.ReasonPhrase) - While trying to get version from psd file at: '$($response.RequestMessage.RequestUri.AbsoluteUri)'."

            if ($response.StatusCode.value__ -eq 404) {
                $errMsg += "`nCheck spelling and / or case (file names at GitHub are case sensitive) of repository name (it is used as the name of psd file)!"
            }
        }
        else {
            $errMsg = $_.Exception.Message
        }

        Write-Error "$errMsg"
        Write-Debug "$(_@) Using default version: $DefaultVersion"
        return $DefaultVersion
    }

    try {
        $psdData = Invoke-Expression $webResponse.Content -ErrorAction Stop
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
    (. $GitExePath rev-parse --is-inside-work-tree 2>$null) -eq 'true'
}

function Update-WithGit {
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [Alias('Path')]
        [string]$ModuleFolderPath,

        [Parameter(Mandatory, ParameterSetName = 'Clone')]
        [string]$RepoUri,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Branch = 'master',

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [Alias('Git')]
        [string]$GitExePath
    )
    Write-Debug "$(_@) `$PSBoundParameters: $(& {$args} @PSBoundParameters)"

    if (-not $RepoUri -and -not (Test-DirectoryIsGitRepository $_ $GitExePath)) {
        Write-Error 'Update-WithGit requires -RepoUri parameter with -ModuleFolderPath is not '
    }

    Push-Location $ModuleFolderPath
    if ($RepoUri) {
        Push-Location ..
        Remove-Item (Join-Path $ModuleFolderPath '*') -Recurse -Force
        . $GitExePath clone --branch $Branch "`"$RepoUri`""
        Pop-Location
    }
    else {
        . $GitExePath pull origin $Branch
    }
    Pop-Location
}

function Update-WithWebRequest {
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
    Expand-Archive -Path $outputPath -DestinationPath $outputDir

    $expandedDirectory = $outputDir.GetDirectories() | Select-Object -First 1 -ExpandProperty FullName
    Write-Debug "$(_@) Remove-Item -Path $(Join-Path $ModuleFolderPath '*') -Recurse -Force"
    Remove-Item -Path (Join-Path $ModuleFolderPath '*') -Recurse -Force

    Write-Debug "$(_@) Move-Item -Path $(Join-Path $expandedDirectory '*') -Destination $ModuleFolderPath -Force"
    Move-Item -Path (Join-Path $expandedDirectory '*') -Destination $ModuleFolderPath -Force

    Remove-Item -Path $outputDir -Recurse -Force
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
    [CmdletBinding(DefaultParameterSetName = 'Git')]
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
        [int]$TimeoutSec = 10
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
            $params = @{ModuleFolderPath = $moduleInfo.ModuleBase }
            if ($NoGit) {
                $result.Method = 'http'
                $params.Uri = Get-ZipUri -RepoName $moduleInfo.Name -GithubUserName $GithubUserName -Branch $Branch
                Write-Debug "$(_@) Invoking Update-WithWebRequest with parameters: $($params | Out-String)"
                Write-Verbose 'Updating via HTTP protocol...'

                Test-UriIsAccessible $params.Uri

                Update-WithWebRequest @params

                $result.Status = 'Updated'
            }
            else {
                $result.Method = 'git'
                $params.GitExePath = $GitExePath
                if (-not (Test-DirectoryIsGitRepository $moduleInfo.ModuleBase $GitExePath)) {
                    $params.RepoUri = Get-RepoUri -RepoName $moduleInfo.Name -GithubUserName $GithubUserName
                }
                Write-Debug "$(_@) Invoking Update-WithGit with parameters: $($params | Out-String)"
                Write-Verbose 'Updating with git.exe ...'

                Test-UriIsAccessible $params.RepoUri

                Update-WithGit -Branch $Branch @params

                $result.Status = 'Updated'
            }
            # Attempting to Remove-Module followed by Import-Module will fail.
            # The user has to Import-Module ... -Force manually!
            # Remove-Module $moduleInfo.Name -Force -ErrorAction SilentlyContinue -Verbose:$false -Debug:$false
            # Import-Module $moduleInfo.ModuleBase -Force -Verbose:$false -Debug:$false
            Write-Information "$($moduleInfo.Name) was successfully updated from version: $($moduleInfo.Version) to: $($versions.RemoteVersion)!"
            $result
        }
        else {
            $result.Status = 'UpToDate'
            Write-Information "The latest version of '$($moduleInfo.Name)' is already installed: $($moduleInfo.Version)"
            $result
        }
    }
    catch {
        $result.Status = 'Error'
        $result.Error = $_
        Write-Error "There was an error while updating '$($moduleInfo.Name)': $($_.Exception.Message)"
        return $result
    }
}

$functionsToExport = @(
    'Update-ModuleFromGithub'
    'Get-ModuleVersions'
    'Get-ModuleInfoFromNameOrPath'
    # 'Get-ModuleVersionFromGithub'
    # 'Get-PsdUri'
)

Export-ModuleMember -Function $functionsToExport -Verbose:$false -Debug:$false
