# Nix Apps

**The big desktop apps Arch has no package for on your architecture — installed,
launchable, and actually rendering.**

Nix Apps sits in your [Omarchy](https://omarchy.org) menu and installs large GUI
applications from [nixpkgs](https://search.nixos.org/packages) into a per-user
[Determinate Nix](https://docs.determinate.systems/) profile. It leaves the base
system entirely to pacman, and it deals with the three things that otherwise
make a Nix app on Arch a bad time: the launcher not seeing it, the app not
finding a graphics driver, and the app finding one that cannot draw.

## Why you'd want it

On `aarch64` Arch Linux ARM the repos are thin and most of the AUR is
`x86_64`-only. The gap lands exactly on the applications that hurt most: IDEs,
browsers, GIMP, Blender, LibreOffice, KiCad. nixpkgs builds those for
`aarch64-linux`, and `cache.nixos.org` ships them prebuilt.

Nothing here is aarch64-specific. The system is read from `uname` once, and the
package list, the platform check, the catalogue markers and the
known-impossible list are all answered for *that* system — `x86_64-linux`,
`riscv64-linux` or anything else nixpkgs supports. aarch64 is simply where the
gap is worst; on x86_64 the same tool works and you will just reach for it less
often.

| Layer | Owner |
|---|---|
| kernel, drivers, Hyprland, terminal, CLI tooling, anything a service depends on | **pacman** (`omarchy pkg add`) |
| large end-user GUI applications with no native package for this arch | **nix profile** (`omarchy-nix install`) |

It will actively push you back to pacman: if the app you asked for exists in the
Arch repos for this machine, `omarchy-nix install` refuses and tells you to run
`omarchy pkg add` instead. `--force` overrides.

## Install

```bash
omarchy plugin add https://github.com/dz0ny/omarchy-nix-apps.git --enable
omarchy-nix setup
```

That is the whole install. `omarchy plugin add` only copies the folder and
rescans the shell, so the bar widget runs `install.sh` when it loads: that links
`omarchy-nix` into `~/.local/bin` and merges this plugin's entries into the
Omarchy menu (`Install → Nix`, `Remove → Nix App`, `Update → Nix Apps`,
`Setup → Nix`). It is a no-op on every run after the first — no rewrite, no
backup, no output — so it costs one process per shell start. Without the widget,
run `~/.config/omarchy/plugins/dz0ny.nix-apps/install.sh` yourself once.

`omarchy-nix setup` installs Determinate Nix (one `sudo` prompt, ~5 GB in
`/nix`), writes the session environment, and fetches a graphics driver. **Log
out and back in once afterwards** — `uwsm` only reads `env.d` at session start,
and until it does, the launcher cannot see anything you install.

Nix Apps uses `jq`, `fzf`, `gum`, `curl` and `pacman`, all of which ship with
Omarchy. Updating is Omarchy's own `omarchy plugin update dz0ny.nix-apps`.

Then pick something:

```bash
omarchy-nix menu
```

## Using it

### The bar icon

An alert, not a launcher. The bar stays empty until an installed app actually
has a newer build waiting, and goes back to empty once you have taken it.

| Click | Does |
|---|---|
| left | opens the update picker — **space** selects, **enter** upgrades |
| middle | re-checks against nixpkgs now |
| right | notification listing what is waiting |

It opens a picker rather than upgrading everything on the spot: an update you
did not ask for is how a working machine stops working mid-afternoon.

### The pickers

Three, all fzf, all with a preview pane carrying the version, the description,
whether it builds here, and whether pacman has it natively.

**`omarchy-nix menu`** — the ~50 curated apps. `tab` multi-selects, `enter`
installs, and **`alt-a` switches the same picker to every package that builds
for this machine, and back.**

**`omarchy-nix pick`** — that second list directly, skipping the catalogue. The
Nix counterpart to `Install → Package`.

**`omarchy-nix menu update`** — what the bar icon opens. Re-checks against
nixpkgs, lists only the apps whose build has actually moved, upgrades the ones
you mark. **Space** selects, **enter** upgrades, `ctrl-a` takes everything.

The "every package" list is not all of nixpkgs. It is built once by
`omarchy-nix index`, cached in `~/.local/state/omarchy-nix/nixpkgs-index.tsv`,
and filtered to what you can actually install here:

- only attributes whose `meta.platforms` covers this system, and that are not
  marked broken — `nix search` will happily offer you Spotify on aarch64 even
  though upstream ships x86_64 binaries only
- only top-level attributes; `python3Packages.*` and friends are libraries, not
  apps

That is ~22k packages on `aarch64-linux` and ~23k on `x86_64-linux`, out of the
~112k `nix search` returns, and the eval takes about fifteen seconds.
`omarchy-nix search` still goes straight to `nix search`, so nothing is out of
reach.

### The commands

```
omarchy-nix setup [--env-only]   Install Determinate Nix and wire the session
omarchy-nix menu [remove|update] Curated catalogue picker, or remove, or upgrade
omarchy-nix pick [query]         Picker over every package that builds here
omarchy-nix install <app>...     By catalogue id, name, or raw nixpkgs attribute
omarchy-nix remove <app>...
omarchy-nix list [--json]
omarchy-nix update [app...]
omarchy-nix updates [--brief]    What an upgrade would change (cached)
omarchy-nix exec <cmd> [args]    Run a Nix app with the graphics driver wired up
omarchy-nix gl [--refresh]       Install or update that driver, or re-probe it
omarchy-nix sync                 Re-mirror the desktop entries
omarchy-nix index [--refresh]    Rebuild the list of packages that build here
omarchy-nix search <query>
omarchy-nix catalog [--json]
omarchy-nix verify               Check the whole catalogue against this system
omarchy-nix status [--brief]
omarchy-nix doctor
omarchy-nix gc                   Trim old generations and collect garbage
```

`install` and `update` end with a `gc` of their own, so the store does not
quietly accumulate every closure you have ever replaced. Set
`NIX_APPS_GC_AFTER=0` if you would rather run it yourself. Generations are
gcroots, so an upgrade's old closure only becomes collectable once the
generation holding it is older than `NIX_APPS_GC_KEEP` (7 days by default).

```bash
omarchy-nix install vscode blender kicad
omarchy-nix install nixpkgs#zed-editor      # anything in nixpkgs, not just the catalogue
omarchy-nix install --force firefox         # even though Arch has it for arm64
```

## How it works

**Determinate Nix.** `setup` runs the official installer (`curl -sSf -L
https://install.determinate.systems/nix | sh -s -- install --determinate
--no-confirm`). Flakes and `nix-command` are on by default, and the whole thing
reverts with `/nix/nix-installer uninstall`.

**Profiles, not a system rebuild.** Apps go into your user profile via `nix
profile add`. Nothing about the Arch system changes; `pacman -Qi` and `nix
profile list` never argue over the same file.

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

**A graphics driver.** A nixpkgs GUI app ships libglvnd but no driver. On NixOS
the driver comes from `/run/opengl-driver`; on Arch that path does not exist,
libglvnd finds no EGL vendor, and the app dies at startup with

```
No provider of eglGetPlatformDisplayEXT found.  Requires one of:
    EGL_EXT_platform_base
```

The host's mesa cannot fill the gap — it is built against a newer glibc than the
one in the app's closure, and putting `/usr/lib` on `LD_LIBRARY_PATH` takes the
whole process down, wrapper shell included. So the driver comes from nixpkgs
too: `omarchy-nix gl` installs a mesa into a profile of its own under
`~/.local/state/omarchy-nix/gl`, and `omarchy-nix exec` points an app at it.

It is applied **per app, never session-wide**. Forcing this mesa on the
pacman-managed desktop would put Hyprland's own EGL at risk, and losing the
compositor costs more than a GUI app that will not start. If you launch
something from a terminal and it cannot find a driver, run it through the
wrapper:

```bash
omarchy-nix exec localsend_app
```

**Hardware or software, probed not assumed.** A driver can answer
`eglInitialize` and still be useless to a GTK app. Under virtio-gpu in a VM,
virgl exposes OpenGL 2.1 on the Wayland platform and no core profile at all; GTK
needs a 3.2 core context, fails to create one, and the window comes up **black**
— the app is running, it just has nothing to draw with. The same machine's
llvmpipe reports 4.6.

So `omarchy-nix gl` asks `eglinfo` what the platform your apps will actually use
can give, and when that is below OpenGL 3.2 core it records
`LIBGL_ALWAYS_SOFTWARE=1` in `~/.local/state/omarchy-nix/gl-env` for
`omarchy-nix exec` to apply. On a real GPU the answer goes the other way and
nothing is overridden. Re-probe after a driver change with `omarchy-nix gl
--probe`; override the verdict with `NIX_APPS_GL_SOFTWARE`.

**Desktop entries are mirrored, not just exposed.** Two problems, one answer.
The launcher watches the applications directories that existed when it started;
`~/.nix-profile/share/applications` is a symlink into the store, and every
install builds a new generation, so that directory is *replaced* rather than
modified. No inotify event fires, and a newly installed app stays invisible
until the shell restarts. And the graphics wiring above has to be attached per
app, which means owning the `Exec` line.

So install, remove and update mirror every Nix `.desktop` into
`~/.local/share/applications` — same filename, so it is the same desktop file id
and `XDG_DATA_HOME` wins over `XDG_DATA_DIRS`, replacing the profile's copy in
the launcher rather than doubling it — with `Exec` routed through `omarchy-nix
exec` and an `X-Omarchy-Nix=true` marker so the plugin only ever prunes its own.
`omarchy-nix sync` redoes it by hand.

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
then marks each row `installed`, `no <system> build`, `renamed upstream` or
`attr gone`. Run it after a big nixpkgs bump.

Those last two are different things, and telling them apart matters. When
nixpkgs renames or discontinues a package it usually leaves the attribute in
place and makes it *throw*, with the answer in the message:

```
jetbrains.idea-community: IntelliJ IDEA Community has been removed as it has
been discontinued by JetBrains. Either switch to 'jetbrains.idea-oss' or
'jetbrains.idea'.
```

Testing that with `tryEval` alone cannot distinguish "deleted" from "still there
and refusing", and calling it "attr gone" sends you looking for a package
sitting right in front of you. So existence is checked with `hasAttr`, which
does not force the value, before anything is evaluated — and when an attribute
does throw, `verify` and `install` print what it said.

### Apps that cannot work here

`apps.json` also carries an `unavailable` list — Spotify, Slack, Discord, Zoom,
Signal Desktop, Android Studio, Postman, LM Studio. These ship `x86_64`-only
Linux binaries upstream, so nixpkgs has no build for anything else either and no
package manager will fix that. `omarchy-nix catalog` prints them with the
suggested alternative (a web app via `omarchy install webapp`, `spotify-player`,
Bruno, Ollama…), and so does the picker's preview pane.

That list is scoped by `unavailable.systems`, because it is not a property of
the app but of the app *on this machine*: on `x86_64-linux` every one of them
installs fine, so the list applies to nothing, `catalog` does not print the
section, and `install spotify` just installs Spotify.

## Configuration

`~/.config/omarchy-nix/config`, sourced on every run:

```bash
NIX_APPS_FLAKE="nixpkgs"          # or github:NixOS/nixpkgs/nixos-unstable to pin
NIX_APPS_ALLOW_UNFREE=1           # 0 refuses VS Code, Obsidian, Sublime, Brave
NIX_APPS_GC_AFTER=1               # 0 stops the gc that follows install and update
# NIX_APPS_GC_KEEP="7d"           # how old a generation must be before gc drops it
# NIX_APPS_CATALOG="$HOME/.config/omarchy-nix/apps.json"   # your own catalogue
# NIX_APPS_INDEX_MAX_AGE=604800   # how stale the package list may get, seconds
# NIX_APPS_UPDATE_MAX_AGE=21600   # how stale the update check may get, seconds
# NIX_APPS_GL_SOFTWARE=1          # force software rendering (0 forces hardware)
```

The bar widget's check interval lives in Omarchy's own plugin settings, not
here.

## Troubleshooting

```bash
omarchy-nix doctor
```

checks the architecture, the Nix binary and daemon, flake support, the session
env file, `XDG_DATA_DIRS`, the mirrored desktop entries, the graphics driver and
which way it probed, the required tooling, and the age of the package list.

**An app installed but does not show in the launcher.** `omarchy-nix sync`
re-mirrors the entries; `doctor` says how many are mirrored. If it is your very
first install, the session env also has to be in place, and that only loads at
login — log out and back in.

**A Nix app dies at startup with an EGL error.** It has no graphics driver:
`omarchy-nix gl`, then launch it again.

**A Nix app opens a black window.** It has a driver but no usable GL context.
`omarchy-nix gl --probe` re-checks and falls back to software rendering when the
hardware path cannot give a 3.2 core context.

**The bar icon never appears.** It only appears when an installed app has a
newer build waiting. `omarchy-nix updates --refresh` answers the same question
in the terminal, and is what the widget reads.

**An app stays listed as outdated after upgrading.** It was installed from a
different flake than the configured one — you changed `NIX_APPS_FLAKE`, or
installed by hand from a pin. `nix profile upgrade` follows the ref each element
came from, so it will never move. `omarchy-nix update` says so; the way out is
`omarchy-nix remove <app> && omarchy-nix install <app>`.

**The package list is out of date.** `omarchy-nix index --refresh`, or
`Install → Nix → Rebuild Index`. It rebuilds itself weekly on its own.

**Disk filling up.** `omarchy-nix gc` drops profile generations older than 30
days and collects garbage.

**Themes look wrong in a Nix app.** GTK/Qt apps from Nix read the system theme
through `XDG_DATA_DIRS`, which `setup` handles; per-app icon themes may still
need the matching Nix package (`adwaita-icon-theme`).

## Remove

```bash
~/.config/omarchy/plugins/dz0ny.nix-apps/uninstall.sh
omarchy plugin remove dz0ny.nix-apps
```

`uninstall.sh` unwires the menu entries, the `~/.local/bin` symlink, the session
env file and the mirrored desktop entries. It deliberately leaves Nix and the
apps you installed alone — removing those is a separate, explicit decision:

```bash
nix profile remove <name>      # one app
/nix/nix-installer uninstall   # Nix itself
rm -rf ~/.local/state/omarchy-nix ~/.config/omarchy-nix
```

## Development

```
bin/omarchy-nix    the CLI; everything the plugin does, it does through this
apps.json          the curated catalogue
NixApps.qml        the bar widget — thin, and only an alert
manifest.json      plugin manifest and widget settings schema
install.sh         wires the CLI onto PATH and the entries into the menu
uninstall.sh       undoes exactly that
menu.jsonc         the menu entries, for pasting by hand
```

The widget deliberately knows almost nothing: it reads `omarchy-nix updates
--brief` and shells out for everything else, so there is one implementation of
each behaviour rather than two that drift.

`bin/omarchy-nix` is `shellcheck -x` clean; please keep it that way.

## License

MIT
