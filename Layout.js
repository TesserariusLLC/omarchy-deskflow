.pragma library
// Geometry for the layout window, kept free of QML so it can be tested with node.
//
// Everything lives in one coordinate space: this computer's monitors at their
// Hyprland logical positions, and each other computer as one rectangle of its
// own screen size. Deskflow treats each computer as a single screen, the
// bounding box of its monitors, and its links are percentages along an edge,
// so links come straight out of which rectangles touch where.

var TOUCH = 2          // pixels; edges closer than this count as touching

function bbox(rects) {
  if (!rects || rects.length === 0) return null
  var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i]
    x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y)
    x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h)
  }
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

function overlaps(a, b) {
  return a.x < b.x + b.w - TOUCH && b.x < a.x + a.w - TOUCH
      && a.y < b.y + b.h - TOUCH && b.y < a.y + a.h - TOUCH
}

function touches(a, b) {
  var vert = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
  var horz = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
  return (vert > TOUCH && (Math.abs(a.x + a.w - b.x) <= TOUCH || Math.abs(b.x + b.w - a.x) <= TOUCH))
      || (horz > TOUCH && (Math.abs(a.y + a.h - b.y) <= TOUCH || Math.abs(b.y + b.h - a.y) <= TOUCH))
}

function pct(v, start, len) {
  return Math.max(0, Math.min(100, Math.round((v - start) / len * 100)))
}
function range(a, b) { return (a <= 0 && b >= 100) ? null : [a, b] }

// One direction of a link: from A's edge `dir` into B, with both ranges.
function edgeLink(A, B, dir) {
  var vertical = dir === "left" || dir === "right"
  var lo = vertical ? Math.max(A.y, B.y) : Math.max(A.x, B.x)
  var hi = vertical ? Math.min(A.y + A.h, B.y + B.h) : Math.min(A.x + A.w, B.x + B.w)
  if (hi - lo <= TOUCH) return null
  var aStart = vertical ? A.y : A.x, aLen = vertical ? A.h : A.w
  var bStart = vertical ? B.y : B.x, bLen = vertical ? B.h : B.w
  return {
    from: A.name, dir: dir, to: B.name,
    range: range(pct(lo, aStart, aLen), pct(hi, aStart, aLen)),
    toRange: range(pct(lo, bStart, bLen), pct(hi, bStart, bLen))
  }
}

// screens: [{name, x, y, w, h}] — this computer's bounding box first, then the others.
function links(screens) {
  var out = []
  for (var i = 0; i < screens.length; i++) for (var j = 0; j < screens.length; j++) {
    if (i === j) continue
    var A = screens[i], B = screens[j], l = null
    // A corner contact matches two of these; only the one with a shared edge yields a link.
    if (!l && Math.abs(A.x - (B.x + B.w)) <= TOUCH) l = edgeLink(A, B, "left")
    if (!l && Math.abs(A.x + A.w - B.x) <= TOUCH) l = edgeLink(A, B, "right")
    if (!l && Math.abs(A.y - (B.y + B.h)) <= TOUCH) l = edgeLink(A, B, "up")
    if (!l && Math.abs(A.y + A.h - B.y) <= TOUCH) l = edgeLink(A, B, "down")
    if (l) out.push(l)
  }
  return out
}

// Snap a dragged rect to the edges of others when within `dist`.
// Returns the adjusted {x, y}.
function snap(r, others, dist) {
  var bx = null, by = null, bdx = dist + 1, bdy = dist + 1
  function tryX(v) { var d = Math.abs(v - r.x); if (d < bdx) { bdx = d; bx = v } }
  function tryY(v) { var d = Math.abs(v - r.y); if (d < bdy) { bdy = d; by = v } }
  for (var i = 0; i < others.length; i++) {
    var o = others[i]
    tryX(o.x + o.w); tryX(o.x - r.w); tryX(o.x); tryX(o.x + o.w - r.w)
    tryY(o.y + o.h); tryY(o.y - r.h); tryY(o.y); tryY(o.y + o.h - r.h)
  }
  return { x: bx !== null ? bx : r.x, y: by !== null ? by : r.y }
}

// Where to put a computer that a preset names in its links but has no rectangle
// for (presets from before 1.0): flush against that side of this computer.
function placeFromLinks(me, name, links, w, h) {
  for (var i = 0; i < links.length; i++) {
    var l = links[i]
    if (l.from !== me.name || l.to !== name) continue
    if (l.dir === "left")  return { x: me.x - w, y: me.y + me.h - h }
    if (l.dir === "right") return { x: me.x + me.w, y: me.y + me.h - h }
    if (l.dir === "up")    return { x: me.x, y: me.y - h }
    if (l.dir === "down")  return { x: me.x, y: me.y + me.h }
  }
  return { x: me.x - w, y: me.y }
}

// Problems worth showing before Apply. Returns [{level: "error"|"warn", text}].
function problems(monitors, others) {
  var out = []
  var on = monitors.filter(function(m) { return m.enabled && !m.handoff })
  if (on.length === 0) out.push({ level: "error", text: "At least one monitor has to stay on this computer." })
  for (var i = 0; i < on.length; i++) for (var j = i + 1; j < on.length; j++)
    if (overlaps(on[i], on[j])) out.push({ level: "error", text: on[i].label + " overlaps " + on[j].label + "." })
  if (on.length > 1) for (var k = 0; k < on.length; k++) {
    var alone = true
    for (var m = 0; m < on.length; m++) if (m !== k && touches(on[k], on[m])) { alone = false; break }
    if (alone) out.push({ level: "warn", text: on[k].label + " doesn't touch another monitor, so the pointer can't reach it." })
  }
  var me = bbox(on)
  for (var n = 0; n < others.length; n++) {
    var o = others[n]
    for (var q = 0; q < on.length; q++)
      if (overlaps(o, on[q])) { out.push({ level: "error", text: o.name + " overlaps " + on[q].label + "." }); break }
    var reach = me && touches(o, me)
    for (var p = 0; p < others.length && !reach; p++) if (p !== n && touches(o, others[p])) reach = true
    if (!reach) out.push({ level: "warn", text: o.name + " doesn't touch anything, so it can't be reached." })
  }
  return out
}
