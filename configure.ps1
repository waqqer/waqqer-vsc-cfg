param(
    [Alias('d')][switch]$DebugOutput,
    [Alias('p')][string]$Path
)

$ErrorActionPreference = 'Stop'
$Green = 'Green'; $Yellow = 'Yellow'; $Gray = 'DarkGray'; $Red = 'Red'; $Cyan = 'Cyan'
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigRoot = Join-Path $ScriptDirectory 'config'
$Cancelled = $false
$CancelHandler = [ConsoleCancelEventHandler]{ param($sender, $eventArgs) $eventArgs.Cancel = $true; $script:Cancelled = $true }
[Console]::add_CancelKeyPress($CancelHandler)

function Stop-IfCancelled {
    if ($script:Cancelled) { throw [System.OperationCanceledException]::new('Cancelled by user.') }
}

function Invoke-CodeCli {
    param([string[]]$Arguments)
    Stop-IfCancelled
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:CodeCli @Arguments 2>&1)
        $status = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    Stop-IfCancelled
    if ($status -ne 0) {
        foreach ($line in $output) { Write-Host $line -ForegroundColor $script:Red }
        return $status
    }
    if ($script:DebugOutput) { foreach ($line in $output) { if ("$line".Trim()) { Write-Host "  $line" -ForegroundColor $script:Gray } } }
    return 0
}

function Invoke-CodeCapture {
    param([string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:CodeCli @Arguments 2>&1)
        $status = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    Stop-IfCancelled
    [pscustomobject]@{ Output = $output; ExitCode = $status }
}

function Read-Number {
    param([string]$Prompt, [int]$Maximum)
    while ($true) {
        Stop-IfCancelled
        $answer = Read-Host $Prompt
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Maximum) { return $number }
        Write-Host "Invalid choice. Enter a number from 1 to $Maximum." -ForegroundColor $script:Red
    }
}

function Clear-MenuScreen {
    if (-not [Console]::IsOutputRedirected) { Clear-Host }
}

function Get-ProfileNames {
    $namedProfiles = @(Get-ChildItem -LiteralPath $script:ConfigRoot -Directory | Where-Object {
        $_.Name -ine 'full' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'extensions.txt') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'settings.json') -PathType Leaf)
    } | Sort-Object Name | ForEach-Object { $_.Name })
    return @('full') + $namedProfiles
}

