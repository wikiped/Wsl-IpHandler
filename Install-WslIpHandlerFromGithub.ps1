$ErrorActionPreference = 'Stop'
Set-StrictMode -Version latest
$ModuleName = 'Wsl-IpHandler'

function PromptForChoice {
    param(
        [string]$Title,
        [string]$Text,
        [string]$FirstOption,
        [string]$FirstHelp,
        [string]$SecondOption,
        [string]$SecondHelp
    )
    $firstChoice = New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList "&$FirstOption", $FirstHelp
    $secondChoice = New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList "&$SecondOption", $SecondHelp
    $Host.UI.PromptForChoice($Title, $Text, @($firstChoice, $secondChoice), 0)
}

if ($PSVersionTable.PSVersion.Major -ne 7) {
    $promptParams = @{
        Title        = "Incompatible Powershell version detected: $($PSVersionTable.PSVersion)!"
        Text         = "$ModuleName has only been tested to work with Powershell Core version 7.1+. Please confirm if you want to continue installing the module:"
        FirstOption  = 'No'
        SecondOption = 'Yes'
    }
    if ((PromptForChoice @promptParams) -eq 0) {
        Write-Warning "$ModuleName installation was cancelled."
        exit
    }
}

$ModulesDirectory = "$(Split-Path $Profile)\Modules"
New-Item $ModulesDirectory -Type Directory -ErrorAction SilentlyContinue | Out-Null
$ModulesDirectoryInfo = Get-Item $ModulesDirectory
$targetDirectory = Join-Path $ModulesDirectoryInfo.FullName $ModuleName

if ($targetDirectory -eq $ModulesDirectory) {
    Write-Error "$ModuleName module directory can not be the same as all modules directory: $ModulesDirectory!" -ErrorAction Stop
}

Push-Location $ModulesDirectory

$targetDirectoryExistsAndNotEmpty = (Test-Path $targetDirectory -PathType Container) -and ((Get-Item $targetDirectory -ErrorAction Ignore | Get-ChildItem -ErrorAction Ignore | Measure-Object | Select-Object -ExpandProperty Count) -gt 0)

if ($targetDirectoryExistsAndNotEmpty) {
    $targetDeletePromptParams = @{
        Title = "'$targetDirectory' already exists and is not empty!"
        Text = 'Please confirm if you want to continue and delete all files it contains!'
        FirstOption = 'Yes'
        FirstHelp = "Yes: all files in '$targetDirectory' will be permanently deleted."
        SecondOption = 'No'
        SecondHelp = "No: all files in '$targetDirectory' will be left as is and installation process will be aborted."
    }
    switch ((PromptForChoice @targetDeletePromptParams)) {
        0 {
            Remove-Item (Join-Path $targetDirectory '*') -Recurse -Force
        }
        1 {
            Write-Warning "$ModuleName installation was cancelled."
            exit
        }
        Default { Throw "Strange choice: '$_', can't help with that!" }
    }
}
else {
    Remove-Item $targetDirectory -Force -ErrorAction Ignore
}

$git = Get-Command 'git.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

if ($null -ne $git) {
    $gitPromptParams = @{
        Title = "Found git.exe at: $($git.Path)"
        Text = "Use git version: $($git.Version) to clone repository to '$targetDirectory'?"
        FirstOption = 'Yes'
        FirstHelp = "Yes: git.exe will be use to clone module's repository to '$targetDirectory'."
        SecondOption = 'No'
        SecondHelp = "No: HTTP protocol will be used to download repository zip file and expanded it to '$targetDirectory'."

    }
    $chooseGit = PromptForChoice @gitPromptParams
}
else {
    $chooseGit = -1
}

if ($chooseGit -eq 0) {
    git clone https://github.com/wikiped/Wsl-IpHandler
}
else {
    $outFile = "$ModuleName.zip"
    Invoke-WebRequest -Uri https://codeload.github.com/wikiped/Wsl-IpHandler/zip/refs/heads/master -OutFile $outFile
    Expand-Archive -Path $outFile -DestinationPath '.' -Force
    Remove-Item -Path $outFile
    Rename-Item -Path "${ModuleName}-master" -NewName $ModuleName -Force
}

$psdFile = "$ModuleName.psd1"
$version = (Import-Psd (Join-Path $targetDirectory $psdFile) -ErrorAction Ignore | Select-Object -ExpandProperty ModuleVersion -ErrorAction Ignore) ?? ""
if ($version) { $version = "version: $version " }
Write-Host "Wsl-IpHandler ${version}was installed in: '$targetDirectory'"
Pop-Location
