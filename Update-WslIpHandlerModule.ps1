[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version latest

$ModuleName = 'WSL-IpHandler'

Remove-Module $ModuleName -Force

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $PSScriptRoot
    git pull origin master
    Pop-Location
}
else {
    $uri = 'https://codeload.github.com/wikiped/WSL-IpHandler/zip/refs/heads/master'
    $outputDir = New-TemporaryDirectory
    $outputName = 'WSL-IpHandler-master'
    $outputPath = Join-Path $outputDir "${outputName}.zip"

    Invoke-WebRequest -Uri $uri -OutFile $outputPath

    Remove-Item -Path "$PSScriptRoot\*" -Recurse -Force

    Expand-Archive -Path $outputPath -DestinationPath $outputDir

    Move-Item -Path (Join-path $outputDir $outputName '\*') -Destination $PSScriptRoot -Force

    Remove-Item -Path $outputDir -Recurse -Force
}

if ($Error) {
    Write-Error "There was an error while updating WSL-IpHandler Module: $($Error[0])"
}
else {
    Import-Module $ModuleName -Force
    Write-Host 'WSL-IpHandler Module was successfully updated and imported!'
}
