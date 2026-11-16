param(
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$c = 'full',
    [Alias('d')]
    [switch]$DebugOutput
)

$ErrorActionPreference = 'Stop'

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

$RepositoryDirectory = $PSScriptRoot
$SettingsSource = Join-Path $env:APPDATA 'Code\User\settings.json'
$ConfigDirectory = Join-Path $RepositoryDirectory 'config'
if ($c -ne 'full') {
    $ConfigDirectory = Join-Path $ConfigDirectory $c
}
$null = New-Item -ItemType Directory -Force -Path $ConfigDirectory
$ExtensionsFile = Join-Path $ConfigDirectory 'extensions.txt'
$SettingsDestination = Join-Path $ConfigDirectory 'settings.json'

if (-not (Test-Path -LiteralPath $SettingsSource -PathType Leaf)) {
    throw "VS Code settings file was not found: $SettingsSource"
}

Invoke-CodeCli -Arguments @('--list-extensions')
$Extensions = @($script:CodeCliOutput | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$' })
if ($script:CodeCliExitCode -ne 0) {
    throw 'VS Code failed to list installed extensions.'
}

if ($DebugOutput) { Write-Host "DEBUG: profile=$c, source=$SettingsSource, destination=$ConfigDirectory" -ForegroundColor DarkGray }
$Extensions | Sort-Object -Unique | Set-Content -LiteralPath $ExtensionsFile -Encoding utf8
Copy-Item -LiteralPath $SettingsSource -Destination $SettingsDestination -Force

Write-Host "Updated $ConfigDirectory with $($Extensions.Count) extensions and settings." -ForegroundColor Green
Write-Host 'Review and commit these changes to publish them to GitHub.' -ForegroundColor Cyan
