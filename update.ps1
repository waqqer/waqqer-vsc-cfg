$ErrorActionPreference = 'Stop'

$Code = Get-Command code -ErrorAction SilentlyContinue
if (-not $Code) {
    throw 'VS Code command-line tool "code" was not found. Install VS Code and ensure its bin folder is on PATH.'
}

$RepositoryDirectory = $PSScriptRoot
$SettingsSource = Join-Path $env:APPDATA 'Code\User\settings.json'
$ExtensionsFile = Join-Path $RepositoryDirectory 'extensions.txt'
$SettingsDestination = Join-Path $RepositoryDirectory 'settings.json'

if (-not (Test-Path -LiteralPath $SettingsSource -PathType Leaf)) {
    throw "VS Code settings file was not found: $SettingsSource"
}

$Extensions = @(& $Code.Source --list-extensions)
if ($LASTEXITCODE -ne 0) {
    throw 'VS Code failed to list installed extensions.'
}

$Extensions | Sort-Object -Unique | Set-Content -LiteralPath $ExtensionsFile -Encoding utf8
Copy-Item -LiteralPath $SettingsSource -Destination $SettingsDestination -Force

Write-Host "Updated extensions.txt with $($Extensions.Count) extensions."
Write-Host 'Copied the current VS Code settings to settings.json.'
Write-Host 'Review and commit these changes to publish them to GitHub.'
