## Windows Installation

Install the full profile (the default):

```powershell
irm https://raw.githubusercontent.com/waqqer/waqqer-vsc-cfg/main/win/install.ps1 | iex
```

Install a named profile such as `lite`:

```powershell
irm https://raw.githubusercontent.com/waqqer/waqqer-vsc-cfg/main/win/install.ps1 -Config lite
```

Clean install removes all installed VS Code extensions and replaces the user settings file. To clean install `lite`, pass `-Config lite`:

```powershell
irm https://raw.githubusercontent.com/waqqer/waqqer-vsc-cfg/main/win/clean_install.ps1 -Config lite
```

To save the current VS Code setup into a profile, run `win/update.ps1 -Config lite` from the cloned repository. Omit `-Config` to update the full profile.

## Linux Installation

The VS Code `code` command must be available on `PATH`. Clone the repository and install the full profile (the default):

```bash
git clone https://github.com/waqqer/waqqer-vsc-cfg.git
cd waqqer-vsc-cfg
bash linux/install.sh
```

Install a named profile such as `lite` by passing its name:

```bash
bash linux/install.sh lite
```

The installer copies settings to `${XDG_CONFIG_HOME:-~/.config}/Code/User/settings.json`.

Clean install removes all installed VS Code extensions and replaces the user settings file. Pass the profile name to clean install that profile:

```bash
bash linux/clean_install.sh lite
```

To save the current VS Code setup into a profile, run `bash linux/update.sh lite`. Omit the profile name to update the full profile.

### Adding profiles

Create a directory under `config/` for each profile, containing `extensions.txt` and `settings.json`. Use the directory name as the `-Config` value on Windows or as the argument on Linux. Profile names may contain letters, numbers, underscores, and hyphens. The `full` profile uses the files directly in `config/`.
