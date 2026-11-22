# VS Code configuration

Interactive setup tool for installing, removing, and updating VS Code extension profiles on Windows and Linux.

## Start

Run the entry point for your operating system from this repository:

```powershell
.\configure.ps1
```

```bash
./configure.sh
```

The menu offers clean install, install a profile, delete all extensions, reset VS Code user data, and profile management. Profiles are read from `config/`: `full` uses the files directly in that directory; named profiles use subdirectories such as `config/lite/`.

Clean install applies both the selected extensions and `settings.json`. Install adds the selected extensions and leaves the current user settings unchanged.

Reset VS Code removes the standard user data and extension directories, or the portable installation's `data/user-data` and `data/extensions` directories. It requires typing `RESET` to confirm, and leaves the VS Code application and project files in place. Close VS Code and run the reset from an external terminal.

## Options

`-d` prints VS Code CLI details while installing or removing extensions:

```powershell
.\configure.ps1 -d
```

```bash
./configure.sh -d
```

`-p` selects a VS Code installation directory instead of using `code` from `PATH`. Combine it with `-d` as needed:

```powershell
.\configure.ps1 -p "D:\Programs\Microsoft VS Code" -d
```

```bash
./configure.sh -p "/opt/vscode" -d
```

Windows paths must contain `Code.exe` or `bin\code.cmd`; Linux paths must contain an executable `bin/code` or `code`.

## Profiles

Each profile contains `extensions.txt` and `settings.json`. Add a directory under `config/` with those files to make another profile available in the menu. The `full` profile uses `config/extensions.txt` and `config/settings.json`.
Each profile contains `extensions.txt` and `settings.json`. Add a directory under `config/` with those files to make another profile available in the menu. The `full` profile uses `config/extensions.txt` and `config/settings.json`.