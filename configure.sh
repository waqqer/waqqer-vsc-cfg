#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 ]]; then
    green=$'\033[32m'; yellow=$'\033[33m'; gray=$'\033[90m'; red=$'\033[31m'; cyan=$'\033[36m'; reset=$'\033[0m'
else
    green=''; yellow=''; gray=''; red=''; cyan=''; reset=''
fi

debug=false
custom_path=''
while (($#)); do
    case "$1" in
        -d|--debug) debug=true; shift ;;
        -p|--path)
            (($# >= 2)) || { printf '%sError:%s -p requires a VS Code directory.\n' "$red" "$reset" >&2; exit 2; }
            [[ -z "$custom_path" ]] || { printf '%sError:%s specify -p only once.\n' "$red" "$reset" >&2; exit 2; }
            custom_path=$2; shift 2 ;;
        -h|--help) printf 'Usage: ./configure.sh [-d] [-p <VS Code directory>]\n'; exit 0 ;;
        *) printf '%sError:%s unknown argument: %s\nUsage: ./configure.sh [-d] [-p <VS Code directory>]\n' "$red" "$reset" "$1" >&2; exit 2 ;;
    esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_root="$script_dir/config"
[[ -d "$config_root" ]] || { printf '%sError:%s config directory not found: %s\n' "$red" "$reset" "$config_root" >&2; exit 1; }

if [[ -n "$custom_path" ]]; then
    [[ -d "$custom_path" ]] || { printf '%sError:%s VS Code directory does not exist: %s\n' "$red" "$reset" "$custom_path" >&2; exit 1; }
    code_root="$(cd -- "$custom_path" && pwd)"
    if [[ -x "$custom_path/bin/code" ]]; then code_cli="$custom_path/bin/code"
    elif [[ -x "$custom_path/code" ]]; then code_cli="$custom_path/code"
    else printf '%sError:%s no executable VS Code CLI found in "%s" (expected bin/code or code).\n' "$red" "$reset" "$custom_path" >&2; exit 1
    fi
else
    code_cli="$(command -v code || true)"
    [[ -n "$code_cli" ]] || { printf '%sError:%s VS Code CLI "code" was not found on PATH.\n' "$red" "$reset" >&2; exit 1; }
    resolved_code="$(readlink -f -- "$code_cli" 2>/dev/null || printf '%s' "$code_cli")"
    code_directory="$(dirname -- "$resolved_code")"
    if [[ "${code_directory##*/}" == bin ]]; then code_root="$(cd -- "$code_directory/.." && pwd)"; else code_root="$code_directory"; fi
fi

if [[ "$debug" == true ]]; then printf '%sDEBUG%s VS Code CLI: %s\n' "$gray" "$reset" "$code_cli"; fi

profiles=(full)
while IFS= read -r -d '' dir; do
    name="${dir##*/}"
    [[ "${name,,}" != full && -f "$dir/extensions.txt" && -f "$dir/settings.json" ]] && profiles+=("$name")
