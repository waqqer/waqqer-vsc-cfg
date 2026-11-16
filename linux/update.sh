#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'This script requires Bash. Run it with: bash linux/update.sh [profile]\n' >&2
    exit 2
fi

set -euo pipefail

if [[ -t 1 ]]; then
    color_green=$'\033[32m'; color_gray=$'\033[90m'; color_reset=$'\033[0m'
else
    color_green=''; color_gray=''; color_reset=''
fi

config_name=full
debug=false
config_set=false
for argument in "$@"; do
    case "$argument" in
        -d|--debug) debug=true ;;
        *)
            if [[ "$config_set" == true || ! "$argument" =~ ^[A-Za-z0-9_-]+$ ]]; then
                printf 'Usage: bash linux/update.sh [profile] [-d|--debug]\n' >&2
                exit 1
            fi
            config_name="$argument"
            config_set=true
            ;;
    esac
done

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
if [[ "$debug" == true ]]; then
    printf '%sDEBUG%s profile=%s settingsSource=%s config=%s\n' "$color_gray" "$color_reset" "$config_name" "$settings_source" "$config_dir"
    printf '%sDEBUG%s code --list-extensions | sort -u\n' "$color_gray" "$color_reset"
fi
code --list-extensions | LC_ALL=C sort -u > "$config_dir/extensions.txt"
cp -- "$settings_source" "$config_dir/settings.json"
if [[ "$debug" == true ]]; then printf '%sDEBUG%s copied settings.json\n' "$color_gray" "$color_reset"; fi

printf '%sUpdated profile "%s" with extensions and settings.%s\n' "$color_green" "$config_name" "$color_reset"
printf '%sReview and commit these changes to publish them to GitHub.%s\n' "$color_cyan" "$color_reset"
