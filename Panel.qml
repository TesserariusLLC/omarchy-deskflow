import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget for Deskflow, as server or client. All work goes through
// bin/deskflowctl, which drives omarchy-deskflow.service.
//   Left click: panel with the on/off switch, layout presets, address, gaming mode, start at login.
//   Middle click: toggle Deskflow.  Right click: refresh.
//   Arrange monitors and Setup open windows owned by Service.qml (omarchy-shell deskflow layout|setup).
Panel {
  id: root
  moduleName: "tesserarius.deskflow"
  ipcTarget: "tesserarius.deskflow"
  manageIpc: false

  // From this file's URL; the shell strips __sourceDir from third-party manifests.
  readonly property string script: {
    var url = String(Qt.resolvedUrl("bin/deskflowctl"))
    try { return decodeURIComponent(url.replace(/^file:\/\//, "")) } catch (e) { return "" }
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: (bar && bar.fontFamily) ? bar.fontFamily : Style.font.family
  readonly property string glyph: "\u{f037a}"      // nf-md-monitor_multiple
  readonly property string lockGlyph: "\u{f033e}"  // nf-md-lock
  readonly property string copyGlyph: "\u{f018f}"  // nf-md-content_copy

  property bool loaded: false
  property bool running: false
  property string role: "none"
  property bool installed: true
  property string serverHost: ""
  property bool autostart: false
  property int clients: 0
  property string serverName: ""
  property string ip: ""
  property int port: 24800
  property string fingerprint: ""
  property var leftScreens: []
  property var rightScreens: []
  property var upScreens: []
  property var downScreens: []
  property var peers: []
  property bool busy: action.running
  property string error: ""
  property string copied: ""
  property string preset: ""
  property bool gaming: false
  // Deskflow's Scroll Lock: the pointer can't leave lockedOn until Scroll Lock is pressed again.
  property bool locked: false
  property string lockedOn: ""
  property var presets: []
  property bool presetsOpen: false
  property string pendingPreset: ""
  readonly property string presetName: {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === preset) return presets[i].name
    return preset
  }

  readonly property var clientScreens: leftScreens.concat(rightScreens, upScreens, downScreens)
  readonly property string address: ip !== "" ? ip + ":" + port : "No network"
  // IPs and fingerprints use a sans font: the theme's monospace zero carries a
  // dot that reads as an 8 at small sizes (10.20 looked like 10.28).
  readonly property string numberFont: "sans-serif"
  readonly property string shortFingerprint: fingerprint.length > 24
    ? fingerprint.slice(0, 11) + " … " + fingerprint.slice(-11) : fingerprint
  readonly property bool isClient: role === "client"
  readonly property bool needsSetup: loaded && (!installed || role === "none")
  readonly property string statusText: needsSetup ? "Not set up"
    : !running ? "Off"
    : isClient ? (clients > 0 ? "Connected to " + serverHost : "Connecting to " + (serverHost !== "" ? serverHost : "the server") + "…")
    : (clients === 0 ? "On, waiting for " + (clientScreens.length === 1 ? clientScreens[0] : "computers")
    : (clients === 1 && clientScreens.length === 1 ? "On, " + clientScreens[0] + " connected"
    : "On, " + clients + " connected"))
  readonly property string lockText: locked && !isClient ? "pointer locked" + (lockedOn !== "" ? " to " + lockedOn : "") : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Bounded, plain-string copy of a list coming from the script.
  function names(v) {
    var out = []
    if (!(v instanceof Array)) return out
    for (var i = 0; i < v.length && i < 8; i++) out.push(String(v[i]).slice(0, 40))
    return out
  }
  // A screen counts as connected when it is the only client in the layout
  // and someone is connected; Deskflow doesn't log client names at Info level.
  function screenConnected(n) { return running && clients > 0 && clientScreens.length === 1 && clientScreens[0] === n }
  function openWindow(which) { Quickshell.execDetached(["omarchy-shell", "deskflow", which]); root.close() }
  function screenCaption(n) {
    if (n === serverName) return "this PC"
    if (!running) return "server off"
    if (screenConnected(n)) return peers.length === 1 ? peers[0] : "connected"
    return clientScreens.length === 1 ? "not connected" : (clients > 0 ? "" : "not connected")
  }

  function refresh() { if (!poll.running) poll.running = true }
  function run(args) {
    if (action.running) return
    root.error = ""
    action.command = [root.script].concat(args)
    action.running = true
  }
  // The script checks the live service state, so a stale poll can't invert the toggle.
  // The local flip is only optimistic UI; the next poll corrects it.
  function toggleServer() {
    if (action.running) return
    root.running = !root.running
    run(["toggle"])
  }
  function applyPreset(id) {
    if (action.running || id === "") return
    root.pendingPreset = id
    run(["preset", "apply", id])
  }
  function presetAt(i) { if (i >= 0 && i < presets.length) applyPreset(presets[i].id) }
  function toggleGaming() {
    if (action.running || root.role !== "server") return
    root.gaming = !root.gaming
    run(["gaming", root.gaming ? "on" : "off"])
  }
  function toggleAutostart() { root.autostart = !root.autostart; run(["autostart", root.autostart ? "on" : "off"]) }
  function copy(what, label) {
    if (what === "") return
    Quickshell.execDetached(["wl-copy", "--", what])
    root.copied = label
    copiedTimer.restart()
  }

  Process {
    id: poll
    command: [root.script, "state"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var s = JSON.parse(text)
          root.loaded = true
          root.running = s.running === true
          root.autostart = s.autostart === true
          root.gaming = s.gaming === true
          var lk = s.lock || {}
          root.locked = root.running && lk.locked === true
          root.lockedOn = /^[A-Za-z0-9._-]{0,64}$/.test(String(lk.on || "")) ? String(lk.on || "") : ""
          root.role = /^(server|client|none)$/.test(String(s.role)) ? String(s.role) : "none"
          root.installed = s.installed !== false
          root.serverHost = /^[A-Za-z0-9._:-]{0,253}$/.test(String(s.serverHost || "")) ? String(s.serverHost || "") : ""
          root.clients = (s.peers instanceof Array) ? Math.min(99, s.peers.length) : 0
          root.serverName = String(s.name || "").slice(0, 40)
          root.ip = /^[0-9.]{7,15}$/.test(String(s.ip || "")) ? String(s.ip) : ""
          root.port = Math.max(1, Math.min(65535, parseInt(s.port) || 24800))
          root.fingerprint = /^[0-9A-F:]{0,120}$/.test(String(s.fingerprint || "")) ? String(s.fingerprint) : ""
          var l = s.links || {}
          root.leftScreens = root.names(l.left)
          root.rightScreens = root.names(l.right)
          root.upScreens = root.names(l.up)
          root.downScreens = root.names(l.down)
          root.peers = root.names(s.peers)
          root.preset = /^[a-z0-9-]{0,40}$/.test(String(s.preset || "")) ? String(s.preset) : ""
          var ps = []
          if (s.presets instanceof Array) for (var i = 0; i < s.presets.length && i < 9; i++) {
            var q = s.presets[i] || {}
            if (!/^[a-z0-9-]{1,40}$/.test(String(q.id || ""))) continue
            ps.push({ id: String(q.id), name: String(q.name || q.id).slice(0, 40),
                      note: String(q.note || "").slice(0, 240) })
          }
          root.presets = ps
        } catch (e) {}
      }
    }
  }
  Process {
    id: action
    stderr: StdioCollector { id: actionErr }
    onExited: function(code) {
      if (code !== 0) root.error = "Command failed: " + String(actionErr.text).trim().slice(0, 200)
      root.pendingPreset = ""
      root.refresh()
    }
  }
  Timer {
    interval: root.opened ? 2000 : 5000
    repeat: true; running: true
    onTriggered: root.refresh()
  }
  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copied = "" }

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggleServer() }
    function preset(id: string): void { root.applyPreset(id) }
    function status(): string { return root.statusText + (root.lockText !== "" ? ", " + root.lockText : "") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.locked ? root.lockGlyph : root.glyph
    foreground: root.locked ? root.accent : (root.running ? root.barForeground : Qt.darker(root.barForeground, 1.55))
    tooltipText: "Deskflow: " + root.statusText + (root.lockText !== "" ? " · " + root.lockText + " (Scroll Lock)" : "")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleServer()
      else if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  component Body: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // One monitor preset in the drawer.
  component PresetCard: BorderSurface {
    id: card
    property var preset: ({})
    property int number: 0
    readonly property bool current: preset.id === root.preset
    readonly property bool pending: preset.id === root.pendingPreset
    width: parent ? parent.width : implicitWidth
    implicitHeight: cardColumn.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: current ? Style.selectedFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(current ? "selected" : (cardMouse.containsMouse ? "hover" : "normal"), root.foreground, root.accent)
    opacity: root.busy && !pending ? 0.6 : 1.0
    Column {
      id: cardColumn
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(10)
      width: parent.width - Style.space(20)
      spacing: Style.space(2)
      Body {
        width: parent.width
        text: card.number + "  " + card.preset.name
          + (card.pending ? "   switching…" : (card.current ? "   active" : ""))
        font.bold: true
        color: card.current ? root.foreground : root.dim
      }
      Caption { width: parent.width; text: card.preset.note; visible: card.preset.note !== ""; maximumLineCount: card.current ? 6 : 1; elide: Text.ElideRight }
    }
    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.applyPreset(card.preset.id)
    }
  }

  // One screen in the layout strip.
  component ScreenChip: BorderSurface {
    id: chip
    property string name: ""
    readonly property bool isServer: name === root.serverName
    readonly property bool lit: isServer ? root.running : root.screenConnected(name)
    implicitWidth: Math.max(Style.space(96), chipColumn.implicitWidth + Style.space(20))
    implicitHeight: chipColumn.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: lit ? Style.selectedFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(lit ? "selected" : "normal", root.foreground, root.accent)
    Column {
      id: chipColumn
      anchors.centerIn: parent
      spacing: Style.space(2)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: chip.name
        color: chip.lit ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.screenCaption(chip.name)
        color: root.dim
        font.family: root.numberFont
        font.pixelSize: Style.font.caption
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(800))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.toggleServer()
        else if (t === "a" || t === "A") root.toggleAutostart()
        else if (t === "g" || t === "G") root.toggleGaming()
        else if (t === "c" || t === "C") root.copy(root.ip !== "" ? root.ip : "", "Address")
        else if (t === "o" || t === "O") { Quickshell.execDetached(["deskflow"]); root.close() }
        else if (t === "l" || t === "L") root.openWindow("layout")
        else if (t === "u" || t === "U") root.openWindow("setup")
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "p" || t === "P") root.presetsOpen = !root.presetsOpen
        else if (t >= "1" && t <= "9") root.presetAt(parseInt(t) - 1)
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "Deskflow"
          meta: root.statusText
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.running ? 1.0 : 0.6
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.glyph
              color: root.running ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: serverSwitch
              visible: !root.needsSetup
              checked: root.running
              busy: root.busy
              foreground: hero.foreground
              onToggled: root.toggleServer()
              PanelToolTip {
                visible: serverSwitch.containsMouse
                text: root.running ? "Switch Deskflow off (S)" : "Switch Deskflow on (S)"
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.error
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ── Not set up yet: one way forward.
        Column {
          visible: root.needsSetup
          width: parent.width
          spacing: Style.space(8)
          Caption { width: parent.width; text: !root.installed ? "Deskflow isn't installed yet. Setup installs it and walks you through the rest." : "Choose whether this computer shares its keyboard and mouse (server) or is controlled by another (client)." }
          Button {
            width: parent.width
            text: "Set up Deskflow"
            foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.body
            bordered: true; selected: true
            onClicked: root.openWindow("setup")
          }
        }

        BorderSurface {
          visible: root.locked && !root.isClient
          width: parent.width
          implicitHeight: lockCol.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Style.selectedFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("selected", root.foreground, root.accent)
          Column {
            id: lockCol
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Style.space(10); rightMargin: Style.space(10) }
            spacing: Style.space(2)
            Body { width: parent.width; font.bold: true; wrapMode: Text.WordWrap
                   text: root.lockGlyph + "  Pointer locked to " + (root.lockedOn !== "" ? root.lockedOn : "one computer") }
            Caption { width: parent.width
                      text: root.lockedOn === root.serverName || root.lockedOn === ""
                        ? "Scroll Lock is on and holding the pointer here. The Scroll Lock key only works while the pointer is on another computer, so use Release."
                        : "Scroll Lock is on, so the mouse and keyboard stay on " + root.lockedOn + ". Press Scroll Lock there to release them, or use Release." }
            Button {
              text: "Release"
              tooltipText: "Release the lock (restarts Deskflow)"
              enabled: !root.busy
              bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
              onClicked: { root.locked = false; root.run(["unlock"]) }
            }
          }
        }

        PanelSeparator { visible: !root.needsSetup; foreground: root.foreground }

        // ── Layout presets drawer.
        Column {
          visible: !root.needsSetup
          width: parent.width
          spacing: Style.space(8)
          PanelSectionHeader { text: "LAYOUT"; foreground: root.foreground; fontFamily: root.fontFamily }
          Button {
            id: presetButton
            visible: root.presets.length > 0
            width: parent.width
            text: (root.pendingPreset !== "" ? "Switching…" : (root.presetName !== "" ? root.presetName : "Choose a preset"))
              + "   " + (root.presetsOpen ? "▴" : "▾")
            tooltipText: root.presetsOpen ? "Hide presets (P)" : "Show presets (P)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            bordered: true
            selected: root.presetsOpen
            leftAlign: true
            onClicked: root.presetsOpen = !root.presetsOpen
          }
          Column {
            visible: root.presetsOpen
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.presets
              delegate: PresetCard { preset: modelData; number: index + 1 }
            }
            Caption {
              width: parent.width
              text: "Keys 1–" + root.presets.length + " switch, P opens or closes this list."
            }
          }
          Button {
            width: parent.width
            text: "Arrange monitors…"
            tooltipText: "Drag monitors and computers into place, then save presets (L)"
            foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.openWindow("layout")
          }
        }

        PanelSeparator { visible: !root.needsSetup && !root.isClient; foreground: root.foreground }

        // ── Computers left to right, as linked in the Deskflow layout.
        Column {
          visible: !root.needsSetup && !root.isClient
          width: parent.width
          spacing: Style.space(8)
          PanelSectionHeader { text: "COMPUTERS"; foreground: root.foreground; fontFamily: root.fontFamily }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)
            Repeater {
              model: root.leftScreens.concat([root.serverName], root.rightScreens)
              delegate: Row {
                spacing: Style.space(8)
                Text {
                  visible: index > 0
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "↔"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                ScreenChip { name: modelData }
              }
            }
          }
          Caption {
            visible: root.upScreens.length > 0 || root.downScreens.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (root.upScreens.length > 0 ? "Above: " + root.upScreens.join(", ") : "")
              + (root.upScreens.length > 0 && root.downScreens.length > 0 ? "   " : "")
              + (root.downScreens.length > 0 ? "Below: " + root.downScreens.join(", ") : "")
          }
          Caption {
            visible: root.running && root.clients > 0 && root.clientScreens.length !== 1
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Connected from " + root.peers.join(", ")
            font.family: root.numberFont
          }
        }

        PanelSeparator { visible: !root.needsSetup; foreground: root.foreground }

        Column {
          visible: !root.needsSetup && root.isClient
          width: parent.width
          spacing: Style.space(4)
          PanelSectionHeader { text: "SERVER"; foreground: root.foreground; fontFamily: root.fontFamily }
          Body { text: (root.serverHost !== "" ? root.serverHost : "No server set") + "   (this computer: " + root.serverName + ")"; font.pixelSize: Style.font.body; font.family: root.numberFont }
          Caption { width: parent.width; text: "Change it in Setup (U)." }
        }

        // ── Address other computers connect to, and the TLS fingerprint they are asked to trust.
        Column {
          visible: !root.needsSetup && !root.isClient
          width: parent.width
          spacing: Style.space(6)
          PanelSectionHeader { text: "SERVER ADDRESS"; foreground: root.foreground; fontFamily: root.fontFamily }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Body {
              width: parent.width - copyIp.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.serverName !== "" ? root.address + "   (" + root.serverName + ")" : root.address
              font.pixelSize: Style.font.body
              font.family: root.numberFont
            }
            PanelActionButton {
              id: copyIp
              iconText: root.copyGlyph
              tooltipText: root.copied === "Address" ? "Copied" : "Copy IP (C)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.ip !== ""
              onClicked: root.copy(root.ip, "Address")
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Column {
              width: parent.width - copyFp.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Body { text: "TLS fingerprint" }
              Caption { width: parent.width; text: root.shortFingerprint !== "" ? "SHA256 " + root.shortFingerprint : "No certificate found"; font.family: root.numberFont }
            }
            PanelActionButton {
              id: copyFp
              iconText: root.copyGlyph
              tooltipText: root.copied === "Fingerprint" ? "Copied" : "Copy full fingerprint"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.fingerprint !== ""
              onClicked: root.copy(root.fingerprint, "Fingerprint")
            }
          }
          Caption {
            width: parent.width
            text: "When another computer asks to trust this server, its fingerprint should match."
          }
        }

        PanelSeparator { visible: !root.needsSetup; foreground: root.foreground }

        Row {
          visible: !root.needsSetup && root.role === "server"
          width: parent.width
          spacing: Style.space(8)
          Column {
            width: parent.width - gamingSwitch.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Body { width: parent.width; text: "Gaming mode" }
            Caption {
              width: parent.width
              text: root.gaming ? "Key repeat and the input method are off here, so games on the other computer get clean input."
                                : "Turn on to play games on the other computer: stops held keys arriving as rapid taps, and stuck keys."
            }
          }
          ToggleSwitch {
            id: gamingSwitch
            checked: root.gaming
            busy: root.busy
            foreground: root.foreground
            onToggled: root.toggleGaming()
            PanelToolTip {
              visible: gamingSwitch.containsMouse
              text: "Toggle gaming mode (G)"
              fontFamily: root.fontFamily
            }
          }
        }

        Row {
          visible: !root.needsSetup
          width: parent.width
          spacing: Style.space(8)
          Column {
            width: parent.width - autoSwitch.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Body { width: parent.width; text: "Start at login" }
            Caption {
              width: parent.width
              text: root.autostart ? "Deskflow starts each time you log in." : "Deskflow only runs when you switch it on."
            }
          }
          ToggleSwitch {
            id: autoSwitch
            checked: root.autostart
            busy: root.busy
            foreground: root.foreground
            onToggled: root.toggleAutostart()
            PanelToolTip {
              visible: autoSwitch.containsMouse
              text: "Toggle start at login (A)"
              fontFamily: root.fontFamily
            }
          }
        }

        PanelSeparator { visible: !root.needsSetup; foreground: root.foreground }

        Row {
          visible: !root.needsSetup
          width: parent.width
          spacing: Style.space(8)
          Button {
            width: (parent.width - Style.space(8)) / 2
            text: "Setup"
            tooltipText: "Checklist, pairing and connection help (U)"
            foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.openWindow("setup")
          }
          Button {
            width: (parent.width - Style.space(8)) / 2
            text: "Deskflow window"
            tooltipText: "Deskflow's own settings. Changes apply after switching it off and on (O)"
            foreground: root.foreground; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
            bordered: true
            onClicked: { Quickshell.execDetached(["deskflow"]); root.close() }
          }
        }
      }
    }
  }
}
