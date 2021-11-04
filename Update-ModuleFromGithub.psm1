using namespace System.Management.Automation
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest

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
    Write-Error "Powershell cannot find module '$ModuleName' in any of the standard locations in :`$env:PSModulePath."
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
    elseif (Test-Path $ModulePath -PathType Leaf -Include '*.psm1', '*.psd1') {
        Write-Error "'$ModulePath' cannot be loaded, because it is NOT a valid module file."
    }
    else {
        Write-Error "'$ModulePath' is NOT a valid module path."
    }
}

function Get-RepoUri {
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

function Get-RepoVersion {
    param (
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
        [uri]$PsdUri,

        [switch]$ThrowOnError
    )
    [version]$version = '0.0'

    try {
        $webResponse = Invoke-WebRequest -Uri $psdUri
    }
    catch {
        $response = $_.Exception.Response
        $errMsg = "Error $($response.StatusCode.value__): $($response.ReasonPhrase) - While trying to get version from psd file at: '$($response.RequestMessage.RequestUri.AbsoluteUri)'. "

        if ($response.StatusCode.value__ -eq 404) {
            $errMsg += 'Check case of Repository Name (it is used as the name of psd file) - file names at GitHub are case sensitive!'
        }
        Write-Error "$errMsg"
    }

    $psdData = Invoke-Expression $webResponse.Content -ErrorAction SilentlyContinue

    if (-not $psdData) {
        if ($ThrowOnError) {
            Write-Error "Cannot parse content of psd at: $PsdUri"
        }
        else {
            return $version
        }
    }

    if ($psdData.ModuleVersion) {
        [version]($psdData.ModuleVersion)
    }
    else {
        if ($ThrowOnError) {
            Write-Error "ModuleVersion is not specified in PSD Document at: $PsdUri"
        }
        else {
            $version
        }
    }
}

function Get-ModuleInfo {
    [OutputType([PSModuleInfo])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleNameOrPath
    )
    $moduleInfo = @{}

    if (Test-Path $ModuleNameOrPath) {
        $moduleInfo = Import-Module $ModulePath -PassThru -ErrorAction SilentlyContinue
        Get-Module -Name $moduleInfo.Name | Where-Object Path -Like "${ModulePath}*" | Remove-Module -ErrorAction SilentlyContinue
        if (-not $moduleInfo) {
            Write-ModulePathInvalidError $ModulePath
        }
    }
    else {
        $moduleInfo = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue
        if (-not $moduleInfo) {
            Write-ModuleNameNotFoundError "$ModuleName"
        }
    }
    $moduleInfo
}

function Update-WithGit {
    param (
        [Parameter(Mandatory)][Alias('Path')][ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ModuleFolderPath,

        [Parameter()][Alias('Git')]
        [ValidateScript({ Test-Path $_ -PathType Leaf -Include 'git.exe' })]
        [string]$GitExePath
    )
    $GitExePath = if (-not $GitExePath) {
        (Get-Command git -ErrorAction SilentlyContinue)?.Source
    }
    if ($GitExePath) {
        Push-Location $ModuleFolderPath
        . $GitExePath pull origin master
        Pop-Location
    }
    else {
        Write-Error "Git must be installed and git.exe has to be in environment's PATH variable OR it's path has to be specified in -GitExePath parameter."
    }
}

function Update-WithWebRequest {
    param (
        [Parameter(Mandatory)][ValidateNotNull()]
        [uri]$Uri,

        [Parameter(Mandatory)][Alias('Path')][ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ModuleFolderPath
    )
    $outputDir = New-TemporaryDirectory
    $outputName = 'WSL-IpHandler-master'
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

    Expand-Archive -Path $outputPath -DestinationPath $outputDir

    Remove-Item -Path "$ModuleFolderPath\*" -Recurse -Force

    Move-Item -Path (Join-Path $outputDir $outputName '\*') -Destination $ModuleFolderPath -Force

    Remove-Item -Path $outputDir -Recurse -Force
}

<#
    .SYNOPSIS
    Updates local Powershell module's files using repository of the module at github.com.

    .DESCRIPTION
    Updates local Module's files to the latest available at Module's repository at github.com.
    If `git` is available (or specified as parameter) uses `git pull origin <branch>`, otherwise Invoke-WebRequest command will be used to download master.zip and expand it to Module's directory replacing all files with downloaded ones.
    For this command to work Powershell module to be updated should have been installed (or pulled / cloned) from Github in a first place. Regular Powershell modules (which are installed with Install-Module command) ARE NOT supported and command will fail!
    It is also assumed that the modules repository has main module's files (.psd1 and .psm1) located at the root of the repository.

    .PARAMETER ModuleNameOrPath
    Name of the module to be update as it appears in github address uri to repository. It is case sensitive since it is used a name for PSD file to get latest version information.

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

    .PARAMETER DoNotUseGit
    If given will update module using Invoke-WebRequest command (built-in in Powershell) even if git.exe is on PATH.

    .PARAMETER Force
    If given will update module even if there is version mismatch between installed version and version in repository.

    .EXAMPLE
    Update-ModuleFromGithub 'C:\Documents\My Modules\SomeModuleToBeUpdated' -GithubUserName theusername

    Will use git.exe (that is on PATH) to update module SomeModuleToBeUpdated (if the module has been installed from GitHub in a first place!)

    .EXAMPLE
    Update-ModuleFromGithub SomeModuleToBeUpdated githubuser -DoNotUseGit

    Will download master.zip from https://github.com/githubuser/SomModuleToBeUpdated

    .NOTES
    The default update mode is to use git.exe if it can be located with PATH.
    Adding -GitExePath parameter will allow to use git.exe that is not on PATH.
    All files in this Module's folder will be removed before update!
#>
function Update-ModuleFromGithub {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleNameOrPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('User')]
        [string]$GithubUserName,

        [ValidateNotNullOrEmpty()]
        [string]$Branch = 'master',

        [Parameter(ParameterSetName = 'Git')]
        [Alias('Git')]
        [string]$GitExePath,

        [switch]$DoNotUseGit,

        [switch]$Force
    )
    if (Test-Path $ModuleNameOrPath) {
        $ModulePath = $ModuleNameOrPath
        $ModuleName = $null
    }
    else {
        $ModuleName = $ModuleNameOrPath
        $ModulePath = $null
    }
    $GitExePath = if ($GitExePath) { $GitExePath }
    else { (Get-Command 'git.exe' -ErrorAction SilentlyContinue)?.Path }

    if ($ModuleName) {
        $moduleInfo = Get-ModuleInfo $ModuleName
        $ModulePath = $moduleInfo.ModuleBase
    }
    else {
        $moduleInfo = Get-ModuleInfo $ModulePath
        $ModuleName = $moduleInfo.Name
    }

    $uriParams = @{
        RepoName       = $ModuleName
        GithubUserName = $GithubUserName
        Branch         = $Branch
    }

    $psdUri = Get-PsdUri @uriParams

    $updateIsNeeded = $false

    if ($Force) {
        $updateIsNeeded = $true
    }
    else {
        $remoteVersion = Get-RepoVersion $psdUri
        if ("$remoteVersion" -eq '0.0') {
            Write-Error "Cannot parse latest version from $psdUri.`nTo disregard this error and update to whatever version is in the repository use -Force parameter."
            return
        }
        $updateIsNeeded = $moduleInfo.Version -lt $remoteVersion
    }

    $gitParams = @{}
    $httpParams = @{
        GithubUserName = $GithubUserName
        Branch         = $Branch
    }

    if ($updateIsNeeded) {
        if ($GitExePath -and -not $DoNotUseGit) {
            $gitParams.ModuleFolderPath = $ModulePath
            $gitParams.GitExePath = $GitExePath
            Write-Debug "Invoking Update-WithGit with parameters: $($gitParams | Out-String)"
            # Update-WithGit @gitParams
        }
        else {
            $httpParams.ModuleFolderPath = $ModulePath
            Write-Debug "Invoking Update-WithWebRequest with parameters: $($httpParams | Out-String)"
            # Update-WithWebRequest @httpParams
        }

        if ($Error) {
            Write-Error "There was an error while updating WSL-IpHandler Module: $($Error[0])"
        }
        else {
            Remove-Module $ModuleName -Force -ea SilentlyContinue
            Import-Module $ModulePath -Force
            Write-Host 'WSL-IpHandler Module was successfully updated and imported!'
        }
    }
    else {
        Write-Host "The latest version of '$ModuleName' is already installed: $($moduleInfo.Version)"
    }
}

Export-ModuleMember -Function Update-ModuleFromGithub -Verbose:$false -Debug:$false
