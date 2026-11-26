import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The plugin's always-on half. One instance however many bars there are, so it
// owns what must happen once: the layout and setup windows, connect/disconnect
// notifications, and putting the layout back after Hyprland reloads its config
// (a reload brings every monitor back at its configured position).
//
//   omarchy-shell deskflow layout     open the layout window
//   omarchy-shell deskflow setup      open the setup window
//   omarchy-shell deskflow close      close whichever is open
Scope {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // From this file's URL: the shell strips __sourceDir from third-party manifests.
  readonly property string sourceDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") !== 0) return ""
    try { url = decodeURIComponent(url.substring(7)) } catch (e) { return "" }
    return url.replace(/\/$/, "")
  }
  readonly property string ctl: sourceDir + "/bin/deskflowctl"

  function openLayout() { setupLoader.active = false; layoutLoader.active = true; if (layoutLoader.item) layoutLoader.item.show() }
  function openSetup() { layoutLoader.active = false; setupLoader.active = true; if (setupLoader.item) setupLoader.item.show() }
  function closeAll() {
    if (layoutLoader.item) layoutLoader.item.hide()
    if (setupLoader.item) setupLoader.item.hide()
  }

  IpcHandler {
    target: "deskflow"
    function layout(): void { root.openLayout() }
    function setup(): void { root.openSetup() }
    function close(): void { root.closeAll() }
  }

  Loader {
    id: layoutLoader
    active: false
    source: Qt.resolvedUrl("LayoutWindow.qml")
    onLoaded: { item.ctl = root.ctl; item.closed.connect(function() { layoutLoader.active = false }); item.setupRequested.connect(root.openSetup); item.show() }
  }
  Loader {
    id: setupLoader
    active: false
    source: Qt.resolvedUrl("SetupWindow.qml")
    onLoaded: { item.ctl = root.ctl; item.closed.connect(function() { setupLoader.active = false }); item.layoutRequested.connect(root.openLayout); item.show() }
  }

  // One-time conversion of the pre-1.0 presets file, then the notification watcher.
  Process {
    id: init
    command: [root.ctl, "init"]
    running: root.sourceDir !== ""
    onExited: watcher.running = true
  }
  Process {
    id: watcher
    command: [root.ctl, "watch"]
    onRunningChanged: if (!running) watcherRestart.start()
  }
  Timer { id: watcherRestart; interval: 5000; onTriggered: watcher.running = true }

  // Hyprland reload: debounce, since saving a config can fire several reloads.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded") reapply.restart()
    }
  }
  Timer {
    id: reapply
    interval: 800
    onTriggered: Quickshell.execDetached([root.ctl, "preset", "reapply", "--hypr-only"])
  }

  Component.onDestruction: if (watcher.running) watcher.running = false
}
