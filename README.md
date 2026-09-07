# omarchy-nix-apps

An Omarchy plugin that installs the **big desktop apps Arch does not package for
your architecture**, using [Determinate Nix](https://docs.determinate.systems/)
and a per-user Nix profile.

On `aarch64` Arch Linux ARM the repos are thin and most of the AUR is
`x86_64`-only, and the gap lands exactly on the applications that hurt most:
IDEs, browsers, GIMP, Blender, LibreOffice, KiCad. nixpkgs builds those for
`aarch64-linux` and `cache.nixos.org` ships them prebuilt.

The split this plugin assumes:

| Layer | Owner |
|---|---|
| kernel, drivers, Hyprland, terminal, CLI tooling, anything a service depends on | **pacman** (`omarchy pkg add`) |
| large end-user GUI applications with no native package for this arch | **nix profile** (`omarchy-nix install`) |

It will actively push you back to pacman: if the app you asked for exists in the
Arch repos for this machine, `omarchy-nix install` refuses and tells you to run
`omarchy pkg add` instead (`--force` overrides).

## Requirements

- Omarchy (Hyprland under `uwsm`), `jq`, `gum`, `curl` — all already present on a stock install
- ~5 GB of free space for `/nix`
- `sudo` once, for the Nix installer

## Install

```bash
omarchy plugin add https://github.com/dz0ny/omarchy-nix-apps.git
~/.config/omarchy/plugins/dz0ny.nix-apps/install.sh
```

`omarchy plugin add` only copies the folder and rescans the shell, so
`install.sh` does the rest: it links `omarchy-nix` into `~/.local/bin` and adds
four entries to the Omarchy menu (`Install → Nix App`, `Remove → Nix App`,
`Update → Nix Apps`, `Setup → Nix`). Re-running it is safe; it replaces its own
managed block rather than appending a second one.

Then:

```bash
omarchy-nix setup     # installs Determinate Nix + the session environment
omarchy-nix menu      # pick apps
```

Log out and back in once after `setup`, so the session picks up
`XDG_DATA_DIRS` and the installed apps appear in the launcher.

The bar widget is optional:

```bash
omarchy plugin enable dz0ny.nix-apps --section right
```

Left-click opens the picker, middle-click upgrades everything, right-click sends
a status notification. It hides itself entirely until Nix is installed.

## Usage

```
omarchy-nix setup [--env-only]   Install Determinate Nix and wire the session
omarchy-nix menu [remove]        TUI picker
omarchy-nix install <app>...     By catalogue id, name, or raw nixpkgs attribute
omarchy-nix remove <app>...
omarchy-nix list [--json]
omarchy-nix update [app...]
omarchy-nix search <query>
omarchy-nix catalog [--json]
omarchy-nix verify               Check the whole catalogue against this system
omarchy-nix status [--brief]
omarchy-nix doctor
omarchy-nix gc
```

```bash
omarchy-nix install vscode blender kicad
omarchy-nix install nixpkgs#zed-editor      # anything in nixpkgs, not just the catalogue
omarchy-nix install --force firefox         # even though Arch has it for arm64
```

## How it works

**Determinate Nix.** `setup` runs the official installer
(`curl -sSf -L https://install.determinate.systems/nix | sh -s -- install
--determinate --no-confirm`). Flakes and `nix-command` are on by default, and
the whole thing reverts with `/nix/nix-installer uninstall`.

**Profiles, not a system rebuild.** Apps go into your user profile via
`nix profile install`. Nothing about the Arch system changes; `pacman -Qi` and
`nix profile list` never argue over the same file.

**Session wiring** is the part that is easy to get wrong. `/etc/profile.d/nix.sh`
only reaches login shells, so a `.desktop` file in `~/.nix-profile/share` stays
invisible to the launcher. `setup` writes
`~/.config/uwsm/env.d/50-omarchy-nix-apps.sh`, which `uwsm` sources before
Hyprland starts, so the whole graphical session — `omarchy-shell` included —
sees:

- `XDG_DATA_DIRS` extended with `~/.nix-profile/share` (desktop entries, icons)
- `PATH` **appended** with `~/.nix-profile/bin` — appended on purpose, so a Nix
  profile that happens to contain `git` or `bash` cannot displace the
  pacman-managed system tooling
- `NIX_SSL_CERT_FILE`, which the graphical session would otherwise lack

**A platform check before every install.** `omarchy-nix install` evaluates
`meta.platforms` for the attribute and refuses when your system is not in it,
instead of downloading for ten minutes and failing at the end. `--no-check`
skips it.

## The catalogue

`apps.json` is a curated list of ~50 large applications with their nixpkgs
attributes, grouped by category, marked `unfree` where relevant, and annotated
with the Arch package name so the native-package check can fire.

nixpkgs attribute names drift (`gimp` → `gimp3`, `godot` → `godot_4`, …), so the
catalogue is a starting point, not a promise:

```bash
omarchy-nix verify
```

resolves every entry against the configured flake in one evaluation and caches
the result in `~/.local/state/omarchy-nix/verified.json`. The picker then marks
entries `✓` installed, `✗` no build for this system, `?` attribute gone. Run it
after a big nixpkgs bump.

### Apps that cannot work here

`apps.json` also carries an `unavailable` list — Spotify, Slack, Discord, Zoom,
Signal Desktop, Android Studio, Postman, LM Studio. These ship `x86_64`-only
Linux binaries upstream, so nixpkgs has no `aarch64-linux` build either and no
package manager will fix that. `omarchy-nix catalog` prints them with the
suggested alternative (a web app via `omarchy install webapp`, `spotify-player`,
Bruno, Ollama…).

## Configuration

`~/.config/omarchy-nix/config`, sourced on every run:

```bash
NIX_APPS_FLAKE="nixpkgs"          # or github:NixOS/nixpkgs/nixos-unstable to pin
NIX_APPS_ALLOW_UNFREE=1           # 0 refuses VS Code, Obsidian, Sublime, Brave
# NIX_APPS_CATALOG="$HOME/.config/omarchy-nix/apps.json"   # your own catalogue
```

## Troubleshooting

```bash
omarchy-nix doctor
```

checks the architecture, the Nix binary and daemon, flake support, the session
env file, `XDG_DATA_DIRS`, the `.desktop` count, and the required tooling.

**An app installed but does not show in the launcher.** The session env only
loads at login — log out and back in, then `omarchy-nix doctor`.

**Disk filling up.** `omarchy-nix gc` drops profile generations older than 30
days and collects garbage.

**Themes look wrong in a Nix app.** GTK/Qt apps from Nix read the system theme
through `XDG_DATA_DIRS`, which `setup` handles; per-app icon themes may still
need the matching Nix package (`adwaita-icon-theme`).

## Uninstall

```bash
~/.config/omarchy/plugins/dz0ny.nix-apps/uninstall.sh   # unwires the menu, PATH, session env
omarchy plugin remove dz0ny.nix-apps                    # removes the plugin
/nix/nix-installer uninstall                            # removes Nix itself, if you want
```

The first two leave Nix and your installed apps alone, on purpose.

## License

MIT
