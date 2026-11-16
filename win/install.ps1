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

$TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("vscode-config-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempDirectory | Out-Null

try {
    $ExtensionsFile = Join-Path $TempDirectory 'extensions.txt'
    $SettingsFile = Join-Path $TempDirectory 'settings.json'
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/extensions.txt" -OutFile $ExtensionsFile
    Invoke-WebRequest -Uri "$RawBase/$ConfigPath/settings.json" -OutFile $SettingsFile

    $Extensions = @(Get-Content -LiteralPath $ExtensionsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($DebugOutput) { Write-Host "DEBUG: profile=$c, extensionsFile=$ExtensionsFile, settingsFile=$SettingsFile" -ForegroundColor DarkGray }
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

    $UserDirectory = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
    Copy-Item -LiteralPath $SettingsFile -Destination (Join-Path $UserDirectory 'settings.json') -Force
    Write-Host "VS Code profile '$c' installed successfully." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
