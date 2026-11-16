#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'This script requires Bash. Run it with: bash linux/install.sh [profile]\n' >&2
    exit 2
fi

set -euo pipefail

if [[ -t 1 ]]; then
    color_green=$'\033[32m'; color_gray=$'\033[90m'; color_red=$'\033[31m'; color_reset=$'\033[0m'
else
    color_green=''; color_gray=''; color_red=''; color_reset=''
fi

config_name=full
debug=false
config_set=false
for argument in "$@"; do
    case "$argument" in
        -d|--debug) debug=true ;;
        *)
            if [[ "$config_set" == true || ! "$argument" =~ ^[A-Za-z0-9_-]+$ ]]; then
                printf 'Usage: bash linux/install.sh [profile] [-d|--debug]\n' >&2
                exit 1
            fi
            config_name="$argument"
            config_set=true
            ;;
    esac
done

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

if [[ "$debug" == true ]]; then
    printf '%sDEBUG%s profile=%s config=%s\n' "$color_gray" "$color_reset" "$config_name" "$config_dir"
    printf '%sDEBUG%s CLI=%s\n' "$color_gray" "$color_reset" "$(command -v code)"
fi

extensions=()
while IFS= read -r extension || [[ -n "$extension" ]]; do
    extension="${extension%$'\r'}"
    [[ -z "$extension" || "$extension" == \#* ]] && continue
    extensions+=("$extension")
done < "$extensions_file"

for extension in "${extensions[@]}"; do
    printf '\n%sInstall extension %s%s\n' "$color_green" "$extension" "$color_reset"
    if [[ "$debug" == true ]]; then
        printf '%sDEBUG%s code --install-extension %s\n' "$color_gray" "$color_reset" "$extension"
        if ! code --install-extension "$extension"; then
            printf '%sFailed to install extension "%s".%s\n' "$color_red" "$extension" "$color_reset" >&2
            exit 1
        fi
    else
        if output="$(code --install-extension "$extension" 2>&1)"; then
            :
        else
            status=$?
            printf '%sFailed to install extension "%s":%s\n%s\n' "$color_red" "$extension" "$color_reset" "$output" >&2
            exit "$status"
        fi
    fi
done

user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
mkdir -p -- "$user_dir"
cp -- "$settings_file" "$user_dir/settings.json"
if [[ "$debug" == true ]]; then
    printf '%sDEBUG%s copied %s to %s/settings.json\n' "$color_gray" "$color_reset" "$settings_file" "$user_dir"
fi
printf '%s\n' "$color_green"

printf '%sVS Code profile "%s" installed successfully.%s\n' "$color_green" "$config_name" "$color_reset"