done < <(find "$config_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

choose_number() {
    local prompt=$1 count=$2 answer
    while true; do
        if ! IFS= read -r -p "$prompt" answer; then printf '\n%sCancelled.%s\n' "$yellow" "$reset"; exit 130; fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && ((10#$answer >= 1 && 10#$answer <= count)); then
            REPLY=$((10#$answer)); return 0
        fi
        printf '%sInvalid choice.%s Enter a number from 1 to %d.\n' "$red" "$reset" "$count"
    done
}

clear_menu_screen() {
    if [[ -t 1 ]]; then printf '\033[2J\033[H'; fi
}

printf '\n%s---------------- VS Code Configuration ----------------%s\n' "$cyan" "$reset"
printf '  %sINSTALL%s\n  [1] Clean install  (remove extensions, then install profile)\n  [2] Install profile\n\n' "$green" "$reset"
printf '  %sREMOVE%s\n  [3] Delete all extensions\n  [4] Reset VS Code user data\n\n' "$yellow" "$reset"
printf '  %sOTHER%s\n  [5] Update profiles\n%s--------------------------------------------------------%s\n\n' "$cyan" "$reset" "$cyan" "$reset"
choose_number 'Select operation [1-5]: ' 5
operation=$REPLY
clear_menu_screen

profile='full'
if [[ "$operation" == 1 || "$operation" == 2 ]]; then
    printf '\n%s------------------ Available profiles -----------------%s\n' "$cyan" "$reset"
    for i in "${!profiles[@]}"; do printf '  %d. %s\n' "$((i+1))" "${profiles[$i]}"; done
    choose_number "Select profile [1-${#profiles[@]}]: " "${#profiles[@]}"
    profile=${profiles[$((REPLY-1))]}
    clear_menu_screen
    config_dir="$config_root"
    [[ "$profile" == full ]] || config_dir="$config_root/$profile"
    [[ -f "$config_dir/extensions.txt" && -f "$config_dir/settings.json" ]] || { printf '%sError:%s profile files are missing for "%s".\n' "$red" "$reset" "$profile" >&2; exit 1; }
fi

run_code() {
    local output status
    if output=$("$code_cli" "$@" 2>&1); then
        [[ "$debug" == true && -n "$output" ]] && printf '%s\n' "$output" | sed "s/^/${gray}  /;s/$/${reset}/"
        return 0
    else
        status=$?
        [[ -n "$output" ]] && printf '%s\n' "$output" >&2
        return "$status"
    fi
}

remove_all_extensions() {
    local listing previous ext pass=0 output status installed still_installed i wait_shown=false retry_shown=false
    local -A removal_errors=()
    local -a batch_args=()
    printf '\n%sREMOVE  Installed extensions%s\n' "$yellow" "$reset"
    while true; do
        if [[ "$debug" == true ]]; then printf '%sDEBUG%s code --list-extensions\n' "$gray" "$reset"; fi
        if ! listing=$("$code_cli" --list-extensions 2>&1); then printf '%sError:%s could not list VS Code extensions.\n%s\n' "$red" "$reset" "$listing" >&2; return 1; fi
        mapfile -t current < <(printf '%s\n' "$listing" | sed '/^[[:space:]]*$/d')
        ((${#current[@]})) || break
        previous=$(printf '%s\n' "${current[@]}" | LC_ALL=C sort)
        batch_args=()
        for ((i=0; i<${#current[@]}; i++)); do
            printf '  %s\u2022 Removing [%d/%d] %s%s\n' "$yellow" "$((i+1))" "${#current[@]}" "${current[$i]}" "$reset"
        done
        for ((i=${#current[@]}-1; i>=0; i--)); do
            batch_args+=(--uninstall-extension "${current[$i]}")
        done
        if [[ "$debug" == true ]]; then
            printf '%sDEBUG%s' "$gray" "$reset"
            printf ' %q' "$code_cli" "${batch_args[@]}"
            printf '\n'
        fi
        if [[ "$wait_shown" == false ]]; then
            printf '  %s\u2022 Waiting for VS Code...%s\n' "$cyan" "$reset"
            wait_shown=true
        fi
        if output=$("$code_cli" "${batch_args[@]}" 2>&1); then status=0; else status=$?; fi
        [[ "$debug" == true && -n "$output" ]] && printf '%s\n' "$output" | sed "s/^/${gray}  /;s/$/${reset}/"

        if ! listing=$("$code_cli" --list-extensions 2>&1); then printf '%sError:%s could not verify extension removal.\n%s\n' "$red" "$reset" "$listing" >&2; return 1; fi
        mapfile -t current < <(printf '%s\n' "$listing" | sed '/^[[:space:]]*$/d')
        ((${#current[@]})) || break
        if [[ "$previous" != "$(printf '%s\n' "${current[@]}" | LC_ALL=C sort)" ]]; then
            ((pass+=1))
            ((pass < 100)) || { printf '%sError:%s stopped after too many removal passes.\n' "$red" "$reset" >&2; return 1; }
            continue
        fi

        if [[ "$retry_shown" == false ]]; then
            printf '  %s\u2022 Retrying dependency-blocked removals...%s\n' "$cyan" "$reset"
            retry_shown=true
        fi
        for ext in "${current[@]}"; do
            if [[ "$debug" == true ]]; then printf '%sDEBUG%s code --uninstall-extension %s\n' "$gray" "$reset" "$ext"; fi
            if output=$("$code_cli" --uninstall-extension "$ext" 2>&1); then
                [[ "$debug" == true && -n "$output" ]] && printf '%s\n' "$output" | sed "s/^/${gray}  /;s/$/${reset}/"
            else
                status=$?
                if listing=$("$code_cli" --list-extensions 2>&1); then
                    mapfile -t current < <(printf '%s\n' "$listing" | sed '/^[[:space:]]*$/d')
                    still_installed=false
                    for installed in "${current[@]}"; do [[ "$installed" == "$ext" ]] && still_installed=true; done
                    if [[ "$still_installed" == false ]]; then
                        printf '  %s\u2022 Already removed: %s%s\n' "$green" "$ext" "$reset"
                        [[ "$debug" == true && -n "$output" ]] && printf '%s\n' "$output" | sed "s/^/${gray}  /;s/$/${reset}/"
                        continue
                    fi
                else
                    printf '%sError:%s could not check whether %s remains installed.\n%s\n' "$red" "$reset" "$ext" "$listing" >&2
                    return 1
                fi
                removal_errors["$ext"]="${output:-VS Code CLI exited with status $status}"
            fi
        done
        if ! listing=$("$code_cli" --list-extensions 2>&1); then printf '%sError:%s could not verify extension removal.\n%s\n' "$red" "$reset" "$listing" >&2; return 1; fi
        mapfile -t current < <(printf '%s\n' "$listing" | sed '/^[[:space:]]*$/d')
        ((${#current[@]})) || break
        if [[ "$previous" == "$(printf '%s\n' "${current[@]}" | LC_ALL=C sort)" ]]; then
            for ext in "${current[@]}"; do
                printf '%sUnable to remove %s:%s\n%s\n' "$red" "$ext" "$reset" "${removal_errors[$ext]:-No removal details were returned by VS Code.}" >&2
            done
            printf '%sError:%s extensions remain installed: %s\n' "$red" "$reset" "${current[*]}" >&2
            return 1
        fi
        ((pass+=1))
        ((pass < 100)) || { printf '%sError:%s stopped after too many removal passes.\n' "$red" "$reset" >&2; return 1; }
    done
    printf '%sAll extensions removed.%s\n' "$green" "$reset"
}

reset_vscode() {
    local target answer
    local -a targets=() existing_targets=()
    if [[ -n "$code_root" && -d "$code_root/data" ]]; then
        targets=("$code_root/data/user-data" "$code_root/data/extensions")
    else
        targets=("${XDG_CONFIG_HOME:-$HOME/.config}/Code" "$HOME/.vscode/extensions")
    fi

    for target in "${targets[@]}"; do
        if [[ -L "$target" ]]; then printf '%sError:%s refusing to remove redirected data path: %s\n' "$red" "$reset" "$target" >&2; return 1; fi
        [[ -e "$target" ]] && existing_targets+=("$target")
    done
    ((${#existing_targets[@]})) || { printf '%sVS Code already has no user data to reset.%s\n' "$yellow" "$reset"; return 0; }

    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -x code >/dev/null 2>&1 || pgrep -x code-insiders >/dev/null 2>&1; then
            printf '%sError:%s close VS Code windows (including the one hosting this terminal) and run Reset from an external terminal.\n' "$red" "$reset" >&2
            return 1
        fi
    fi
    printf '\n%sThis removes VS Code settings, profiles, extensions, workspace state, and cached user data:%s\n' "$yellow" "$reset"
    printf '  %s\n' "${existing_targets[@]}"
    printf '%sVS Code itself and project files will remain.%s\n' "$yellow" "$reset"
    if ! IFS= read -r -p 'Type RESET to confirm: ' answer; then printf '\n%sReset cancelled.%s\n' "$yellow" "$reset"; return 0; fi
    [[ "$answer" == RESET ]] || { printf '%sReset cancelled.%s\n' "$yellow" "$reset"; return 0; }

    for target in "${existing_targets[@]}"; do
        case "$target" in
            "$code_root/data/user-data"|"$code_root/data/extensions"|"${XDG_CONFIG_HOME:-$HOME/.config}/Code"|"$HOME/.vscode/extensions") ;;
            *) printf '%sError:%s refusing unexpected reset path: %s\n' "$red" "$reset" "$target" >&2; return 1 ;;
        esac
        [[ -d "$target" ]] || { printf '%sError:%s expected a data directory at: %s\n' "$red" "$reset" "$target" >&2; return 1; }
        rm -rf -- "$target" || { printf '%sError:%s reset is incomplete at %s. Close VS Code and helper processes, then run Reset again from an external terminal; some data may already have been removed.\n' "$red" "$reset" "$target" >&2; return 1; }
        printf 'Removed %s\n' "$target"
    done
    printf '%sVS Code user data reset completed.%s\n' "$green" "$reset"
}

install_profile() {
    local apply_settings=${1:-false} ext total=0 index=0 user_dir
    mapfile -t extensions < <(sed 's/\r$//' "$config_dir/extensions.txt" | sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d')
    total=${#extensions[@]}
    printf '\n%sINSTALL  Profile "%s"  |  %d extensions%s\n' "$cyan" "$profile" "$total" "$reset"
    local -a install_args=()
    for ext in "${extensions[@]}"; do
        ((index+=1))
        printf '  %s\u2022 Installing [%d/%d] %s%s\n' "$green" "$index" "$total" "$ext" "$reset"
        install_args+=(--install-extension "$ext")
    done
    if ((${#install_args[@]})); then
        if [[ "$debug" == true ]]; then
            printf '%sDEBUG%s' "$gray" "$reset"
            printf ' %q' "$code_cli" "${install_args[@]}"
            printf '\n'
        fi
        printf '  %s\u2022 Waiting for VS Code...%s\n' "$cyan" "$reset"
        if ! run_code "${install_args[@]}"; then
            printf '%sError:%s VS Code failed to install one or more extensions in profile "%s".\n' "$red" "$reset" "$profile" >&2
            return 1
        fi
    fi
    user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
    if [[ "$apply_settings" == true ]]; then
        mkdir -p -- "$user_dir" || { printf '%sError:%s cannot create settings directory: %s\n' "$red" "$reset" "$user_dir" >&2; return 1; }
        cp -- "$config_dir/settings.json" "$user_dir/settings.json" || { printf '%sError:%s failed to copy profile settings.\n' "$red" "$reset" >&2; return 1; }
        printf '%sProfile "%s" installed successfully with settings.%s\n' "$green" "$profile" "$reset"
    else
        printf '%sProfile "%s" installed successfully. Settings were left unchanged.%s\n' "$green" "$profile" "$reset"
    fi
}

assert_local_repository() {
    if [[ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]]; then
        printf '%sError:%s Update profiles is available only from a local session.\n' "$red" "$reset" >&2
        return 1
    fi
    command -v git >/dev/null 2>&1 || { printf '%sError:%s Update profiles requires a local Git clone with a configured remote.\n' "$red" "$reset" >&2; return 1; }
    local repository_root script_root remotes
    repository_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null) || { printf '%sError:%s Update profiles requires a local Git clone with a configured remote.\n' "$red" "$reset" >&2; return 1; }
    repository_root=$(cd -- "$repository_root" && pwd -P) || return 1
    script_root=$(cd -- "$script_dir" && pwd -P) || return 1
    [[ "$repository_root" == "$script_root" ]] || { printf '%sError:%s Update profiles must be run from the root of the cloned project.\n' "$red" "$reset" >&2; return 1; }
    remotes=$(git -C "$script_dir" remote -v 2>/dev/null) || { printf '%sError:%s could not inspect Git remotes.\n' "$red" "$reset" >&2; return 1; }
    [[ -n "$remotes" ]] || { printf '%sError:%s Update profiles requires a configured Git remote.\n' "$red" "$reset" >&2; return 1; }
}

refresh_profiles() {
    local dir name
    profiles=(full)
    while IFS= read -r -d '' dir; do
        name="${dir##*/}"
        [[ "${name,,}" != full && -f "$dir/extensions.txt" && -f "$dir/settings.json" ]] && profiles+=("$name")
    done < <(find "$config_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

read_new_profile_name() {
    local name directory existing profile_path
    while true; do
        if ! IFS= read -r -p 'New profile name (letters, numbers, - and _): ' name; then
            printf '\n%sCancelled.%s\n' "$yellow" "$reset"
            return 130
        fi
        if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
            printf '%sInvalid name.%s Start with a letter or number; use only letters, numbers, - and _.\n' "$red" "$reset"
            continue
        fi
        if [[ "${name,,}" == full ]]; then
            printf '%sInvalid name.%s "full" is reserved for the default profile.\n' "$red" "$reset"
            continue
        fi
        directory="$config_root/$name"
        if [[ -e "$directory" ]]; then
            printf '%sProfile already exists:%s %s\n' "$red" "$reset" "$name"
            continue
        fi
        for profile_path in "$config_root"/*/; do
            [[ -d "$profile_path" ]] || continue
            existing="${profile_path%/}"
            existing="${existing##*/}"
            if [[ "${existing,,}" == "${name,,}" ]]; then
                printf '%sProfile already exists:%s %s\n' "$red" "$reset" "$existing"
                continue 2
            fi
        done
        REPLY=$name
        return 0
    done
}

save_current_profile() {
    local profile_name=$1 mode=$2 target settings_source="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"
    local temp_dir temp_raw temp_ext temp_settings backup_ext backup_settings created=false backups_ready=false
    if [[ "$profile_name" == full ]]; then target="$config_root"; else target="$config_root/$profile_name"; fi
    if [[ "$mode" == create ]]; then
        [[ "$profile_name" != full && ! -e "$target" ]] || { printf '%sError:%s profile already exists: %s\n' "$red" "$reset" "$profile_name" >&2; return 1; }
    else
        [[ -f "$target/extensions.txt" && -f "$target/settings.json" ]] || { printf '%sError:%s profile files are missing for "%s".\n' "$red" "$reset" "$profile_name" >&2; return 1; }
    fi
    [[ -f "$settings_source" ]] || { printf '%sError:%s VS Code settings not found: %s\n' "$red" "$reset" "$settings_source" >&2; return 1; }

    temp_dir=$(mktemp -d "$config_root/.profile.XXXXXX") || { printf '%sError:%s could not create temporary profile files.\n' "$red" "$reset" >&2; return 1; }
    temp_raw="$temp_dir/current-extensions.txt"
    temp_ext="$temp_dir/extensions.txt"
    temp_settings="$temp_dir/settings.json"
    backup_ext="$temp_dir/extensions.bak"
    backup_settings="$temp_dir/settings.bak"
    if ! "$code_cli" --list-extensions > "$temp_raw" 2>&1; then
        cat -- "$temp_raw" >&2
        rm -rf -- "$temp_dir"
        printf '%sError:%s failed to read installed extensions.\n' "$red" "$reset" >&2
        return 1
    fi
    if ! awk '/^[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$/' "$temp_raw" | LC_ALL=C sort -u > "$temp_ext"; then
        rm -rf -- "$temp_dir"
        printf '%sError:%s failed to prepare the extension list.\n' "$red" "$reset" >&2
        return 1
    fi
    if ! cp -- "$settings_source" "$temp_settings"; then
        rm -rf -- "$temp_dir"
        printf '%sError:%s failed to read current settings.\n' "$red" "$reset" >&2
        return 1
    fi

    if [[ "$mode" == create ]]; then
        if ! mkdir -- "$target"; then rm -rf -- "$temp_dir"; printf '%sError:%s could not create profile "%s".\n' "$red" "$reset" "$profile_name" >&2; return 1; fi
        created=true
    else
        if ! cp -p -- "$target/extensions.txt" "$backup_ext" || ! cp -p -- "$target/settings.json" "$backup_settings"; then
            rm -rf -- "$temp_dir"
            printf '%sError:%s could not prepare profile rollback files.\n' "$red" "$reset" >&2
            return 1
        fi
        backups_ready=true
    fi

    if mv -f -- "$temp_ext" "$target/extensions.txt" && mv -f -- "$temp_settings" "$target/settings.json"; then
        rm -rf -- "$temp_dir"
        if [[ "$mode" == create ]]; then printf '%sCreated profile "%s" with current extensions and settings.%s\n' "$green" "$profile_name" "$reset"
        else printf '%sUpdated profile "%s" with current extensions and settings.%s\n' "$green" "$profile_name" "$reset"; fi
        return 0
    fi

    local rollback_error=''
    if [[ "$created" == true ]]; then
        rm -f -- "$target/extensions.txt" "$target/settings.json" || rollback_error='Could not remove partial profile files.'
        rmdir -- "$target" 2>/dev/null || rollback_error='Could not remove the incomplete profile directory.'
    elif [[ "$backups_ready" == true ]]; then
        cp -p -- "$backup_ext" "$target/extensions.txt" && cp -p -- "$backup_settings" "$target/settings.json" || rollback_error='Could not restore the previous profile files.'
    fi
    rm -rf -- "$temp_dir"
    printf '%sError:%s failed to save profile "%s".%s\n' "$red" "$reset" "$profile_name" "${rollback_error:+ $rollback_error}" >&2
    return 1
}

update_profiles() {
    assert_local_repository || return 1
    printf '\n%s-------------------- Update profiles -------------------%s\n' "$cyan" "$reset"
    printf '  [1] Create new profile\n  [2] Update profile\n  [3] Update default\n'
    choose_number 'Select action [1-3]: ' 3
    local action=$REPLY profile_name profile_index
    clear_menu_screen
    case "$action" in
        1)
            read_new_profile_name || return $?
            profile_name=$REPLY
            clear_menu_screen
            save_current_profile "$profile_name" create
            ;;
        2)
            refresh_profiles
            printf '\n%s------------------ Available profiles -----------------%s\n' "$cyan" "$reset"
            for i in "${!profiles[@]}"; do
                if [[ "${profiles[$i]}" == full ]]; then printf '  %d. full (default)\n' "$((i+1))"
                else printf '  %d. %s\n' "$((i+1))" "${profiles[$i]}"; fi
            done
            choose_number "Select profile [1-${#profiles[@]}]: " "${#profiles[@]}"
            profile_name=${profiles[$((REPLY-1))]}
            clear_menu_screen
            save_current_profile "$profile_name" update
            ;;
        3) save_current_profile full update ;;
    esac
}

case "$operation" in
    1) remove_all_extensions && install_profile true ;;
    2) install_profile false ;;
    3) remove_all_extensions ;;
    4) reset_vscode ;;
    5) update_profiles ;;
esac
