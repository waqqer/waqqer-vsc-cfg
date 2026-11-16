param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$c = 'full',
    [Alias('d')]
    [switch]$DebugOutput
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

function Invoke-CodeCli {
    param([string[]]$Arguments)

    $PreviousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $script:CodeCliOutput = @(& $Code.Source @Arguments 2>&1)
        $script:CodeCliExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }

    if ($DebugOutput) {
        foreach ($Line in $script:CodeCliOutput) {
            Write-Host $Line -ForegroundColor DarkGray
        }
    }
}

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vscode-clean-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    $ExtensionsFile = Join-Path $TempDirectory 'extensions.txt'
    $SettingsFile = Join-Path $TempDirectory 'settings.json'
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/extensions.txt" -OutFile $ExtensionsFile
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/settings.json" -OutFile $SettingsFile
    if ($DebugOutput) { Write-Host "DEBUG: profile=$c, extensionsFile=$ExtensionsFile, settingsFile=$SettingsFile" -ForegroundColor DarkGray }

    Invoke-CodeCli -Arguments @('--list-extensions')
    $InstalledExtensions = @($script:CodeCliOutput | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$' })
    if ($script:CodeCliExitCode -ne 0) {
        throw 'VS Code failed to list installed extensions; nothing was removed.'
    }

    $PendingExtensions = @($InstalledExtensions | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    while ($PendingExtensions.Count -gt 0) {
        $PreviousPass = @($PendingExtensions)
        foreach ($Extension in $PendingExtensions) {
            Write-Host "Remove extension $Extension" -ForegroundColor Red
            if ($DebugOutput) {
                Write-Host "DEBUG: $($Code.Source) --uninstall-extension $Extension" -ForegroundColor DarkGray
            }
            Invoke-CodeCli -Arguments @('--uninstall-extension', $Extension)
        }

        if ($DebugOutput) { Write-Host "DEBUG: $($Code.Source) --list-extensions" -ForegroundColor DarkGray }
        Invoke-CodeCli -Arguments @('--list-extensions')
        $StillInstalled = @($script:CodeCliOutput | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$' })
        if ($script:CodeCliExitCode -ne 0) {
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

    $Extensions = @(Get-Content -LiteralPath $ExtensionsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $TotalExtensions = $Extensions.Count
    $CurrentExtension = 0
    foreach ($Extension in $Extensions) {
        Write-Host "Install extension $Extension" -ForegroundColor Green
        if ($DebugOutput) {
            Write-Host "DEBUG: $($Code.Source) --install-extension $Extension" -ForegroundColor DarkGray
        }
        Invoke-CodeCli -Arguments @('--install-extension', $Extension)
        if ($script:CodeCliExitCode -ne 0) {
            throw "VS Code failed to install extension: $Extension"
        }
        $CurrentExtension++
    }

    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
    Copy-Item -LiteralPath $SettingsFile -Destination $CurrentSettings -Force
    Write-Host 'Clean VS Code installation completed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
