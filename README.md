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

- Omarchy (Hyprland under `uwsm`), `jq`, `fzf`, `gum`, `curl` — all already present on a stock install
- ~5 GB of free space for `/nix`
- `sudo` once, for the Nix installer

## Install

```bash
omarchy plugin add https://github.com/dz0ny/omarchy-nix-apps.git --enable
```

That is the whole install. `omarchy plugin add` only copies the folder and
rescans the shell, so the bar widget runs `install.sh` when it loads: that
links `omarchy-nix` into `~/.local/bin` and merges the plugin's entries into
the Omarchy menu (`Install → Nix`, `Remove → Nix App`, `Update → Nix Apps`,
`Setup → Nix`). It is a no-op on every run after the first — no rewrite, no
backup, no output — so it costs one process per shell start.

Without the widget, run it yourself once:

```bash
~/.config/omarchy/plugins/dz0ny.nix-apps/install.sh
```

Then:

```bash
omarchy-nix setup     # installs Determinate Nix + the session environment
omarchy-nix menu      # pick apps
```

Log out and back in once after `setup`, so the session picks up
`XDG_DATA_DIRS` and the installed apps appear in the launcher.

The bar widget is an alert, not a launcher: the bar stays empty until an
installed Nix app actually has a newer build waiting, and goes back to empty
once you have taken it. Left-click upgrades everything, middle-click re-checks
now, right-click lists what is waiting.

## Usage

```
omarchy-nix setup [--env-only]   Install Determinate Nix and wire the session
omarchy-nix menu [remove]        Curated catalogue picker; alt-a for every package
omarchy-nix pick [query]         Picker over every package that builds here
omarchy-nix install <app>...     By catalogue id, name, or raw nixpkgs attribute
omarchy-nix remove <app>...
omarchy-nix list [--json]
omarchy-nix update [app...]
omarchy-nix updates [--brief]    What an upgrade would change (cached)
omarchy-nix index [--refresh]    Rebuild the list of packages that build here
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

### The picker

`omarchy-nix menu` opens fzf on the ~50 curated apps, with a preview pane
carrying the version, the description, whether it builds here, and whether
pacman has it natively. **`alt-a` switches the same picker to every package
that builds for this machine, and back.** `tab` multi-selects, `enter`
installs.

That second list is not all of nixpkgs. It is built once by
`omarchy-nix index` and cached in
`~/.local/state/omarchy-nix/nixpkgs-index.tsv`, and it is filtered to what you
can actually install here:

- only attributes whose `meta.platforms` covers this system, and that are not
  marked broken — `nix search` will happily offer you Spotify on aarch64 even
  though upstream ships x86_64 binaries only
- only top-level attributes; `python3Packages.*` and friends are libraries,
  not apps

On this machine that is ~22k packages out of the ~112k `nix search` returns,
and the eval takes about fifteen seconds. `omarchy-nix search` still goes
straight to `nix search`, so nothing is out of reach.

`omarchy-nix pick` opens that same list directly, skipping the catalogue —
it is the Nix counterpart to `Install → Package`.

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
the result in `~/.local/state/omarchy-nix/verified.json`. The catalogue picker
then marks each row `installed`, `no aarch64-linux build`, or `attr gone`. Run
it after a big nixpkgs bump.

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
# NIX_APPS_INDEX_MAX_AGE=604800   # how stale the package list may get, seconds
# NIX_APPS_UPDATE_MAX_AGE=21600   # how stale the update check may get, seconds
```

## Troubleshooting

```bash
omarchy-nix doctor
```

checks the architecture, the Nix binary and daemon, flake support, the session
env file, `XDG_DATA_DIRS`, the `.desktop` count, the required tooling, and the
age of the package list.

**The bar widget never appears.** It only appears when an installed Nix app has
a newer build waiting. `omarchy-nix updates --refresh` answers the same
question in the terminal, and is what the widget reads.

**The package list is out of date.** `omarchy-nix index --refresh`, or
`Install → Nix → Rebuild Index`. It rebuilds itself weekly on its own.

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
