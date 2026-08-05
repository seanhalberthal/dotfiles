#!/usr/bin/env bash
# local-layer helpers shared by the dotfiles dispatcher: manifest of the
# user-owned "local layer" plus private-repo plumbing for export/import.
# source this file after common.sh and cli.sh

[[ -n "${_DOTFILES_LOCAL_LAYER_SH_LOADED:-}" ]] && return 0
_DOTFILES_LOCAL_LAYER_SH_LOADED=1

[[ -z "${_DOTFILES_COMMON_SH_LOADED:-}" ]] && {
    echo "local-layer.sh requires common.sh to be sourced first" >&2
    return 1
}
[[ -z "${_DOTFILES_CLI_SH_LOADED:-}" ]] && {
    echo "local-layer.sh requires cli.sh to be sourced first" >&2
    return 1
}

: "${DOTFILES_DIR:?DOTFILES_DIR must be set before sourcing local-layer.sh}"

# build LOCAL_PAIRS (files) and LOCAL_DIR_PAIRS (directories) as
# "repo-relative|system-absolute" strings, preset-gated like the installer.
# secrets.zsh, .state/, the preset file and current-theme are deliberately
# absent: theme is a per-machine choice, not synced
_local_pairs() {
    # should_install reads $PRESET (installer export); resolve from the saved
    # preset when invoked via the CLI, where it is unset
    local PRESET="${PRESET:-$(get_preset)}"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    LOCAL_PAIRS=(
        "zshrc|$HOME/.zshrc"
        "config/tmux/local.conf|$cfg/tmux/local.conf"
    )
    LOCAL_DIR_PAIRS=()
    if should_install "core"; then
        LOCAL_PAIRS+=(
            "config/nvim/local.lua|$cfg/nvim/local.lua"
            "config/ghostty/local|$cfg/ghostty/local"
            "config/gh-dash/local.yml|$cfg/gh-dash/local.yml"
            "config/lazygit/local.yml|$cfg/lazygit/local.yml"
            "config/zed/settings.json|$cfg/zed/settings.json"
            "config/btop/btop.conf|$cfg/btop/btop.conf"
            "ai/claude/CLAUDE.local.md|$HOME/.ai/claude/CLAUDE.local.md"
        )
        if is_macos; then
            LOCAL_PAIRS+=("lazydocker/config.yml|$HOME/Library/Application Support/lazydocker/config.yml")
        else
            LOCAL_PAIRS+=("lazydocker/config.yml|$cfg/lazydocker/config.yml")
        fi
        LOCAL_DIR_PAIRS+=("config/dotfiles/launchers|$cfg/dotfiles/launchers")
    fi
    if should_install "full"; then
        LOCAL_PAIRS+=(
            "hammerspoon/local.lua|$HOME/.hammerspoon/local.lua"
            "config/karabiner/karabiner.json|$cfg/karabiner/karabiner.json"
        )
    fi
}

# narrow LOCAL_PAIRS / LOCAL_DIR_PAIRS in place to entries matching the given
# selectors. a selector matches a file pair, or a whole dir pair, by the exact
# or suffix repo-relative path, the basename, or the system path; a single file
# inside a dir pair (dir + "/" + subpath) is promoted into LOCAL_PAIRS so it
# flows through the ordinary file path, no wholesale mirror and no prune.
# returns 1 if any selector matches nothing. requires _local_pairs first
_local_select() {
    local -a fpairs=() dpairs=()
    local pair repo sys base sel rest matched
    for sel in "$@"; do
        sel="${sel#./}"; sel="${sel%/}"
        matched=0
        for pair in "${LOCAL_PAIRS[@]}"; do
            repo="${pair%%|*}" sys="${pair#*|}" base="${repo##*/}"
            if [[ "$sel" == "$repo" || "$repo" == */"$sel" || "$sel" == "$base" \
                || "$sel" == "$sys" || "$sys" == */"$sel" ]]; then
                fpairs+=("$pair"); matched=1
            fi
        done
        for pair in "${LOCAL_DIR_PAIRS[@]}"; do
            repo="${pair%%|*}" sys="${pair#*|}" base="${repo##*/}"
            if [[ "$sel" == "$repo" || "$repo" == */"$sel" || "$sel" == "$base" \
                || "$sel" == "$sys" || "$sys" == */"$sel" ]]; then
                dpairs+=("$pair"); matched=1
            elif [[ "$sel" == "$repo/"* ]]; then
                rest="${sel#"$repo"/}"; fpairs+=("$repo/$rest|$sys/$rest"); matched=1
            elif [[ "$sel" == "$base/"* ]]; then
                rest="${sel#"$base"/}"; fpairs+=("$repo/$rest|$sys/$rest"); matched=1
            elif [[ "$sel" == "$sys/"* ]]; then
                rest="${sel#"$sys"/}"; fpairs+=("$repo/$rest|$sys/$rest"); matched=1
            fi
        done
        if [[ $matched -eq 0 ]]; then
            error "No local-layer entry matches: $sel"
            return 1
        fi
    done
    LOCAL_PAIRS=( ${fpairs[@]+"${fpairs[@]}"} )
    LOCAL_DIR_PAIRS=( ${dpairs[@]+"${dpairs[@]}"} )
}

# expand github "owner/repo" shorthand to a full https clone url; schemes,
# user@ forms, and existing local paths pass through untouched
_local_expand_url() {
    local url="$1"
    if [[ "$url" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ && ! -e "$url" ]]; then
        printf 'https://github.com/%s.git' "${url%.git}"
    else
        printf '%s' "$url"
    fi
}

# validate and echo the configured local repo dir. errors to stderr:
# unconfigured (2), missing dir or not a git repo (1)
_local_dir_required() {
    local dir
    dir=$(get_local_dir)
    if [[ -z "$dir" ]]; then
        error "No local repo configured"
        printf "  Run: ${CYAN}dotfiles local init${NC} (new) or ${CYAN}dotfiles local clone <url>${NC} (existing)\n" >&2
        return 2
    fi
    if [[ ! -d "$dir" ]]; then
        error "Local repo path does not exist: $dir"
        printf "  Fix the pointer (%s) or run: ${CYAN}dotfiles local init${NC}\n" "$LOCAL_REPO_FILE" >&2
        return 1
    fi
    if ! git -C "$dir" rev-parse --git-dir &>/dev/null; then
        error "Not a git repository: $dir"
        return 1
    fi
    printf '%s' "$dir"
}

# seed .gitignore in the local repo if missing; belt and braces, the
# manifest never includes these
_local_seed_gitignore() {
    local dir="$1"
    [[ -f "$dir/.gitignore" ]] && return 0
    printf '%s\n' ".DS_Store" "secrets.zsh" ".state/" "statusline-theme.sh" "config/dotfiles/current-theme" > "$dir/.gitignore"
}

# write the pointer file
_local_write_pointer() {
    local dir="$1"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$dir" > "$LOCAL_REPO_FILE"
}

# commit with an identity fallback so fresh machines without git config work
_local_commit() {
    local dir="$1" msg="$2"
    if git -C "$dir" config user.email >/dev/null 2>&1; then
        git -C "$dir" commit -q -m "$msg"
    else
        git -C "$dir" -c user.name="${USER:-dotfiles}" \
            -c user.email="${USER:-dotfiles}@$(hostname -s)" commit -q -m "$msg"
    fi
}
