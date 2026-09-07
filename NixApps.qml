import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for the dz0ny.nix-apps plugin.
//
// Deliberately thin: everything it knows comes from `omarchy-nix status
// --brief`, and every action it takes is the same omarchy-nix command a user
// would type. The widget is a shortcut, never a second implementation.
BarWidget {
  id: root
  moduleName: "dz0ny.nix-apps"

  // Number of apps in the Nix profile; -1 until the first poll answers.
  property int appCount: -1
  // False while Nix is missing, which is also how the widget stays invisible
  // on a machine that never ran `omarchy-nix setup`.
  property bool nixReady: false

  readonly property int refreshIntervalSec: (root.settings && root.settings.refreshIntervalSec > 0)
    ? root.settings.refreshIntervalSec
    : 300

  readonly property bool hideWhenEmpty: root.settings ? root.settings.hideWhenEmpty === true : false

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function openPicker() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation 'omarchy-nix menu'")
  }

  function runUpdate() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation 'omarchy-nix update'")
  }

  function showStatus() {
    if (root.bar) root.bar.run("omarchy-nix status --notify")
  }

  visible: root.nixReady && (!root.hideWhenEmpty || root.appCount > 0)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "dz0ny.nix-apps"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function install(): void {
      root.broadcast("openPicker")
    }
  }

  Process {
    id: statusProc
    command: ["omarchy-nix", "status", "--brief"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var parsed = parseInt(raw, 10)
        root.appCount = isNaN(parsed) ? 0 : parsed
      }
    }

    // A non-zero exit means "no Nix here", which is a state, not a failure.
    onExited: function (exitCode) {
      root.nixReady = exitCode === 0
      if (!root.nixReady) root.appCount = -1
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
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
    text: "\udb84\udd05"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.appCount >= 0
      ? root.appCount + " Nix app" + (root.appCount === 1 ? "" : "s") + " — click to install, middle-click to update"
      : "Nix apps"

    onPressed: function (b) {
      if (b === Qt.RightButton) root.showStatus()
      else if (b === Qt.MiddleButton) root.runUpdate()
      else root.openPicker()
    }
  }
}
