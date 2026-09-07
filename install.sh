#!/bin/bash
# Wire the dz0ny.nix-apps plugin into the rest of Omarchy: the CLI on PATH and
# the entries in the Omarchy menu.
#
# `omarchy plugin add` only copies a folder and tells the shell to rescan it,
# so anything outside the shell has to be put in place here. The bar widget
# runs this on load with --quiet --no-prompt, which is why every step below is
# a no-op when it is already done: no rewrite, no backup, no output.
#
#   install.sh [--quiet] [--no-prompt]

set -uo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
EXT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc"
GLYPH=$'\U000F1105'   # nf-md-nix
ICON_SEARCH=$'\uf002'
ICON_REFRESH=$'\uf021'

QUIET=0
PROMPT=1
while (($#)); do
  case "$1" in
    --quiet | -q) QUIET=1; shift ;;
    --no-prompt) PROMPT=0; shift ;;
    -h | --help) echo "Usage: install.sh [--quiet] [--no-prompt]"; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; exit 1 ;;
  esac
done

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
info() { ((QUIET)) || printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok() { ((QUIET)) || printf '%s\n' "${C_GREEN}  ✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}  !${C_RESET} $*" >&2; }
die() { printf '%s\n' "install.sh: $*" >&2; exit 1; }

[[ -x $PLUGIN_DIR/bin/omarchy-nix ]] || die "bin/omarchy-nix is missing or not executable"

# ----------------------------------------------------------------- the CLI

if [[ $(readlink -f "$BIN_DIR/omarchy-nix" 2>/dev/null) != "$PLUGIN_DIR/bin/omarchy-nix" ]]; then
  mkdir -p "$BIN_DIR"
  ln -sf "$PLUGIN_DIR/bin/omarchy-nix" "$BIN_DIR/omarchy-nix"
  info "Linked omarchy-nix into $BIN_DIR"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on PATH; the menu entries will not find omarchy-nix" ;;
esac

# -------------------------------------------------------- the Omarchy menu

# Every row is guarded on the CLI still being there, so removing the plugin
# takes its menu entries out of the menu with it — a dangling symlink is not
# executable, so `command -v` stops finding it.
HAVE_CLI="command -v omarchy-nix >/dev/null 2>&1"
HAVE_NIX="command -v nix >/dev/null 2>&1 || [ -x /nix/var/nix/profiles/default/bin/nix ]"
NO_NIX="! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]"
TERM_RUN="omarchy-launch-floating-terminal-with-presentation"

# Built with command substitution, not `read -d ''`: read would strip the two
# leading spaces off the first line and keep a trailing newline, and the
# comparison below has to be byte-exact or every run rewrites the file.
BLOCK=$(cat <<EOF
  // >>> omarchy-nix-apps (managed by install.sh)
  "install.nix": {"icon":"$GLYPH","label":"Nix","description":"Apps from nixpkgs, for what Arch does not package here","when":"$HAVE_CLI"},
  "install.nix.app": {"icon":"$GLYPH","label":"App","description":"The curated catalogue — alt-a switches to every package that builds here","action":"$TERM_RUN 'omarchy-nix menu'"},
  "install.nix.package": {"icon":"$ICON_SEARCH","label":"Any Package","description":"Every nixpkgs package that builds for this machine, like Install > Package","action":"$TERM_RUN 'omarchy-nix pick'"},
  "install.nix.index": {"icon":"$ICON_REFRESH","label":"Rebuild Index","description":"Refresh the list of nixpkgs packages that build for this machine","when":"$HAVE_NIX","action":"$TERM_RUN 'omarchy-nix index --refresh'"},
  "remove.nix": {"icon":"$GLYPH","label":"Nix App","description":"Remove an app from the Nix profile","when":"$HAVE_CLI","action":"$TERM_RUN 'omarchy-nix menu remove'"},
  "update.nix": {"icon":"$GLYPH","label":"Nix Apps","description":"Upgrade every app in the Nix profile","when":"$HAVE_CLI && ($HAVE_NIX)","action":"$TERM_RUN 'omarchy-nix update'"},
  "setup.nix": {"icon":"$GLYPH","label":"Nix","description":"Install Determinate Nix","when":"$HAVE_CLI && $NO_NIX","action":"$TERM_RUN 'omarchy-nix setup'"},
  // <<< omarchy-nix-apps
EOF
)

mkdir -p "$(dirname "$EXT_FILE")"
[[ -f $EXT_FILE ]] || printf '{\n}\n' >"$EXT_FILE"

current=$(awk '
  /\/\/ >>> omarchy-nix-apps/ { inside = 1 }
  inside { print }
  /\/\/ <<< omarchy-nix-apps/ { inside = 0 }
' "$EXT_FILE")

if [[ $current == "$BLOCK" ]]; then
  ok "menu entries already current"
else
  cp -- "$EXT_FILE" "$EXT_FILE.bak.$(date +%s)"
  tmp=$(mktemp)
  awk '
    /\/\/ >>> omarchy-nix-apps/ { skip = 1 }
    !skip { print }
    /\/\/ <<< omarchy-nix-apps/ { skip = 0 }
  ' "$EXT_FILE" >"$tmp"

  close_line=$(awk '{ line = $0; gsub(/[[:space:]]/, "", line); if (line == "}") last = NR } END { print last + 0 }' "$tmp")
  if [[ $close_line -gt 0 ]]; then
    {
      head -n $((close_line - 1)) "$tmp"
      printf '%s\n' "$BLOCK"
      tail -n +"$close_line" "$tmp"
    } >"$EXT_FILE"
    info "Menu entries written to $EXT_FILE"
  else
    warn "could not find the closing brace in $EXT_FILE — add the entries from menu.jsonc by hand"
  fi
  rm -f "$tmp"
fi

# ------------------------------------------------------------------- next

((QUIET)) && exit 0

cat <<EOS

${C_GREEN}Plugin wired up.${C_RESET}

  omarchy-nix setup      install Determinate Nix and the session environment
  omarchy-nix menu       pick from the curated catalogue (alt-a for every package)
  omarchy-nix pick       pick from every package that builds for this machine
  omarchy-nix doctor     check the integration

  Bar widget (shows only when app updates are waiting):
    omarchy plugin enable dz0ny.nix-apps --section right

EOS

if ((PROMPT)) && [[ -t 0 && -t 1 ]] && ! command -v nix >/dev/null 2>&1 &&
  [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  if command -v gum >/dev/null 2>&1 && gum confirm "Run omarchy-nix setup now?"; then
    exec "$PLUGIN_DIR/bin/omarchy-nix" setup
  fi
fi
