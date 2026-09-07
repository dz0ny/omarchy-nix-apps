#!/bin/bash
# Undo install.sh. Leaves Nix itself and the installed apps alone — removing
# those is a separate, explicit decision.

set -uo pipefail

BIN_DIR="$HOME/.local/bin"
EXT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc"
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/50-omarchy-nix-apps.sh"

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'
info() { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok() { printf '%s\n' "${C_GREEN}  ✓${C_RESET} $*"; }

info "Removing the omarchy-nix symlink"
[[ -L $BIN_DIR/omarchy-nix ]] && rm -f "$BIN_DIR/omarchy-nix" && ok "$BIN_DIR/omarchy-nix"

if [[ -f $EXT_FILE ]]; then
  info "Removing the menu entries"
  cp -- "$EXT_FILE" "$EXT_FILE.bak.$(date +%s)"
  tmp=$(mktemp)
  awk '
    /\/\/ >>> omarchy-nix-apps/ { skip = 1 }
    !skip { print }
    /\/\/ <<< omarchy-nix-apps/ { skip = 0 }
  ' "$EXT_FILE" >"$tmp" && mv "$tmp" "$EXT_FILE"
  ok "$EXT_FILE"
fi

if [[ -f $ENV_FILE ]]; then
  info "Removing the session environment file"
  rm -f "$ENV_FILE"
  ok "$ENV_FILE (log out and back in to drop it from the running session)"
fi

cat <<'EOS'

Still on this machine, on purpose:
  - the apps in your Nix profile   remove with: nix profile remove <name>
  - Nix itself                     remove with: /nix/nix-installer uninstall
  - ~/.config/omarchy-nix/config   your settings
  - ~/.local/state/omarchy-nix     the package list and update caches
  - the plugin folder              remove with: omarchy plugin remove dz0ny.nix-apps

EOS
