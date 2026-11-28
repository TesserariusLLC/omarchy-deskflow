pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Layout.js" as Geo

// Drag this computer's monitors and the other computers into place, apply it,
// and save it as a preset. Every change goes through bin/deskflowctl.
Item {
  id: root

  property string ctl: ""
  signal closed()
  signal setupRequested()

  function show() { shown = true; load() }
  function hide() { shown = false; closed() }
  property bool shown: false

  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color hairline: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property string fontFamily: Style.font.family

  // ---------------------------------------------------------------- model
  property string myName: ""
  property string role: "server"
  property bool ddcAvailable: false
  property var ddc: ({})
  property var monitors: []      // {key, output, serial, label, w, h, x, y, enabled, handoff}
  property var others: []        // {name, x, y, w, h}
  property var known: []         // computers seen or saved: {name, width, height, seen}
  property var presets: []
  property string currentPreset: ""
  property string loadedPreset: ""
  property bool dirty: false
  property bool busy: action.running
  property string message: ""
  property bool messageIsError: false
  property string selKind: ""    // "monitor" | "computer" | ""
  property int selIndex: -1
  property string saveName: ""
  property var probe: null       // {key, current, inputs: [{code, label}]}
  property bool probing: probeProc.running

  readonly property var selMonitor: selKind === "monitor" && selIndex >= 0 && selIndex < monitors.length ? monitors[selIndex] : null
  readonly property var selComputer: selKind === "computer" && selIndex >= 0 && selIndex < others.length ? others[selIndex] : null
  readonly property var active: monitors.filter(function(m) { return m.enabled && !m.handoff })
  readonly property var meBox: Geo.bbox(active)
  readonly property var issues: Geo.problems(monitors, others)
  readonly property bool hasErrors: issues.some(function(p) { return p.level === "error" })
  readonly property bool isServer: role !== "client"

  function clone(o) { return JSON.parse(JSON.stringify(o)) }
  function setMonitors(list) { monitors = list; dirty = true }
  function setOthers(list) { others = list; dirty = true }
  function say(text, isError) { message = text; messageIsError = !!isError }

  function load() {
    say("", false)
    if (!loadProc.running) loadProc.running = true
  }

  // Monitors from Hyprland; positions from the loaded preset when it names them.
  function fromData(d, presetId) {
    myName = String(d.name || "")
    role = String(d.role || "server")
    ddcAvailable = d.ddcAvailable === true
    ddc = d.ddc || {}
    known = d.computers instanceof Array ? d.computers : []
    presets = d.presets instanceof Array ? d.presets : []
    currentPreset = String(d.current || "")
    var p = null
    for (var i = 0; i < presets.length; i++) if (presets[i].id === presetId) p = presets[i]
    var outs = d.outputs instanceof Array ? d.outputs : []
    var ms = []
    for (var j = 0; j < outs.length && j < 16; j++) {
      var o = outs[j]
      var m = { key: String(o.key), output: String(o.output), serial: String(o.serial || ""),
                label: String(o.model || o.output).slice(0, 40), port: String(o.output),
                w: Number(o.lw) || 1920, h: Number(o.lh) || 1080,
                x: Number(o.x) || 0, y: Number(o.y) || 0, enabled: !o.disabled, handoff: false }
      if (p) {
        var pm = (p.monitors || []).filter(function(q) { return q.key === m.key || (!q.key && q.output === m.output) })[0]
        if (pm) { m.x = Number(pm.x) || 0; m.y = Number(pm.y) || 0; m.handoff = pm.handoff === true; m.enabled = pm.enabled !== false || m.handoff }
      }
      ms.push(m)
    }
    // A monitor that is off or handed off still needs somewhere sensible on the canvas.
    var on = ms.filter(function(q) { return q.enabled && !q.handoff })
    var box = Geo.bbox(on) || { x: 0, y: 0, w: 0, h: 0 }
    // Presets keep a handed-off monitor wherever it last was, often on top of the
    // ones that stay, so set any that would overlap on a shelf below the layout.
    var shelf = box.x
    for (var k = 0; k < ms.length; k++) {
      var mk = ms[k]
      if (mk.enabled && !mk.handoff) continue
      if (p && !on.some(function(q) { return Geo.overlaps(q, mk) })) continue
      mk.x = shelf; mk.y = box.y + box.h + 300; shelf += mk.w + 100
    }
    monitors = ms

    var me = Geo.bbox(ms.filter(function(q) { return q.enabled && !q.handoff }))
    if (me) me.name = myName
    var os = []
    var links = p ? (p.links || []) : (d.links || [])
    var screens = p ? (p.screens || []) : []
    for (var s = 0; s < screens.length; s++)
      os.push({ name: String(screens[s].name), x: Number(screens[s].x), y: Number(screens[s].y),
                w: Number(screens[s].width) || 1920, h: Number(screens[s].height) || 1080 })
    // Presets from before 1.0, and the live links file, name computers without placing them.
    if (me) for (var l = 0; l < links.length; l++) {
      var n = links[l].from === myName ? links[l].to : ""
      if (!n || os.some(function(q) { return q.name === n })) continue
      var size = sizeOf(n)
      var pos = Geo.placeFromLinks(me, n, links, size.w, size.h)
      os.push({ name: n, x: pos.x, y: pos.y, w: size.w, h: size.h })
    }
    others = isServer ? os : []
    loadedPreset = p ? p.id : ""
    saveName = p ? p.name : ""
    dirty = false
    probe = null
    if (selKind === "monitor" && selIndex >= monitors.length) selKind = ""
    if (selKind === "computer" && selIndex >= others.length) selKind = ""
    fitView()
  }
  function sizeOf(name) {
    for (var i = 0; i < known.length; i++) if (known[i].name === name) return { w: Number(known[i].width) || 1920, h: Number(known[i].height) || 1080 }
    return { w: 1920, h: 1080 }
  }

  function layoutJson(extra) {
    var me = meBox ? { name: myName, x: meBox.x, y: meBox.y, w: meBox.w, h: meBox.h } : null
    var screens = me ? [me].concat(others) : others
    var out = {
      monitors: monitors.map(function(m) { return { key: m.key, output: m.output, x: Math.round(m.x), y: Math.round(m.y), enabled: m.enabled, handoff: m.handoff } }),
      screens: others.map(function(o) { return { name: o.name, x: Math.round(o.x), y: Math.round(o.y), width: Math.round(o.w), height: Math.round(o.h) } }),
      links: isServer ? Geo.links(screens) : []
    }
    for (var k in extra) out[k] = extra[k]
    return JSON.stringify(out)
  }

  function run(args, after) {
    if (action.running) return
    action.after = after || ""
    action.command = [ctl].concat(args)
    action.running = true
  }
  function apply() {
    if (hasErrors) return
    say("Applying…", false)
    run(["apply", layoutJson({})], "applied")
  }
  function applyPreset(id) { say("Applying…", false); run(["preset", "apply", id], "applied-preset:" + id) }
  function savePreset() {
    var name = saveName.trim()
    if (name === "") { say("Give the preset a name first.", true); return }
    var sameAsLoaded = false
    for (var i = 0; i < presets.length; i++) if (presets[i].id === loadedPreset && presets[i].name === name) sameAsLoaded = true
    var extra = { name: name }
    if (sameAsLoaded) extra.id = loadedPreset
    var args = ["preset", "save", layoutJson(extra)]
    if (!dirty) args.push("--current")
    run(args, "saved")
  }
  function deletePreset(id) { run(["preset", "delete", id], "deleted") }

  function addComputer(name, w, h) {
    var base = String(name || "").replace(/[^A-Za-z0-9._-]/g, "").slice(0, 64)
    if (base === "") base = "LAPTOP"
    var n = base, i = 2
    while (n === myName || others.some(function(o) { return o.name === n })) n = base + "-" + (i++)
    var me = meBox || { x: 0, y: 0, w: 0, h: 0 }
    var list = clone(others)
    list.push({ name: n, x: me.x - w, y: me.y + me.h - h, w: w, h: h })
    setOthers(list)
    selKind = "computer"; selIndex = list.length - 1
    fitView()
  }
  function updateComputer(i, patch) {
    var list = clone(others)
    for (var k in patch) list[i][k] = patch[k]
    setOthers(list)
  }
  function removeComputer(i) {
    var list = clone(others); list.splice(i, 1); setOthers(list); selKind = ""; fitView()
  }
  function updateMonitor(i, patch) {
    var list = clone(monitors)
    for (var k in patch) list[i][k] = patch[k]
    setMonitors(list)
  }

  // ---------------------------------------------------------------- processes
  Process {
    id: loadProc
    command: [root.ctl, "monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var d = JSON.parse(text); root.fromData(d, root.loadedPreset !== "" ? root.loadedPreset : String(d.current || "")) }
        catch (e) { root.say("Could not read the monitors: " + String(e).slice(0, 120), true) }
      }
    }
  }
  Process {
    id: action
    property string after: ""
    stdout: StdioCollector { id: actionOut }
    stderr: StdioCollector { id: actionErr }
    onExited: function(code) {
      var err = String(actionErr.text).trim().split("\n").filter(function(l) { return l !== "" }).slice(-2).join(" ").slice(0, 220)
      if (code !== 0) { root.say(err !== "" ? err : "That didn't work.", true); return }
      if (after === "applied") { root.dirty = false; root.say(err !== "" ? "Applied, with a warning: " + err : "Applied. Save it as a preset to switch back to it later.", err !== "") }
      else if (after.indexOf("applied-preset:") === 0) { root.loadedPreset = after.slice(15); root.say(err !== "" ? "Applied, with a warning: " + err : "Preset applied.", err !== ""); root.load() }
      else if (after === "saved") { root.loadedPreset = String(actionOut.text).trim(); root.say("Saved.", false); root.load() }
      else if (after === "deleted") { root.loadedPreset = ""; root.say("Preset deleted.", false); root.load() }
      else if (after === "ddc") { root.probe = null; root.say("Input switching saved for this monitor.", false); root.load() }
    }
  }
  Process {
    id: probeProc
    property string key: ""
    stdout: StdioCollector {
      id: probeOut
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          var inputs = (d.inputs instanceof Array ? d.inputs : []).slice(0, 16).filter(function(x) { return /^0x[0-9a-f]{1,2}$/.test(String(x.code)) })
            .map(function(x) { return { value: String(x.code), label: String(x.label || x.code).slice(0, 40) + "  (" + x.code + ")" } })
          if (inputs.length === 0) { root.say("That monitor didn't list any inputs over DDC/CI.", true); return }
          var cur = /^0x[0-9a-f]{1,2}$/.test(String(d.current)) ? String(d.current) : inputs[0].value
          var other = inputs.filter(function(x) { return x.value !== cur })[0]
          root.probe = { key: probeProc.key, inputs: inputs, desktop: cur, other: other ? other.value : cur }
        } catch (e) {}
      }
    }
    stderr: StdioCollector { id: probeErr }
    onExited: function(code) { if (code !== 0) root.say(String(probeErr.text).trim().slice(0, 200) || "ddcutil couldn't reach that monitor.", true) }
  }

  // ---------------------------------------------------------------- view transform
  // Frozen while dragging, so the canvas doesn't rescale under the pointer.
  property real viewScale: 0.05
  property real viewX: 0
  property real viewY: 0
  property bool dragging: false
  function fitView() {
    if (dragging) return
    var all = monitors.concat(others)
    var b = Geo.bbox(all)
    if (!b || canvas.width <= 0) return
    var pad = Style.space(40)
    viewScale = Math.min((canvas.width - 2 * pad) / Math.max(1, b.w), (canvas.height - 2 * pad) / Math.max(1, b.h))
    viewX = b.x - (canvas.width / viewScale - b.w) / 2
    viewY = b.y - (canvas.height / viewScale - b.h) / 2
  }

  // ---------------------------------------------------------------- window
  OverlayWindow {
    id: window
    shown: root.shown
    WlrLayershell.namespace: "deskflow-layout"

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
    MouseArea { anchors.fill: parent; onClicked: root.hide() }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.round(Math.min(Style.space(1080), window.width * 0.92))
      height: Math.round(Math.min(Style.space(700), window.height * 0.9))
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
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Delete && root.selComputer) { root.removeComputer(root.selIndex); event.accepted = true }
        }

        // ── header
        Item {
          id: header
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(18) }
          height: Style.space(40)
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Label { text: "Arrange monitors"; font.pixelSize: Style.font.heading; font.bold: true }
            Label {
              color: root.dim
              text: root.isServer
                ? "Drag your monitors and the other computers. The pointer crosses wherever two edges touch."
                : "Drag your monitors into place. As a client, the server decides where this computer sits."
            }
          }
          Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: Style.space(8)
            Button { text: "Setup"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.setupRequested() }
            Button { text: "Close"; bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall; onClicked: root.hide() }
          }
        }

        // ── canvas
        Rectangle {
          id: canvas
          anchors { left: parent.left; top: header.bottom; bottom: footer.top; right: side.left; margins: Style.space(18) }
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
          radius: Style.cornerRadius
          border.width: 1
          border.color: root.hairline
          clip: true
          onWidthChanged: root.fitView()
          onHeightChanged: root.fitView()
          MouseArea { anchors.fill: parent; onClicked: { root.selKind = ""; keys.forceActiveFocus() } }

          Label {
            visible: root.monitors.length === 0
            anchors.centerIn: parent
            color: root.dim
            text: loadProc.running ? "Reading monitors…" : "No monitors found."
          }

          // This computer's outline: what Deskflow treats as one screen.
          Rectangle {
            visible: root.isServer && root.meBox !== null && root.others.length > 0
            x: root.meBox ? (root.meBox.x - root.viewX) * root.viewScale - 4 : 0
            y: root.meBox ? (root.meBox.y - root.viewY) * root.viewScale - 4 : 0
            width: root.meBox ? root.meBox.w * root.viewScale + 8 : 0
            height: root.meBox ? root.meBox.h * root.viewScale + 8 : 0
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
            radius: Style.cornerRadius
            Label {
              anchors { left: parent.left; bottom: parent.top; bottomMargin: 2 }
              text: root.myName + " (this computer)"
              color: root.dim
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.monitors.length
            delegate: Box {
              required property int index
              readonly property var m: root.monitors[index] || ({})
              kind: "monitor"
              boxIndex: index
              lx: m.x || 0; ly: m.y || 0; lw: m.w || 1; lh: m.h || 1
              title: m.label || ""
              subtitle: (m.port || "") + "  " + (m.w || 0) + "×" + (m.h || 0)
              note: m.handoff ? "shows the other computer" : (!m.enabled ? "off" : "")
              faded: !m.enabled || m.handoff
              tint: root.fg
            }
          }
          Repeater {
            model: root.others.length
            delegate: Box {
              required property int index
              readonly property var o: root.others[index] || ({})
              kind: "computer"
              boxIndex: index
              lx: o.x || 0; ly: o.y || 0; lw: o.w || 1; lh: o.h || 1
              title: o.name || ""
              subtitle: "other computer  " + (o.w || 0) + "×" + (o.h || 0)
              note: ""
              faded: false
              tint: root.accent
            }
          }
        }

        // ── side panel
        Flickable {
          id: side
          anchors { right: parent.right; top: header.bottom; bottom: footer.top; topMargin: Style.space(18); bottomMargin: Style.space(18); rightMargin: Style.space(18) }
          width: Style.space(290)
          contentHeight: sideColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: sideColumn
            width: side.width
            spacing: Style.space(10)

            // Selected monitor
            Column {
              visible: root.selMonitor !== null
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "MONITOR"; foreground: root.fg; fontFamily: root.fontFamily }
              Label { text: root.selMonitor ? root.selMonitor.label + "  ·  " + root.selMonitor.port : ""; font.bold: true }
              Label { color: root.dim; text: root.selMonitor ? root.selMonitor.w + "×" + root.selMonitor.h + " at " + Math.round(root.selMonitor.x) + ", " + Math.round(root.selMonitor.y) : "" }
              SwitchRow {
                text: "On"
                detail: "Off leaves it dark and out of the layout."
                checked: root.selMonitor ? root.selMonitor.enabled && !root.selMonitor.handoff : false
                onToggled: root.updateMonitor(root.selIndex, { enabled: !(root.selMonitor.enabled && !root.selMonitor.handoff), handoff: false })
              }
              SwitchRow {
                readonly property var cfg: root.selMonitor ? root.ddc[root.selMonitor.key] : null
                visible: root.ddcAvailable && root.selMonitor !== null && root.selMonitor.serial !== ""
                enabled: !!(cfg && cfg.other)
                text: "Show the other computer"
                detail: cfg && cfg.other ? "Switches its input to " + cfg.other + " and takes it out of this layout."
                                         : "Set up input switching below first."
                checked: root.selMonitor ? root.selMonitor.handoff : false
                onToggled: root.updateMonitor(root.selIndex, { handoff: !root.selMonitor.handoff, enabled: true })
              }
              Column {
                visible: root.ddcAvailable && root.selMonitor !== null && root.selMonitor.serial !== ""
                width: parent.width
                spacing: Style.space(6)
                Label {
                  readonly property var cfg: root.selMonitor ? root.ddc[root.selMonitor.key] : null
                  width: parent.width
                  color: root.dim
                  wrapMode: Text.WordWrap
                  text: cfg ? "Input switching: this computer " + cfg.desktop + (cfg.other ? ", other computer " + cfg.other : ", no other input") + "."
                            : "Input switching isn't set up for this monitor."
                }
                Button {
                  visible: !root.probe || root.probe.key !== (root.selMonitor ? root.selMonitor.key : "")
                  width: parent.width
                  text: root.probing ? "Asking the monitor…" : "Detect inputs"
                  tooltipText: "Reads the inputs this monitor offers over DDC/CI. Takes a few seconds."
                  bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                  onClicked: if (!probeProc.running && root.selMonitor) {
                    probeProc.key = root.selMonitor.key
                    probeProc.command = [root.ctl, "ddc-probe", root.selMonitor.serial]
                    probeProc.running = true
                  }
                }
                Column {
                  visible: root.probe !== null && root.selMonitor !== null && root.probe.key === root.selMonitor.key
                  width: parent.width
                  spacing: Style.space(6)
                  Dropdown {
                    id: desktopInput
                    width: parent.width
                    label: "Input this computer is on"
                    options: root.probe ? root.probe.inputs : []
                    value: root.probe ? root.probe.desktop : ""
                    foreground: root.fg; fontFamily: root.fontFamily
                    onChanged: function(v) { var p = root.clone(root.probe); p.desktop = v; root.probe = p }
                  }
                  Dropdown {
                    width: parent.width
                    label: "Input the other computer is on"
                    options: root.probe ? [{ value: "none", label: "None (never switch)" }].concat(root.probe.inputs) : []
                    value: root.probe ? root.probe.other : ""
                    foreground: root.fg; fontFamily: root.fontFamily
                    onChanged: function(v) { var p = root.clone(root.probe); p.other = v; root.probe = p }
                  }
                  Button {
                    width: parent.width
                    text: "Save input switching"
                    bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                    onClicked: root.run(["ddc-set", root.probe.key, root.probe.desktop, root.probe.other === root.probe.desktop ? "none" : root.probe.other], "ddc")
                  }
                }
              }
            }

            // Selected computer
            Column {
              visible: root.selComputer !== null
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "OTHER COMPUTER"; foreground: root.fg; fontFamily: root.fontFamily }
              Label { width: parent.width; color: root.dim; wrapMode: Text.WordWrap; text: "Use the exact name set in Deskflow on that computer." }
              TextField {
                id: nameField
                width: parent.width
                text: root.selComputer ? root.selComputer.name : ""
                placeholderText: "Computer name"
                foreground: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9._-]{1,64}/ }
                onEditingFinished: if (root.selComputer && text !== root.selComputer.name && text !== "" && text !== root.myName
                                       && !root.others.some(function(o) { return o.name === text })) root.updateComputer(root.selIndex, { name: text })
              }
              Row {
                width: parent.width
                spacing: Style.space(6)
                TextField {
                  id: wField
                  width: (parent.width - Style.space(6)) / 2
                  text: root.selComputer ? String(root.selComputer.w) : ""
                  placeholderText: "Width"
                  foreground: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body
                  validator: IntValidator { bottom: 320; top: 16384 }
                  onEditingFinished: if (root.selComputer && acceptableInput) root.updateComputer(root.selIndex, { w: parseInt(text) })
                }
                TextField {
                  width: (parent.width - Style.space(6)) / 2
                  text: root.selComputer ? String(root.selComputer.h) : ""
                  placeholderText: "Height"
                  foreground: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body
                  validator: IntValidator { bottom: 240; top: 16384 }
                  onEditingFinished: if (root.selComputer && acceptableInput) root.updateComputer(root.selIndex, { h: parseInt(text) })
                }
              }
              Label {
                width: parent.width
                color: root.dim
                wrapMode: Text.WordWrap
                text: "Its whole screen area, all its monitors together. Size only changes where along an edge the pointer crosses."
              }
              Button {
                readonly property var seen: root.selComputer ? root.known.filter(function(k) { return k.name === root.selComputer.name && k.seen })[0] : null
                visible: !!seen && root.selComputer && (seen.width !== root.selComputer.w || seen.height !== root.selComputer.h)
                width: parent.width
                text: seen ? "Use the size it reported (" + seen.width + "×" + seen.height + ")" : ""
                bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                onClicked: root.updateComputer(root.selIndex, { w: seen.width, h: seen.height })
              }
              Button {
                width: parent.width
                text: "Remove from layout"
                bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                onClicked: root.removeComputer(root.selIndex)
              }
            }

            // Add a computer
            Column {
              visible: root.isServer
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "OTHER COMPUTERS"; foreground: root.fg; fontFamily: root.fontFamily }
              Repeater {
                model: root.known.filter(function(k) { return !root.others.some(function(o) { return o.name === k.name }) })
                delegate: Button {
                  required property var modelData
                  width: sideColumn.width
                  text: "Add " + modelData.name + "  (" + modelData.width + "×" + modelData.height + ")"
                  bordered: true; leftAlign: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                  onClicked: root.addComputer(modelData.name, Number(modelData.width) || 1920, Number(modelData.height) || 1080)
                }
              }
              Button {
                width: parent.width
                text: "Add a computer"
                bordered: true; leftAlign: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
                onClicked: root.addComputer("LAPTOP", 1920, 1080)
              }
            }

            // Presets
            Column {
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader { text: "PRESETS"; foreground: root.fg; fontFamily: root.fontFamily }
              Label { visible: root.presets.length === 0; width: parent.width; color: root.dim; wrapMode: Text.WordWrap; text: "None yet. Apply a layout, then save it below." }
              Repeater {
                model: root.presets
                delegate: BorderSurface {
                  id: pcard
                  required property var modelData
                  readonly property bool isLoaded: modelData.id === root.loadedPreset
                  readonly property bool isCurrent: modelData.id === root.currentPreset
                  width: sideColumn.width
                  implicitHeight: prow.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: isLoaded ? Style.selectedFillFor(root.fg, root.accent) : Style.normalFillFor(root.fg, root.accent)
                  borderSpec: Border.controlSpec(isLoaded ? "selected" : (pmouse.containsMouse ? "hover" : "normal"), root.fg, root.accent)
                  MouseArea {
                    id: pmouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.loadedPreset = pcard.modelData.id; root.load() }
                  }
                  Row {
                    id: prow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Style.space(10); rightMargin: Style.space(6) }
                    spacing: Style.space(6)
                    Column {
                      width: parent.width - applyBtn.width - delBtn.width - Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      Label { width: parent.width; elide: Text.ElideRight; text: pcard.modelData.name + (pcard.isCurrent ? "   active" : ""); font.bold: true }
                      Label { width: parent.width; elide: Text.ElideRight; color: root.dim; font.pixelSize: Style.font.caption; text: pcard.modelData.note || ""; visible: text !== "" }
                    }
                    Button {
                      id: applyBtn
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Apply"
                      bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.caption
                      onClicked: root.applyPreset(pcard.modelData.id)
                    }
                    Button {
                      id: delBtn
                      anchors.verticalCenter: parent.verticalCenter
                      text: "✕"
                      tooltipText: "Delete this preset"
                      foreground: root.dim; fontFamily: root.fontFamily; fontSize: Style.font.caption
                      onClicked: { deleteDialog.target = pcard.modelData.id; deleteDialog.message = "Delete the preset “" + pcard.modelData.name + "”?"; deleteDialog.opened = true }
                    }
                  }
                }
              }
            }
          }
        }

        // ── footer: problems, message, apply + save
        Item {
          id: footer
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(18) }
          height: Math.max(footerButtons.implicitHeight, footerText.implicitHeight)
          Column {
            id: footerText
            anchors { left: parent.left; right: footerButtons.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
            spacing: Style.space(2)
            Repeater {
              model: root.issues.slice(0, 3)
              delegate: Label {
                required property var modelData
                width: footerText.width
                elide: Text.ElideRight
                color: modelData.level === "error" ? root.urgent : root.dim
                text: (modelData.level === "error" ? "✕  " : "!  ") + modelData.text
              }
            }
            Label {
              visible: root.message !== ""
              width: footerText.width
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              color: root.messageIsError ? root.urgent : root.fg
              text: root.message
            }
            Label {
              visible: root.issues.length === 0 && root.message === ""
              width: footerText.width
              elide: Text.ElideRight
              color: root.dim
              text: root.dirty ? "Not applied yet." : (root.loadedPreset !== "" ? "Showing a saved preset." : "Showing the current layout.")
            }
          }
          Row {
            id: footerButtons
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: Style.space(8)
            TextField {
              id: saveField
              width: Style.space(170)
              anchors.verticalCenter: parent.verticalCenter
              text: root.saveName
              placeholderText: "Preset name"
              foreground: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body
              maximumLength: 40
              onTextEdited: root.saveName = text
              onAccepted: root.savePreset()
            }
            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: root.presets.some(function(p) { return p.id === root.loadedPreset && p.name === root.saveName.trim() }) ? "Update preset" : "Save as preset"
              enabled: !root.busy && !root.hasErrors && root.saveName.trim() !== ""
              bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
              onClicked: root.savePreset()
            }
            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "Reset"
              tooltipText: "Throw away changes made here"
              enabled: !root.busy && root.dirty
              bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall
              onClicked: root.load()
            }
            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: root.busy ? "Applying…" : "Apply"
              enabled: !root.busy && !root.hasErrors
              selected: root.dirty
              bordered: true; foreground: root.fg; fontFamily: root.fontFamily; fontSize: Style.font.body
              onClicked: root.apply()
            }
          }
        }

        ConfirmDialog {
          id: deleteDialog
          property string target: ""
          anchors.fill: parent
          z: 100
          confirmText: "Delete"
          cancelText: "Cancel"
          background: root.bg
          foreground: root.fg
          fontFamily: root.fontFamily
          onConfirmed: { opened = false; root.deletePreset(target) }
          onCanceled: opened = false
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces
  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component SwitchRow: Item {
    id: sw
    property string text: ""
    property string detail: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    implicitHeight: Math.max(swCol.implicitHeight, swToggle.implicitHeight)
    opacity: enabled ? 1 : 0.5
    Column {
      id: swCol
      anchors { left: parent.left; right: swToggle.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
      spacing: Style.space(2)
      Label { text: sw.text }
      Label { width: parent.width; wrapMode: Text.WordWrap; color: root.dim; font.pixelSize: Style.font.caption; text: sw.detail; visible: text !== "" }
    }
    ToggleSwitch {
      id: swToggle
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      checked: sw.checked
      interactive: sw.enabled
      foreground: root.fg
      onToggled: if (sw.enabled) sw.toggled()
    }
  }

  // One rectangle on the canvas, in layout coordinates (lx, ly, lw, lh).
  component Box: Rectangle {
    id: box
    property string kind: ""
    property int boxIndex: -1
    property real lx: 0
    property real ly: 0
    property real lw: 1
    property real lh: 1
    property string title: ""
    property string subtitle: ""
    property string note: ""
    property bool faded: false
    property color tint: root.fg
    readonly property bool selected: root.selKind === kind && root.selIndex === boxIndex

    x: (lx - root.viewX) * root.viewScale
    y: (ly - root.viewY) * root.viewScale
    width: Math.max(8, lw * root.viewScale)
    height: Math.max(8, lh * root.viewScale)
    radius: Math.max(2, Style.cornerRadius)
    color: Qt.rgba(tint.r, tint.g, tint.b, faded ? 0.04 : (selected ? 0.22 : 0.10))
    border.width: selected ? 2 : 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, selected ? 0.95 : (faded ? 0.3 : 0.6))
    z: selected ? 2 : (kind === "computer" ? 1 : 0)

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(1)
      Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: box.title; font.bold: true; color: box.faded ? root.dim : root.fg }
      Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: box.subtitle; color: root.dim; font.pixelSize: Style.font.caption; visible: box.height > Style.space(44) }
      Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: box.note; color: root.dim; font.pixelSize: Style.font.caption; font.italic: true; visible: text !== "" }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real startX: 0
      property real startY: 0
      property real originX: 0
      property real originY: 0
      onPressed: function(mouse) {
        root.selKind = box.kind; root.selIndex = box.boxIndex
        keys.forceActiveFocus()
        var p = mapToItem(canvas, mouse.x, mouse.y)
        startX = p.x; startY = p.y; originX = box.lx; originY = box.ly
        root.dragging = true
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var p = mapToItem(canvas, mouse.x, mouse.y)
        var nx = originX + (p.x - startX) / root.viewScale
        var ny = originY + (p.y - startY) / root.viewScale
        // Monitors snap to monitors and computers; computers snap to this computer's outline too.
        var targets = []
        for (var i = 0; i < root.monitors.length; i++) {
          var m = root.monitors[i]
          if ((box.kind === "monitor" && i === box.boxIndex) || !m.enabled || m.handoff) continue
          targets.push(m)
        }
        for (var j = 0; j < root.others.length; j++) if (!(box.kind === "computer" && j === box.boxIndex)) targets.push(root.others[j])
        if (box.kind === "computer" && root.meBox) targets.push(root.meBox)
        var s = Geo.snap({ x: nx, y: ny, w: box.lw, h: box.lh }, targets, Style.space(14) / root.viewScale)
        if (box.kind === "monitor") root.updateMonitor(box.boxIndex, { x: Math.round(s.x), y: Math.round(s.y) })
        else root.updateComputer(box.boxIndex, { x: Math.round(s.x), y: Math.round(s.y) })
      }
      onReleased: { root.dragging = false; root.fitView() }
      onCanceled: { root.dragging = false; root.fitView() }
    }
  }
}
