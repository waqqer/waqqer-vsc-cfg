# VS Code configuration

Sync your VS Code extensions and user settings across Windows computers.

## Install on a Windows computer

1. Create a GitHub repository and upload these files.
2. In `install.ps1`, replace `USERNAME/vscode-config` with your GitHub username and repository name.
3. Run this command in PowerShell, replacing `USERNAME` and `vscode-config` if needed:

```powershell
irm https://raw.githubusercontent.com/USERNAME/vscode-config/main/install.ps1 | iex
```

The installer downloads `extensions.txt` and `settings.json`, installs the listed extensions, and copies the settings file to the current Windows user's VS Code profile. It replaces that profile's existing `settings.json`.

## Update the repository from this computer

After installing or removing extensions, or changing VS Code settings, open PowerShell in the local repository folder and run:

```powershell
.\update.ps1
```

This updates the local repository's `extensions.txt` and `settings.json` from this computer's VS Code setup. It does not change VS Code settings, contact GitHub, or upload anything. Review the changes, then commit and push them to publish the update:

```powershell
git add extensions.txt settings.json
git commit -m "Update VS Code configuration"
git push
```

## Public repository and safety

Anyone can read and clone a public repository. If someone runs `update.ps1` in their own clone, it changes only the files in their clone; it does not erase or replace your files on GitHub. They cannot push changes to your repository unless you grant them write access. You publish your own updates only when you push them.

Review `settings.json` before making the repository public. Settings can contain private paths, URLs, or tokens. The current settings file includes a background image URL with a token query parameter; remove or replace that URL before publishing if the token is private or should not be shared.
