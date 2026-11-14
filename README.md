## Windows Installation

Install VS Code extensions and settings:

```powershell
irm https://raw.githubusercontent.com/waqqer/waqqer-vsc-cfg/main/win/install.ps1 | iex
```

Clean install (removes all installed VS Code extensions and replaces the user settings file):

```powershell
irm https://raw.githubusercontent.com/waqqer/waqqer-vsc-cfg/main/win/clean_install.ps1 | iex
```

## Linux Installation

Install VS Code extensions and settings. The `code` command must be available on `PATH`.

```bash
git clone https://github.com/waqqer/waqqer-vsc-cfg.git
cd waqqer-vsc-cfg
bash linux/install.sh
```

The installer copies settings to `${XDG_CONFIG_HOME:-~/.config}/Code/User/settings.json`.

Clean install (removes all installed VS Code extensions and replaces the user settings file):

```bash
bash linux/clean_install.sh
```

To update the repository configuration from your current VS Code setup:

```bash
bash linux/update.sh
```
