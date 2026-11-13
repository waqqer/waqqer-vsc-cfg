$ErrorActionPreference = 'Stop'

# Replace this once with the GitHub repository that contains this file.
$Repository = 'waqqer/waqqer-vsc-cfg'
$Branch = 'main'
$RawBase = "https://raw.githubusercontent.com/$Repository/$Branch"

$Code = Get-Command code -ErrorAction SilentlyContinue
if (-not $Code) {
    throw 'VS Code command-line tool "code" was not found. Install VS Code and ensure its bin folder is on PATH.'
}

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vscode-config-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    $ExtensionsFile = Join-Path $TempDirectory 'extensions.txt'
    $SettingsFile = Join-Path $TempDirectory 'settings.json'
    Invoke-WebRequest -Uri "$RawBase/extensions.txt" -OutFile $ExtensionsFile
    Invoke-WebRequest -Uri "$RawBase/settings.json" -OutFile $SettingsFile

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

    $UserDirectory = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
    Copy-Item -LiteralPath $SettingsFile -Destination (Join-Path $UserDirectory 'settings.json') -Force
    Write-Host 'VS Code extensions and user settings have been installed.'
}
finally {
    Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
