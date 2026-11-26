pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Setup: pick server or client, name this computer, then work down a checklist
// that `deskflowctl doctor` builds. Each failing check carries its own fix:
// "run" calls deskflowctl, "terminal" opens a terminal for anything that needs sudo.
Item {
  id: root

  property string ctl: ""
  signal closed()
  signal layoutRequested()

  property bool shown: false
  function show() { shown = true; refresh() }
  function hide() { shown = false; stopPair(); closed() }

  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property string fontFamily: Style.font.family

  property var d: ({ checks: [] })
  readonly property string role: String(d.role || "none")
  readonly property var checks: d.checks instanceof Array ? d.checks : []
  readonly property int todo: checks.filter(function(c) { return !c.ok && c.required }).length
  property string message: ""
  property bool messageIsError: false
  property string serverFp: ""      // client: fingerprint fetched from the server
  property string pairedFp: ""      // server: fingerprint of a computer waiting to be trusted
  property bool copiedIp: false
  // IPs and fingerprints use a sans font: the theme's monospace zero carries a
  // dot that reads as an 8 at small sizes (10.20 looked like 10.28).
  readonly property string numberFont: "sans-serif"

  // First three parts of this computer's IPv4, to hint where the server lives.
  readonly property string subnet: {
    var m = /^(\d+\.\d+\.\d+)\.\d+$/.exec(String(d.ip || ""))
    return m ? m[1] + "." : ""
  }

  function say(t, e) { message = t; messageIsError = !!e }
  function refresh() { if (!doctorProc.running) doctorProc.running = true }
  function run(args, after) {
    if (action.running) return
    say("", false)
    action.after = after || ""
    action.command = [ctl].concat(args)
    action.running = true
  }
  function fix(f) {
    if (!f) return
    if (f.kind === "terminal") {
      Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", String(f.arg)])
      say("Finish in the terminal. This list updates on its own.", false)
    } else if (f.arg === "fetch-server-fingerprint") {
      run(["fetch-server-fingerprint"], "fp")
    } else run(String(f.arg).split(" "), "")
  }
  // The fields take the saved values only until the user types in them; the
  // checklist refresh every few seconds must not wipe an unsaved entry.
  function syncFields() {
    if (!nameField.edited) nameField.text = String(d.name || "")
    if (!hostField.edited) hostField.text = String(d.serverHost || "")
  }
  function startPair() { pairedFp = ""; pairProc.running = true }
  function stopPair() { if (pairProc.running) pairProc.running = false }

  Process {
    id: doctorProc
    command: [root.ctl, "doctor"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.d = JSON.parse(text); root.syncFields() } catch (e) {} }
    }
  }
  Timer { interval: 3000; repeat: true; running: root.shown; onTriggered: root.refresh() }

  Process {
    id: action
    property string after: ""
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onExited: function(code) {
      if (code !== 0) root.say(String(err.text).trim().split("\n").slice(-1)[0].slice(0, 200) || "That didn't work.", true)
      else if (after === "fp") root.serverFp = String(out.text).trim().slice(0, 100)
      else if (after === "trusted-server") { root.serverFp = ""; root.say("Server trusted. Switch Deskflow on to connect.", false) }
      else if (after === "trusted-client") { root.pairedFp = ""; root.say("Trusted. That computer connects on its next try.", false) }
      root.refresh()
    }
  }
  Process {
    id: pairProc
    command: [root.ctl, "pair"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var j = JSON.parse(line)
          if (!/^[0-9A-F:]{95}$/.test(String(j.fingerprint))) return
          if (j.trusted === true) root.say("That computer is already trusted, so it connects without pairing. Nothing else to do.", false)
          else root.pairedFp = String(j.fingerprint)
        } catch (e) {}
      }
    }
    onExited: if (root.pairedFp === "" && root.message === "") root.say("Nothing new connected within two minutes.", false)
  }

  OverlayWindow {
    id: window
    shown: root.shown
    WlrLayershell.namespace: "deskflow-setup"

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
    MouseArea { anchors.fill: parent; onClicked: root.hide() }

    Rectangle {
      anchors.centerIn: parent
      width: Math.round(Math.min(Style.space(760), window.width * 0.92))
      height: Math.round(Math.min(Style.space(720), window.height * 0.9))
      color: root.bg
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.hairline
      MouseArea { anchors.fill: parent }

      FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onEscapePressed: root.hide()

        Item {
          id: header
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(18) }
          height: Style.space(40)
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Label { text: "Set up Deskflow"; font.pixelSize: Style.font.heading; font.bold: true }
            Label {
              color: root.dim
              text: root.todo === 0 && root.role !== "none" ? "Everything needed is in place." : root.todo + " step" + (root.todo === 1 ? "" : "s") + " left."
            }
          }
          Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: Style.space(8)
            Button { text: "Arrange monitors"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.layoutRequested() }
            Button { text: "Close"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.hide() }
          }
        }

        Flickable {
          id: body
          anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; margins: Style.space(18) }
          contentHeight: col.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: col
            width: body.width
            spacing: Style.space(14)

            // ── role
            Column {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader { text: "THIS COMPUTER IS THE"; foreground: root.fg; fontFamily: root.fontFamily }
              Row {
                width: parent.width
                spacing: Style.space(10)
                RoleCard {
                  value: "server"
                  title: "Server"
                  detail: "Its keyboard and mouse control the other computers. Pick this on the computer you sit at."
                }
                RoleCard {
                  value: "client"
                  title: "Client"
                  detail: "It is controlled from another computer's keyboard and mouse."
                }
              }
            }

            // ── name (and server address for a client)
            Column {
              visible: root.role !== "none"
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "NAMES"; foreground: root.fg; fontFamily: root.fontFamily }
              Row {
                width: parent.width
                spacing: Style.space(8)
                Label { width: Style.space(150); anchors.verticalCenter: parent.verticalCenter; text: "This computer's name" }
                TextField {
                  id: nameField
                  property bool edited: false
                  onTextEdited: edited = true
                  width: parent.width - Style.space(150) - nameSave.width - Style.space(16)
                  foreground: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body
                  validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9._-]{1,64}/ }
                  onAccepted: if (acceptableInput && text !== root.d.name) { edited = false; root.run(["name", text], "") }
                }
                Button {
                  id: nameSave
                  text: "Save"
                  enabled: nameField.acceptableInput && nameField.text !== String(root.d.name || "")
                  bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                  onClicked: { nameField.edited = false; root.run(["name", nameField.text], "") }
                }
              }
              Row {
                visible: root.role === "client"
                width: parent.width
                spacing: Style.space(8)
                Label { width: Style.space(150); anchors.verticalCenter: parent.verticalCenter; text: "Server address" }
                TextField {
                  id: hostField
                  property bool edited: false
                  onTextEdited: edited = true
                  width: parent.width - Style.space(150) - hostSave.width - Style.space(16)
                  font.family: root.numberFont
                  // A hint that stays while what's typed still matches its start.
                  readonly property string hint: root.subnet !== "" ? root.subnet + "x" : "192.168.1.x"
                  TextMetrics { id: typed; font: hostField.font; text: hostField.text }
                  Text {
                    visible: hostField.hint.indexOf(hostField.text) === 0 && hostField.text.length < hostField.hint.length
                    x: hostField.leftPadding + typed.advanceWidth
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: hostField.hint.slice(hostField.text.length) + (hostField.text === "" ? "   (the server's IP)" : "")
                    color: hostField.placeholderTextColor
                    font: hostField.font
                  }
                  foreground: root.fg; font.pixelSize: Style.font.body
                  validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9._:-]{1,253}/ }
                  onAccepted: if (acceptableInput && text !== root.d.serverHost) { edited = false; root.run(["server-host", text], "") }
                }
                Button {
                  id: hostSave
                  text: "Save"
                  enabled: hostField.acceptableInput && hostField.text !== String(root.d.serverHost || "")
                  bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                  onClicked: { hostField.edited = false; root.run(["server-host", hostField.text], "") }
                }
              }
              Label {
                width: parent.width
                wrapMode: Text.WordWrap
                color: root.dim
                text: root.role === "server"
                  ? "Each other computer uses its own name. Add them in Arrange monitors under the same names."
                  : "Enter just the IP; port " + (root.d.port || 24800) + " is added for you. Deskflow on the server suggests one, but if it has several networks, pick the one on the same network as this computer"
                    + (root.d.ip ? " (" + root.d.ip + ")" : "") + ". The server's layout must include this computer's name."
              }
            }

            // ── checklist
            Column {
              visible: root.checks.length > 0
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "CHECKLIST"; foreground: root.fg; fontFamily: root.fontFamily }
              Repeater {
                model: root.checks
                delegate: Item {
                  id: row
                  required property var modelData
                  width: col.width
                  implicitHeight: Math.max(rowText.implicitHeight, fixBtn.implicitHeight) + Style.space(6)
                  Label {
                    id: mark
                    anchors { left: parent.left; top: parent.top; topMargin: Style.space(3) }
                    width: Style.space(22)
                    text: row.modelData.ok ? "✓" : (row.modelData.required ? "✕" : "·")
                    color: row.modelData.ok ? root.accent : (row.modelData.required ? root.urgent : root.dim)
                    font.bold: true
                  }
                  Column {
                    id: rowText
                    anchors { left: mark.right; right: fixBtn.left; rightMargin: Style.space(10); top: parent.top }
                    spacing: Style.space(1)
                    Label { width: parent.width; wrapMode: Text.WordWrap; text: String(row.modelData.title || "").slice(0, 120); font.bold: !row.modelData.ok }
                    Label { width: parent.width; wrapMode: Text.WordWrap; color: root.dim; font.pixelSize: Style.font.caption; font.family: root.numberFont; text: String(row.modelData.detail || "").slice(0, 240); visible: text !== "" }
                  }
                  Button {
                    id: fixBtn
                    anchors { right: parent.right; top: parent.top }
                    visible: !row.modelData.ok && !!row.modelData.fix
                    text: row.modelData.fix ? String(row.modelData.fix.label).slice(0, 24) + (row.modelData.fix.kind === "terminal" ? "…" : "") : ""
                    tooltipText: row.modelData.fix && row.modelData.fix.kind === "terminal" ? "Opens a terminal: " + String(row.modelData.fix.arg).slice(0, 120) : ""
                    enabled: !action.running
                    bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                    onClicked: root.fix(row.modelData.fix)
                  }
                }
              }
            }

            // ── client: confirm the server's fingerprint
            Column {
              visible: root.serverFp !== ""
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "SERVER FINGERPRINT"; foreground: root.fg; fontFamily: root.fontFamily }
              Label { width: parent.width; wrapMode: Text.WrapAnywhere; text: root.serverFp; font.family: root.numberFont }
              Label { width: parent.width; wrapMode: Text.WordWrap; color: root.dim; text: "Trust it only if it matches the fingerprint in the Deskflow panel on the server." }
              Row {
                spacing: Style.space(8)
                Button { text: "It matches, trust it"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.run(["trust-server", root.serverFp], "trusted-server") }
                Button { text: "Cancel"; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.serverFp = "" }
              }
            }

            // ── server: how to connect another computer, and pairing
            Column {
              visible: root.role === "server"
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "CONNECT ANOTHER COMPUTER"; foreground: root.fg; fontFamily: root.fontFamily }
              Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "1. Install Deskflow on it (deskflow.org, or the deskflow package on Linux).\n"
                    + "2. Set it to use another computer's keyboard and mouse (client), and give it a name.\n"
                    + "3. Enter this server's address: " + (root.d.ip ? root.d.ip : "this computer's IP address") + "\n"
                    + "4. When it asks you to trust this server, compare the fingerprint below.\n"
                    + "5. New computers only: click Pair here, then connect from it. A computer paired before is already trusted and reconnects on its own."
              }
              Row {
                spacing: Style.space(8)
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Address"; color: root.dim; width: Style.space(80) }
                Label { anchors.verticalCenter: parent.verticalCenter; text: (root.d.ip || "unknown") + ":" + (root.d.port || 24800); font.bold: true; font.family: root.numberFont }
                Button {
                  text: root.copiedIp ? "Copied" : "Copy"
                  enabled: !!root.d.ip
                  foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.caption
                  onClicked: { Quickshell.execDetached(["wl-copy", "--", String(root.d.ip)]); root.copiedIp = true; copiedTimer.restart() }
                }
              }
              Row {
                width: parent.width
                spacing: Style.space(8)
                Label { text: "Fingerprint"; color: root.dim; width: Style.space(80) }
                Label { width: parent.width - Style.space(88); wrapMode: Text.WrapAnywhere; text: String(root.d.fingerprint || "none yet"); font.family: root.numberFont; font.pixelSize: Style.font.caption }
              }
              Label {
                visible: (root.d.connected || []).length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                font.family: root.numberFont
                text: "Connected now: " + (root.d.connected || []).map(function(c) {
                  return String(c.name).slice(0, 64) + (c.name !== c.ip ? " (" + String(c.ip).slice(0, 45) + ")" : "") }).join(", ")
                  + ". It's trusted, so no pairing is needed."
              }
              Row {
                spacing: Style.space(8)
                Button {
                  text: pairProc.running ? "Waiting for a computer… (Cancel)" : "Pair"
                  tooltipText: "Waits up to two minutes for a computer this server doesn't trust yet. Deskflow restarts once to log fingerprints."
                  bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                  onClicked: pairProc.running ? root.stopPair() : root.startPair()
                }
              }
              Column {
                visible: root.pairedFp !== ""
                width: parent.width
                spacing: Style.space(6)
                Label { width: parent.width; wrapMode: Text.WordWrap; text: "A computer tried to connect with this fingerprint:"; font.bold: true }
                Label { width: parent.width; wrapMode: Text.WrapAnywhere; text: root.pairedFp; font.family: root.numberFont }
                Label { width: parent.width; wrapMode: Text.WordWrap; color: root.dim; text: "Trust it only if it matches the fingerprint Deskflow shows on that computer." }
                Row {
                  spacing: Style.space(8)
                  Button { text: "It matches, trust it"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.run(["trust-client", root.pairedFp], "trusted-client") }
                  Button { text: "Ignore"; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.pairedFp = "" }
                }
              }
            }
          }
        }

        Item {
          id: footer
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(18) }
          height: Math.max(Style.space(28), msg.implicitHeight)
          Label {
            id: msg
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            wrapMode: Text.WordWrap
            color: root.messageIsError ? root.urgent : root.dim
            text: root.message !== "" ? root.message : (action.running ? "Working…" : "Fixes that need your password open in a terminal.")
          }
        }
      }
    }
  }

  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedIp = false }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component RoleCard: BorderSurface {
    id: rc
    property string value: ""
    property string title: ""
    property string detail: ""
    readonly property bool chosen: root.role === value
    width: (col.width - Style.space(10)) / 2
    implicitHeight: rcCol.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: chosen ? Style.selectedFillFor(root.fg, root.accent) : Style.normalFillFor(root.fg, root.accent)
    borderSpec: Border.controlSpec(chosen ? "selected" : (rcMouse.containsMouse ? "hover" : "normal"), root.fg, root.accent)
    Column {
      id: rcCol
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(12) }
      spacing: Style.space(4)
      Label { text: rc.title + (rc.chosen ? "   ✓" : ""); font.bold: true; font.pixelSize: Style.font.body }
      Label { width: parent.width; wrapMode: Text.WordWrap; color: root.dim; text: rc.detail }
    }
    MouseArea {
      id: rcMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!rc.chosen) root.run(["role", rc.value], "")
    }
  }
}
