#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'This script requires Bash. Run it with: bash linux/install.sh [profile]\n' >&2
    exit 2
fi

set -euo pipefail

config_name="${1:-full}"
if [[ ! "$config_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf 'Invalid config name: %s\nUse only letters, numbers, underscores, and hyphens.\n' "$config_name" >&2
    exit 1
fi

if [[ "$(uname -s)" != Linux* ]]; then
    printf 'This installer supports Linux only.\n' >&2
    exit 1
fi

if ! command -v code >/dev/null 2>&1; then
    printf 'VS Code CLI "code" was not found. Install VS Code and ensure its bin directory is on PATH.\n' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$script_dir/../config"
if [[ "$config_name" != full ]]; then
    config_dir="$config_dir/$config_name"
fi
extensions_file="$config_dir/extensions.txt"
settings_file="$config_dir/settings.json"

for file in "$extensions_file" "$settings_file"; do
    if [[ ! -f "$file" ]]; then
        printf 'Required config file was not found: %s\n' "$file" >&2
        exit 1
    fi
done

while IFS= read -r extension || [[ -n "$extension" ]]; do
    extension="${extension%$'\r'}"
    [[ -z "$extension" || "$extension" == \#* ]] && continue
    printf 'Installing %s\n' "$extension"
    if ! code --install-extension "$extension"; then
        printf 'Failed to install extension "%s". Check the extension ID, Marketplace access, and that "code" is the official VS Code CLI.\n' "$extension" >&2
        exit 1
    fi
done < "$extensions_file"

user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
mkdir -p -- "$user_dir"
cp -- "$settings_file" "$user_dir/settings.json"

printf 'VS Code extensions and user settings have been installed.\n'
