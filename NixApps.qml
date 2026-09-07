import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for the dz0ny.nix-apps plugin.
//
// Modelled on omarchy.system-update: it is an alert, not a launcher. The bar
// stays empty until an installed Nix app actually has a newer build waiting,
// and goes back to empty once you have taken it. Installing and removing live
// in the Omarchy menu, where the fzf pickers have room to work.
//
// It also carries the plugin's own wiring: on load it runs the plugin's
// install.sh, which puts omarchy-nix on PATH and the menu entries in place.
// That is why `omarchy plugin add ... --enable` is all a new machine needs.
BarWidget {
  id: root
  moduleName: "dz0ny.nix-apps"

  // Apps whose current nixpkgs build differs from the one in the profile.
  property int updateCount: 0

  readonly property int checkIntervalSec: (root.settings && root.settings.checkIntervalSec > 0)
    ? root.settings.checkIntervalSec
    : 3600

  // file:///…/plugins/dz0ny.nix-apps/ -> /…/plugins/dz0ny.nix-apps
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")

  function refresh() {
    if (!checkProc.running) checkProc.running = true
  }

  // Ignore the cache and ask nixpkgs again.
  function recheck() {
    if (!recheckProc.running) recheckProc.running = true
  }

  // Opens the picker rather than upgrading everything: an update you did not
  // ask for is how a working machine stops working mid-afternoon.
  function runUpdate() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation 'omarchy-nix menu update'")
  }

  function showStatus() {
    if (root.bar) root.bar.run("omarchy-nix updates --notify")
  }

  visible: root.updateCount > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: registerProc.running = true

  IpcHandler {
    target: "dz0ny.nix-apps"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function check(): void {
      root.broadcast("recheck")
    }
  }

  // Self-registration. install.sh is a no-op when everything is already in
  // place — no rewrite, no backup, no output — so running it on every shell
  // start costs one process and nothing else.
  Process {
    id: registerProc
    command: ["bash", root.pluginDir + "/install.sh", "--quiet", "--no-prompt"]

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("nix-apps/install", text.trim())
    }
  }

  // Reads the cached answer; the CLI recomputes only when that cache has aged
  // past its own limit, so polling here stays cheap.
  Process {
    id: checkProc
    command: ["omarchy-nix", "updates", "--brief"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = parseInt(String(text || "").trim(), 10)
        root.updateCount = isNaN(parsed) ? 0 : parsed
      }
    }

    // Non-zero means "nothing waiting", or no Nix at all. Both are states
    // where this widget has nothing to say.
    onExited: function (exitCode) {
      if (exitCode !== 0) root.updateCount = 0
    }
  }

  Process {
    id: recheckProc
    command: ["omarchy-nix", "updates", "--refresh", "--brief"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = parseInt(String(text || "").trim(), 10)
        root.updateCount = isNaN(parsed) ? 0 : parsed
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) root.updateCount = 0
    }
  }

  Timer {
    interval: root.checkIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-nix
    text: "󱄅"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.updateCount === 1
      ? "1 Nix app update — click to pick what to upgrade"
      : root.updateCount + " Nix app updates — click to pick what to upgrade"

    onPressed: function (b) {
      if (b === Qt.RightButton) root.showStatus()
      else if (b === Qt.MiddleButton) root.recheck()
      else root.runUpdate()
    }
  }
}
