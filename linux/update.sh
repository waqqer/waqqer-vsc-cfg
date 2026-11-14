#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux* ]]; then
    printf 'This script supports Linux only.\n' >&2
    exit 1
fi

if ! command -v code >/dev/null 2>&1; then
    printf 'VS Code CLI "code" was not found. Install VS Code and ensure its bin directory is on PATH.\n' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$script_dir/../config"
settings_source="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"

if [[ ! -f "$settings_source" ]]; then
    printf 'VS Code settings file was not found: %s\n' "$settings_source" >&2
    exit 1
fi

mkdir -p -- "$config_dir"
code --list-extensions | LC_ALL=C sort -u > "$config_dir/extensions.txt"
cp -- "$settings_source" "$config_dir/settings.json"

printf 'Updated config/extensions.txt and copied settings to config/settings.json.\n'
printf 'Review and commit these changes to publish them to GitHub.\n'
