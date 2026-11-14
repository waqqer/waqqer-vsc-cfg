#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux* ]]; then
    printf 'This installer supports Linux only.\n' >&2
    exit 1
fi

if ! command -v code >/dev/null 2>&1; then
    printf 'VS Code CLI "code" was not found. Install VS Code and ensure its bin directory is on PATH.\n' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for file in "$script_dir/../config/extensions.txt" "$script_dir/../config/settings.json"; do
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
bash "$script_dir/install.sh"

printf 'Clean VS Code installation completed.\n'
