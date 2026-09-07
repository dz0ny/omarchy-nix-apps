#!/bin/bash
# Wire the dz0ny.nix-apps plugin into the rest of Omarchy.
#
# `omarchy plugin add` only ever copies a folder and tells the shell to rescan
# it, so anything outside the shell — the CLI on PATH, the entries in the
# Omarchy menu — has to be put in place here.

set -uo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
EXT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc"
MARK_BEGIN="  // >>> omarchy-nix-apps (managed by install.sh)"
MARK_END="  // <<< omarchy-nix-apps"
GLYPH=$'\U000F1105'

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
info() { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok() { printf '%s\n' "${C_GREEN}  ✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}  !${C_RESET} $*" >&2; }
die() { printf '%s\n' "install.sh: $*" >&2; exit 1; }

[[ -x $PLUGIN_DIR/bin/omarchy-nix ]] || die "bin/omarchy-nix is missing or not executable"

# ----------------------------------------------------------------- the CLI

info "Linking omarchy-nix into $BIN_DIR"
mkdir -p "$BIN_DIR"
ln -sf "$PLUGIN_DIR/bin/omarchy-nix" "$BIN_DIR/omarchy-nix"
ok "$BIN_DIR/omarchy-nix -> $PLUGIN_DIR/bin/omarchy-nix"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on PATH; the menu entries will not find omarchy-nix" ;;
esac

# -------------------------------------------------------- the Omarchy menu

info "Adding menu entries to $EXT_FILE"
mkdir -p "$(dirname "$EXT_FILE")"
[[ -f $EXT_FILE ]] || printf '{\n}\n' >"$EXT_FILE"
cp -- "$EXT_FILE" "$EXT_FILE.bak.$(date +%s)"

block=$(
  cat <<EOF
$MARK_BEGIN
  "install.nix": {"icon":"$GLYPH","label":"Nix App","description":"Install a big desktop app from nixpkgs","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix menu'"},
  "remove.nix": {"icon":"$GLYPH","label":"Nix App","description":"Remove an app from the Nix profile","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix menu remove'"},
  "update.nix": {"icon":"$GLYPH","label":"Nix Apps","description":"Upgrade every app in the Nix profile","when":"command -v nix >/dev/null 2>&1 || [ -x /nix/var/nix/profiles/default/bin/nix ]","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix update'"},
  "setup.nix": {"icon":"$GLYPH","label":"Nix","description":"Install Determinate Nix","when":"! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix setup'"},
$MARK_END
EOF
)

tmp=$(mktemp)
# Drop a previous block, then re-insert before the file's final closing brace,
# so running this twice leaves the same file rather than a growing one.
awk '
  /\/\/ >>> omarchy-nix-apps/ { skip = 1 }
  !skip { print }
  /\/\/ <<< omarchy-nix-apps/ { skip = 0 }
' "$EXT_FILE" >"$tmp"

close_line=$(awk '{ line = $0; gsub(/[[:space:]]/, "", line); if (line == "}") last = NR } END { print last + 0 }' "$tmp")
[[ $close_line -gt 0 ]] || die "could not find the closing brace in $EXT_FILE — add the entries from menu.jsonc by hand"

{
  head -n $((close_line - 1)) "$tmp"
  printf '%s\n' "$block"
  tail -n +"$close_line" "$tmp"
} >"$EXT_FILE"
rm -f "$tmp"
ok "install / remove / update / setup entries added (the menu hot-reloads)"

# ------------------------------------------------------------------ shell

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 && ok "shell rescanned plugins"
fi

# ------------------------------------------------------------------- next

cat <<EOS

${C_GREEN}Plugin wired up.${C_RESET}

  Next:
    omarchy-nix setup      install Determinate Nix and the session environment
    omarchy-nix menu       pick apps to install
    omarchy-nix doctor     check the integration

  Optional bar widget:
    omarchy plugin enable dz0ny.nix-apps --section right

EOS

if [[ -t 0 && -t 1 ]] && ! "$PLUGIN_DIR/bin/omarchy-nix" status --brief >/dev/null 2>&1; then
  if command -v gum >/dev/null 2>&1 && gum confirm "Run omarchy-nix setup now?"; then
    exec "$PLUGIN_DIR/bin/omarchy-nix" setup
  fi
fi
