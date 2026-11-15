#!/usr/bin/env bash
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
for file in "$config_dir/extensions.txt" "$config_dir/settings.json"; do
    if [[ ! -f "$file" ]]; then
        printf 'Required config file was not found: %s\n' "$file" >&2
        exit 1
    fi
done

installed_extensions="$(code --list-extensions)"
while IFS= read -r extension; do
    [[ -z "$extension" ]] && continue
    printf 'Removing %s\n' "$extension"
    code --uninstall-extension "$extension"
done <<< "$installed_extensions"

user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
rm -f -- "$user_dir/settings.json"
bash "$script_dir/install.sh" "$config_name"

printf 'Clean VS Code installation completed.\n'
