#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf 'This script requires Bash. Run it with: bash linux/clean_install.sh [profile]\n' >&2
    exit 2
fi

set -euo pipefail

if [[ -t 1 ]]; then
    color_green=$'\033[32m'; color_yellow=$'\033[33m'; color_gray=$'\033[90m'; color_red=$'\033[31m'; color_reset=$'\033[0m'
else
    color_green=''; color_yellow=''; color_gray=''; color_red=''; color_reset=''
fi

config_name=full
debug=false
config_set=false
for argument in "$@"; do
    case "$argument" in
        -d|--debug) debug=true ;;
        *)
            if [[ "$config_set" == true || ! "$argument" =~ ^[A-Za-z0-9_-]+$ ]]; then
                printf 'Usage: bash linux/clean_install.sh [profile] [-d|--debug]\n' >&2
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
for file in "$config_dir/extensions.txt" "$config_dir/settings.json"; do
    if [[ ! -f "$file" ]]; then
        printf 'Required config file was not found: %s\n' "$file" >&2
        exit 1
    fi
done

if [[ "$debug" == true ]]; then printf '%sDEBUG%s code --list-extensions\n' "$color_gray" "$color_reset"; fi
installed_extensions="$(code --list-extensions)"
pending_extensions=()
if [[ -n "$installed_extensions" ]]; then
    mapfile -t pending_extensions <<< "$installed_extensions"
fi
while ((${#pending_extensions[@]} > 0)); do
    previous_pass=("${pending_extensions[@]}")

    for extension in "${pending_extensions[@]}"; do
        [[ -z "$extension" ]] && continue
        printf '\n%sRemove extension %s%s\n' "$color_red" "$extension" "$color_reset"
        if [[ "$debug" == true ]]; then
            printf '%sDEBUG%s code --uninstall-extension %s\n' "$color_gray" "$color_reset" "$extension"
            code --uninstall-extension "$extension" || true
        else
            output="$(code --uninstall-extension "$extension" 2>&1)" || true
        fi
    done

if [[ "$debug" == true ]]; then printf '%sDEBUG%s refreshing installed extension list\n' "$color_gray" "$color_reset"; fi
    installed_extensions="$(code --list-extensions)"
    pending_extensions=()
    if [[ -n "$installed_extensions" ]]; then
        mapfile -t pending_extensions <<< "$installed_extensions"
    fi
    if ((${#pending_extensions[@]} > 0)) && [[ "$(printf '%s\n' "${previous_pass[@]}" | LC_ALL=C sort)" == "$(printf '%s\n' "${pending_extensions[@]}" | LC_ALL=C sort)" ]]; then
        printf '%sUnable to remove remaining extensions: %s%s\n' "$color_red" "${pending_extensions[*]}" "$color_reset" >&2
        exit 1
    fi
done

user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
printf '\n%sApplying profile "%s"%s\n' "$color_yellow" "$config_name" "$color_reset"
rm -f -- "$user_dir/settings.json"
install_args=("$config_name")
if [[ "$debug" == true ]]; then install_args+=(-d); fi
bash "$script_dir/install.sh" "${install_args[@]}"

printf '%sClean VS Code installation completed.%s\n' "$color_green" "$color_reset"
