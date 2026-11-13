$ErrorActionPreference = 'Stop'

$Repository = 'waqqer/waqqer-vsc-cfg'
$Branch = 'main'
$RawBase = "https://raw.githubusercontent.com/$Repository/$Branch"

$Code = Get-Command code -ErrorAction SilentlyContinue
if (-not $Code) {
    throw 'VS Code command-line tool "code" was not found. Install VS Code and ensure its bin folder is on PATH.'
}

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vscode-clean-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    $ExtensionsFile = Join-Path $TempDirectory 'extensions.txt'
    $SettingsFile = Join-Path $TempDirectory 'settings.json'
    Invoke-WebRequest -Uri "$RawBase/extensions.txt" -OutFile $ExtensionsFile
    Invoke-WebRequest -Uri "$RawBase/settings.json" -OutFile $SettingsFile

    $InstalledExtensions = @(& $Code.Source --list-extensions)
    if ($LASTEXITCODE -ne 0) {
        throw 'VS Code failed to list installed extensions; nothing was removed.'
    }

    foreach ($Extension in $InstalledExtensions) {
        $Extension = $Extension.Trim()
        if ($Extension) {
            Write-Host "Removing $Extension"
            & $Code.Source --uninstall-extension $Extension
            if ($LASTEXITCODE -ne 0) {
                throw "VS Code failed to remove extension: $Extension. Stopping clean install."
            }
        }
    }

    $UserDirectory = Join-Path $env:APPDATA 'Code\User'
    $CurrentSettings = Join-Path $UserDirectory 'settings.json'
    if (Test-Path -LiteralPath $CurrentSettings) {
        Remove-Item -LiteralPath $CurrentSettings -Force
    }

    Get-Content -LiteralPath $ExtensionsFile | ForEach-Object {
        $Extension = $_.Trim()
        if ($Extension -and -not $Extension.StartsWith('#')) {
            Write-Host "Installing $Extension"
            & $Code.Source --install-extension $Extension
            if ($LASTEXITCODE -ne 0) {
                throw "VS Code failed to install extension: $Extension"
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
    Copy-Item -LiteralPath $SettingsFile -Destination $CurrentSettings -Force
    Write-Host 'Clean VS Code installation completed.'
}
finally {
    Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
