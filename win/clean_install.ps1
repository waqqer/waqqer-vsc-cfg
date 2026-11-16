param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$c = 'full'
)

$ErrorActionPreference = 'Stop'

$Repository = 'waqqer/waqqer-vsc-cfg'
$Branch = 'main'
$RawBase = "https://raw.githubusercontent.com/$Repository/$Branch"
$ConfigPath = if ($c -eq 'full') { 'config' } else { "config/$c" }

$Code = Get-Command code -ErrorAction SilentlyContinue
if (-not $Code) {
    throw 'VS Code command-line tool "code" was not found. Install VS Code and ensure its bin folder is on PATH.'
}

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vscode-clean-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    $ExtensionsFile = Join-Path $TempDirectory 'extensions.txt'
    $SettingsFile = Join-Path $TempDirectory 'settings.json'
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/extensions.txt" -OutFile $ExtensionsFile
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/settings.json" -OutFile $SettingsFile

    $InstalledExtensions = @(& $Code.Source --list-extensions)
    if ($LASTEXITCODE -ne 0) {
        throw 'VS Code failed to list installed extensions; nothing was removed.'
    }

    $PendingExtensions = @($InstalledExtensions | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    while ($PendingExtensions.Count -gt 0) {
        $PreviousPass = @($PendingExtensions)

        foreach ($Extension in $PendingExtensions) {
            Write-Host "Removing $Extension"
            & $Code.Source --uninstall-extension $Extension
        }

        $StillInstalled = @(& $Code.Source --list-extensions)
        if ($LASTEXITCODE -ne 0) {
            throw 'VS Code failed to refresh the installed extensions list.'
        }
        $PendingExtensions = @($StillInstalled | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        if ($PendingExtensions.Count -gt 0) {
            $PreviousSorted = @($PreviousPass | Sort-Object) -join "`n"
            $CurrentSorted = @($PendingExtensions | Sort-Object) -join "`n"
            if ($PreviousSorted -eq $CurrentSorted) {
                throw "Unable to remove remaining extensions. They may depend on each other or VS Code rejected uninstall: $($PendingExtensions -join ', ')"
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