function Assert-LocalRepository {
    if ((Get-Variable PSSenderInfo -ErrorAction SilentlyContinue) -or $env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
        throw 'Update profiles is available only from a local PowerShell session.'
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    $gitExecutable = if ($git) { if ($git.Source) { $git.Source } else { $git.Name } } else { $null }
    if (-not $gitExecutable) {
        $gitCandidates = @(
            (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
        )
        $gitExecutable = $gitCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if (-not $gitExecutable) { throw 'Update profiles requires a local Git clone with a configured remote.' }
    $repositoryRoot = @(& $gitExecutable -C $script:ScriptDirectory rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRoot.Count -eq 0) { throw 'Update profiles requires a local Git clone with a configured remote.' }
    $repositoryRoot = (Resolve-Path -LiteralPath $repositoryRoot[0]).Path
    if ($repositoryRoot -ine (Resolve-Path -LiteralPath $script:ScriptDirectory).Path) { throw 'Update profiles must be run from the root of the cloned project.' }
    $remotes = @(& $gitExecutable -C $script:ScriptDirectory remote -v 2>$null | Where-Object { "$($_)".Trim() })
    if ($LASTEXITCODE -ne 0 -or $remotes.Count -eq 0) { throw 'Update profiles requires a configured Git remote.' }
}

function Read-NewProfileName {
    while ($true) {
        $name = Read-Host 'New profile name (letters, numbers, - and _)'
        if ($null -eq $name) { throw [System.OperationCanceledException]::new('Cancelled by user.') }
        if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            Write-Host 'Use a name starting with a letter or number, followed by letters, numbers, - or _.' -ForegroundColor $script:Red
            continue
        }
        if ($name -ieq 'full') {
            Write-Host 'The name "full" is reserved for the default profile.' -ForegroundColor $script:Red
            continue
        }
        $duplicate = @(Get-ChildItem -LiteralPath $script:ConfigRoot -Directory | Where-Object { $_.Name -ieq $name }).Count -gt 0
        if ($duplicate -or (Test-Path -LiteralPath (Join-Path $script:ConfigRoot $name))) {
            Write-Host "Profile '$name' already exists." -ForegroundColor $script:Red
            continue
        }
        return $name
    }
}

function Save-CurrentProfile {
    param([string]$ProfileName, [switch]$Create)
    $settingsSource = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (-not (Test-Path -LiteralPath $settingsSource -PathType Leaf)) { throw "VS Code settings not found: $settingsSource" }

    $targetDirectory = if ($ProfileName -ieq 'full') { $script:ConfigRoot } else { Join-Path $script:ConfigRoot $ProfileName }
    if ($Create) {
        if ($ProfileName -ieq 'full' -or (Test-Path -LiteralPath $targetDirectory)) { throw "Profile '$ProfileName' already exists." }
    } else {
        foreach ($file in @('extensions.txt', 'settings.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $targetDirectory $file) -PathType Leaf)) { throw "Profile '$ProfileName' is missing $file." }
        }
    }

    $tempDirectory = Join-Path $script:ConfigRoot ('.profile-' + [guid]::NewGuid().ToString('N'))
    $targetCreated = $false
    $backupsReady = $false
    try {
        New-Item -ItemType Directory -Path $tempDirectory -ErrorAction Stop | Out-Null
        $tempExtensions = Join-Path $tempDirectory 'extensions.txt'
        $tempSettings = Join-Path $tempDirectory 'settings.json'
        $backupExtensions = Join-Path $tempDirectory 'extensions.bak'
        $backupSettings = Join-Path $tempDirectory 'settings.bak'

        $installed = @(& $script:CodeCli --list-extensions 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Failed to read installed extensions: $($installed -join ' ')" }
        $profileExtensions = @($installed | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$' } | Sort-Object -Unique)
        if ($profileExtensions.Count -gt 0) { $profileExtensions | Set-Content -LiteralPath $tempExtensions -Encoding utf8 }
        else { New-Item -ItemType File -Path $tempExtensions -ErrorAction Stop | Out-Null }
        Copy-Item -LiteralPath $settingsSource -Destination $tempSettings -ErrorAction Stop

        if ($Create) {
            New-Item -ItemType Directory -Path $targetDirectory -ErrorAction Stop | Out-Null
            $targetCreated = $true
        } else {
            Copy-Item -LiteralPath (Join-Path $targetDirectory 'extensions.txt') -Destination $backupExtensions -ErrorAction Stop
            Copy-Item -LiteralPath (Join-Path $targetDirectory 'settings.json') -Destination $backupSettings -ErrorAction Stop
            $backupsReady = $true
        }

        Move-Item -LiteralPath $tempExtensions -Destination (Join-Path $targetDirectory 'extensions.txt') -Force -ErrorAction Stop
        Move-Item -LiteralPath $tempSettings -Destination (Join-Path $targetDirectory 'settings.json') -Force -ErrorAction Stop
    } catch {
        $saveError = $_.Exception.Message
        try {
            if ($targetCreated) {
                Remove-Item -LiteralPath (Join-Path $targetDirectory 'extensions.txt'), (Join-Path $targetDirectory 'settings.json') -Force -ErrorAction SilentlyContinue
                if (@(Get-ChildItem -LiteralPath $targetDirectory -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $targetDirectory -Force -ErrorAction SilentlyContinue }
            } elseif ($backupsReady) {
                Copy-Item -LiteralPath $backupExtensions -Destination (Join-Path $targetDirectory 'extensions.txt') -Force -ErrorAction Stop
                Copy-Item -LiteralPath $backupSettings -Destination (Join-Path $targetDirectory 'settings.json') -Force -ErrorAction Stop
            }
        } catch { $saveError += " Rollback failed: $($_.Exception.Message)" }
        throw "Could not save profile '$ProfileName': $saveError"
    } finally {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    $verb = if ($Create) { 'Created' } else { 'Updated' }
    Write-Host "$verb profile '$ProfileName' with current extensions and settings." -ForegroundColor $script:Green
}

function Update-Profiles {
    Assert-LocalRepository
    Write-Host "`n-------------------- Update profiles -------------------" -ForegroundColor $script:Cyan
    Write-Host '  [1] Create new profile'
    Write-Host '  [2] Update profile'
    Write-Host '  [3] Update default'
    $action = Read-Number 'Select action [1-3]' 3
    Clear-MenuScreen

    switch ($action) {
        1 {
            $name = Read-NewProfileName
            Save-CurrentProfile -ProfileName $name -Create
        }
        2 {
            $profiles = Get-ProfileNames
            Write-Host "`n------------------ Available profiles -----------------" -ForegroundColor $script:Cyan
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                $label = if ($profiles[$i] -ieq 'full') { 'full (default)' } else { $profiles[$i] }
                Write-Host ('  {0}. {1}' -f ($i + 1), $label)
            }
            $profileIndex = Read-Number "Select profile [1-$($profiles.Count)]" $profiles.Count
            Clear-MenuScreen
            Save-CurrentProfile -ProfileName $profiles[$profileIndex - 1]
        }
        3 { Save-CurrentProfile -ProfileName 'full' }
    }
}

function Remove-AllExtensions {
    Write-Host "`nREMOVE  Installed extensions" -ForegroundColor $script:Yellow
    $pass = 0
    $waitShown = $false
    $retryShown = $false
    $removalErrors = @{}
    while ($true) {
        Stop-IfCancelled
        $result = Invoke-CodeCapture -Arguments @('--list-extensions')
        $listing = $result.Output
        if ($result.ExitCode -ne 0) { throw "Could not list installed extensions: $($listing -join ' ')" }
        $current = @($listing | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
        if ($current.Count -eq 0) { break }
        $previous = @($current | Sort-Object) -join "`n"

        for ($i = 0; $i -lt $current.Count; $i++) {
            Write-Host ('  {0} Removing [{1}/{2}] {3}' -f [char]0x2022, ($i + 1), $current.Count, $current[$i]) -ForegroundColor $script:Yellow
        }
        $batchOrder = @($current)
        [array]::Reverse($batchOrder)
        $batchArguments = @()
        foreach ($extension in $batchOrder) { $batchArguments += @('--uninstall-extension', $extension) }
        if ($script:DebugOutput) { Write-Host "DEBUG: $($script:CodeCli) $($batchArguments -join ' ')" -ForegroundColor $script:Gray }
        if (-not $waitShown) {
            Write-Host "  $([char]0x2022) Waiting for VS Code..." -ForegroundColor $script:Cyan
            $waitShown = $true
        }
        $batchResult = Invoke-CodeCapture -Arguments $batchArguments
        if ($script:DebugOutput) { foreach ($line in $batchResult.Output) { if ("$line".Trim()) { Write-Host "  $line" -ForegroundColor $script:Gray } } }

        $result = Invoke-CodeCapture -Arguments @('--list-extensions')
        $listing = $result.Output
        if ($result.ExitCode -ne 0) { throw "Could not verify extension removal: $($listing -join ' ')" }
        $current = @($listing | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
        if ($current.Count -eq 0) { break }
        if ($previous -ne (@($current | Sort-Object) -join "`n")) {
            $pass++
            if ($pass -ge 100) { throw 'Stopped after too many removal passes.' }
            continue
        }

        if (-not $retryShown) {
            Write-Host "  $([char]0x2022) Retrying dependency-blocked removals..." -ForegroundColor $script:Cyan
            $retryShown = $true
        }
        foreach ($extension in $current) {
            Stop-IfCancelled
            if ($script:DebugOutput) { Write-Host "DEBUG: $($script:CodeCli) --uninstall-extension $extension" -ForegroundColor $script:Gray }
            $result = Invoke-CodeCapture -Arguments @('--uninstall-extension', $extension)
            $output = $result.Output
            $status = $result.ExitCode
            if ($status -ne 0) {
                $result = Invoke-CodeCapture -Arguments @('--list-extensions')
                $listing = $result.Output
                if ($result.ExitCode -ne 0) { throw "Could not check whether $extension remains installed: $($listing -join ' ')" }
                $current = @($listing | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
                if ($current -contains $extension) {
                    $removalErrors[$extension] = if ($output.Count) { $output -join [Environment]::NewLine } else { "VS Code CLI exited with status $status." }
                    continue
                }
                Write-Host "  $([char]0x2022) Already removed: $extension" -ForegroundColor $script:Green
                if ($script:DebugOutput) { foreach ($line in $output) { if ("$line".Trim()) { Write-Host "  $line" -ForegroundColor $script:Gray } } }
            } elseif ($script:DebugOutput) {
                foreach ($line in $output) { if ("$line".Trim()) { Write-Host "  $line" -ForegroundColor $script:Gray } }
            }
        }
        $result = Invoke-CodeCapture -Arguments @('--list-extensions')
        $listing = $result.Output
        if ($result.ExitCode -ne 0) { throw "Could not verify extension removal: $($listing -join ' ')" }
        $current = @($listing | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
        if ($current.Count -eq 0) { break }
        if ($previous -eq (@($current | Sort-Object) -join "`n")) {
            foreach ($extension in $current) {
                Write-Host "Unable to remove ${extension}:" -ForegroundColor $script:Red
                if ($removalErrors.ContainsKey($extension)) { Write-Host $removalErrors[$extension] -ForegroundColor $script:Red }
                else { Write-Host 'VS Code left this extension installed without returning an error.' -ForegroundColor $script:Red }
            }
            throw "Extensions remain installed: $($current -join ', ')"
        }
        $pass++
        if ($pass -ge 100) { throw 'Stopped after too many removal passes.' }
    }
    Write-Host 'All extensions removed.' -ForegroundColor $script:Green
}

function Install-Profile {
    param([switch]$ApplySettings)
    $extensions = @(Get-Content -LiteralPath (Join-Path $script:ConfigDirectory 'extensions.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    Write-Host "`nINSTALL  Profile '$script:Profile'  |  $($extensions.Count) extensions" -ForegroundColor $script:Cyan
    for ($i = 0; $i -lt $extensions.Count; $i++) {
        Stop-IfCancelled
        $extension = $extensions[$i]
        Write-Host ('  {0} Installing [{1}/{2}] {3}' -f [char]0x2022, ($i + 1), $extensions.Count, $extension) -ForegroundColor $Green
    }
    $arguments = @()
    foreach ($extension in $extensions) { $arguments += @('--install-extension', $extension) }
    if ($arguments.Count -gt 0) {
        if ($script:DebugOutput) { Write-Host "DEBUG: $($script:CodeCli) $($arguments -join ' ')" -ForegroundColor $script:Gray }
        Write-Host "  $([char]0x2022) Waiting for VS Code..." -ForegroundColor $script:Cyan
        $status = Invoke-CodeCli -Arguments $arguments
        if ($status -ne 0) { throw "Failed to install profile '$script:Profile'. VS Code reported one or more extension failures." }
    }
    if ($ApplySettings) {
        $userDirectory = Join-Path $env:APPDATA 'Code\User'
        New-Item -ItemType Directory -Force -Path $userDirectory | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ConfigDirectory 'settings.json') -Destination (Join-Path $userDirectory 'settings.json') -Force
        Write-Host "Profile '$script:Profile' installed successfully with settings." -ForegroundColor $script:Green
    } else {
        Write-Host "Profile '$script:Profile' installed successfully. Settings were left unchanged." -ForegroundColor $script:Green
    }
}

function Restore-ResetAclInheritance {
    param([string]$LiteralPath, [System.Security.Principal.SecurityIdentifier]$UserSid)
    $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }

    $acl = Get-Acl -LiteralPath $LiteralPath -ErrorAction Stop
    $hasUserFullControl = @($acl.Access | Where-Object {
        $_.IdentityReference.Value -eq $UserSid.Value -and
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
        (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl)
    }).Count -gt 0
    if ($acl.AreAccessRulesProtected -and -not $hasUserFullControl) {
        $acl.SetAccessRuleProtection($false, $true)
        Set-Acl -LiteralPath $LiteralPath -AclObject $acl -ErrorAction Stop
    }

    if ($item.PSIsContainer) {
        $children = @(Get-ChildItem -LiteralPath $LiteralPath -Force -ErrorAction Stop)
        foreach ($child in $children) { Restore-ResetAclInheritance -LiteralPath $child.FullName -UserSid $UserSid }
    }
}

function Reset-VSCode {
    $portableData = if ($script:CodeRoot) { Join-Path $script:CodeRoot 'data' } else { $null }
    if ($portableData -and (Test-Path -LiteralPath $portableData -PathType Container)) {
        $targets = @((Join-Path $portableData 'user-data'), (Join-Path $portableData 'extensions'))
    } else {
        $targets = @((Join-Path $env:APPDATA 'Code'), (Join-Path $env:USERPROFILE '.vscode\extensions'))
    }
    $existingTargets = @($targets | Where-Object { Test-Path -LiteralPath $_ })
    if ($existingTargets.Count -eq 0) {
        Write-Host 'VS Code already has no user data to reset.' -ForegroundColor $script:Yellow
        return
    }
    $activeCodeProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @('Code', 'Code - Insiders', 'code-insiders') -or
        ($script:CodeRoot -and $_.Path -and $_.Path.StartsWith($script:CodeRoot, [StringComparison]::OrdinalIgnoreCase))
    })
    if ($activeCodeProcesses.Count -gt 0) { throw "Close all VS Code windows, including the one hosting this terminal, and wait for extension helper processes to exit before resetting user data. Run configure.ps1 from an external terminal. Running PIDs: $(($activeCodeProcesses.Id | Sort-Object -Unique) -join ', ')" }

    Write-Host "`nThis will delete VS Code settings, profiles, extension data, workspace state, and cached user data:" -ForegroundColor $script:Yellow
    foreach ($target in $existingTargets) { Write-Host "  $target" }
    Write-Host 'VS Code itself and your project files will remain.' -ForegroundColor $script:Yellow
    $answer = Read-Host 'Type RESET to confirm'
    if ($answer -cne 'RESET') { Write-Host 'Reset cancelled.' -ForegroundColor $script:Yellow; return }

    foreach ($target in $existingTargets) {
        Stop-IfCancelled
        $item = Get-Item -LiteralPath $target -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing to remove redirected data directory: $target" }
        $removeError = $null
        $aclRepairAttempted = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                $removeError = $null
                break
            } catch {
                $removeError = $_.Exception.Message
                if (-not $aclRepairAttempted -and $_.Exception -is [UnauthorizedAccessException]) {
                    $aclRepairAttempted = $true
                    try {
                        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
                        Restore-ResetAclInheritance -LiteralPath $target -UserSid $currentSid
                    } catch {
                        $removeError += " ACL recovery failed: $($_.Exception.Message)"
                    }
                }
                if ($attempt -lt 3) { Start-Sleep -Milliseconds 500 }
            }
        }
        if ($removeError) { throw "Reset is incomplete. Close VS Code and Git askpass/helper processes, then run Reset again from an external terminal. Some data may already have been removed. Failed path: $target. $removeError" }
        Write-Host "Removed $target"
    }
    Write-Host 'VS Code user data reset completed.' -ForegroundColor $script:Green
}

try {
    if (-not (Test-Path -LiteralPath $ConfigRoot -PathType Container)) { throw "Config directory not found: $ConfigRoot" }
    if ($PSBoundParameters.ContainsKey('Path')) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "VS Code directory does not exist: $Path" }
        $CodeRoot = (Resolve-Path -LiteralPath $Path).Path
        $candidates = @((Join-Path $Path 'bin\code.cmd'), (Join-Path $Path 'bin\code.exe'))
        $CodeCli = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $CodeCli) { throw "No VS Code CLI found in '$Path' (expected bin\code.cmd or bin\code.exe)." }
    } else {
        $command = Get-Command code -ErrorAction SilentlyContinue
        if (-not $command) { throw 'VS Code CLI "code" was not found on PATH.' }
        $CodeCli = $command.Source
        $CodeDirectory = Split-Path -Parent $CodeCli
        $CodeRoot = if ((Split-Path -Leaf $CodeDirectory) -ieq 'bin') { Split-Path -Parent $CodeDirectory } else { $CodeDirectory }
        if ([IO.Path]::GetFileName($CodeCli) -ieq 'Code.exe') {
            $cliDirectory = if ((Split-Path -Leaf $CodeDirectory) -ieq 'bin') { $CodeDirectory } else { Join-Path $CodeDirectory 'bin' }
            $cliWrapper = Join-Path $cliDirectory 'code.cmd'
            if (Test-Path -LiteralPath $cliWrapper -PathType Leaf) { $CodeCli = $cliWrapper }
            else { throw "The command 'code' resolved to the VS Code application, not its CLI. Add '$cliDirectory' to PATH or pass the VS Code installation directory with -p." }
        }
    }
    if ($DebugOutput) { Write-Host "DEBUG: VS Code CLI: $CodeCli" -ForegroundColor $Gray }
    $script:CodeCli = $CodeCli
    $script:CodeRoot = $CodeRoot
    $script:DebugOutput = [bool]$DebugOutput
    $script:Red = $Red; $script:Gray = $Gray; $script:Green = $Green; $script:Yellow = $Yellow; $script:Cyan = $Cyan

    $profiles = Get-ProfileNames
    Write-Host "`n---------------- VS Code Configuration ----------------" -ForegroundColor $Cyan
    Write-Host '  INSTALL' -ForegroundColor $Green
    Write-Host '  [1] Clean install  (remove extensions, then install profile)'
    Write-Host '  [2] Install profile'
    Write-Host ''
    Write-Host '  REMOVE' -ForegroundColor $Yellow
    Write-Host '  [3] Delete all extensions'
    Write-Host '  [4] Reset VS Code user data'
    Write-Host ''
    Write-Host '  OTHER' -ForegroundColor $Cyan
    Write-Host '  [5] Update profiles'
    Write-Host '--------------------------------------------------------' -ForegroundColor $Cyan
    $operation = Read-Number 'Select operation [1-5]' 5
    Clear-MenuScreen

    $Profile = 'full'
    if ($operation -eq 1 -or $operation -eq 2) {
        Write-Host "`n------------------ Available profiles -----------------" -ForegroundColor $Cyan
        for ($i = 0; $i -lt $profiles.Count; $i++) { Write-Host ('  {0}. {1}' -f ($i + 1), $profiles[$i]) }
        $profileIndex = Read-Number "Select profile [1-$($profiles.Count)]" $profiles.Count
        $Profile = $profiles[$profileIndex - 1]
        Clear-MenuScreen
        $ConfigDirectory = if ($Profile -eq 'full') { $ConfigRoot } else { Join-Path $ConfigRoot $Profile }
        foreach ($file in @('extensions.txt', 'settings.json')) { if (-not (Test-Path -LiteralPath (Join-Path $ConfigDirectory $file) -PathType Leaf)) { throw "Profile '$Profile' is missing $file." } }
    }
    $script:Profile = $Profile
    $script:ConfigDirectory = $ConfigDirectory

    switch ($operation) {
        1 { Remove-AllExtensions; Install-Profile -ApplySettings }
        2 { Install-Profile }
        3 { Remove-AllExtensions }
        4 { Reset-VSCode }
        5 { Update-Profiles }
    }
} catch [System.OperationCanceledException] {
    Write-Host "`nCancelled. No success was reported." -ForegroundColor $Yellow
    exit 130
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor $Red
    exit 1
} finally {
    [Console]::remove_CancelKeyPress($CancelHandler)
}
