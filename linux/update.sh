#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'This script requires Bash. Run it with: bash linux/update.sh [profile]\n' >&2
    exit 2
fi

set -euo pipefail

config_name="${1:-full}"
if [[ ! "$config_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf 'Invalid config name: %s\nUse only letters, numbers, underscores, and hyphens.\n' "$config_name" >&2
    exit 1
fi

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
if [[ "$config_name" != full ]]; then
    config_dir="$config_dir/$config_name"
fi
settings_source="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"

if [[ ! -f "$settings_source" ]]; then
    printf 'VS Code settings file was not found: %s\n' "$settings_source" >&2
    exit 1
fi

mkdir -p -- "$config_dir"
code --list-extensions | LC_ALL=C sort -u > "$config_dir/extensions.txt"
cp -- "$settings_source" "$config_dir/settings.json"

printf 'Updated %s/extensions.txt and copied settings to %s/settings.json.\n' "$config_dir" "$config_dir"
printf 'Review and commit these changes to publish them to GitHub.\n'
