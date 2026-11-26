// node tests/layout.test.js
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const src = fs.readFileSync(__dirname + "/../Layout.js", "utf8").replace(/^\.pragma library/m, "")
const L0 = {}; vm.runInNewContext(src + "\nObject.assign(L, {bbox, links, snap, problems, touches, overlaps, placeFromLinks})", { L: L0 })
const L = new Proxy(L0.L || L0, { get: (t, k) => (...a) => JSON.parse(JSON.stringify(t[k](...a)) ?? "null") })

// Desktop: laptop (2560x1600) left of three monitors, bottoms aligned.
const mons = [
  { label: "Acer", x: 0, y: 360, w: 1920, h: 1080, enabled: true },
  { label: "ASUS", x: 1920, y: 0, w: 2560, h: 1440, enabled: true },
  { label: "ASUS 2", x: 4480, y: 0, w: 2560, h: 1440, enabled: true },
]
const me = Object.assign({ name: "omarchy" }, L.bbox(mons))
assert.deepStrictEqual([me.x, me.y, me.w, me.h], [0, 0, 7040, 1440])
const laptop = { name: "LAPTOP", x: -2560, y: 1440 - 1600, w: 2560, h: 1600 }
let ls = L.links([me, laptop])
assert.deepStrictEqual(ls, [
  { from: "omarchy", dir: "left", to: "LAPTOP", range: null, toRange: [10, 100] },
  { from: "LAPTOP", dir: "right", to: "omarchy", range: [10, 100], toRange: null },
])

// Laptop under the left half only.
const under = { name: "LAPTOP", x: 0, y: 1440, w: 3520, h: 1600 }
ls = L.links([me, under])
assert.deepStrictEqual(ls[0], { from: "omarchy", dir: "down", to: "LAPTOP", range: [0, 50], toRange: null })

// Corner contact gives no link.
assert.strictEqual(L.links([me, { name: "X", x: 7040, y: 1440, w: 100, h: 100 }]).length, 0)

// Snapping pulls a nearly-adjacent box flush.
assert.deepStrictEqual(L.snap({ x: -2550, y: -150, w: 2560, h: 1600 }, [me], 20), { x: -2560, y: -160 })

// Problems: overlap, unreachable computer, isolated monitor.
assert.ok(L.problems(mons, [laptop]).length === 0)
assert.ok(L.problems(mons, [{ name: "FAR", x: -9000, y: 0, w: 100, h: 100 }])[0].text.includes("FAR"))
assert.strictEqual(L.problems([{ label: "a", x: 0, y: 0, w: 100, h: 100, enabled: true },
                               { label: "b", x: 50, y: 0, w: 100, h: 100, enabled: true }], [])[0].level, "error")
assert.ok(L.problems([{ label: "a", x: 0, y: 0, w: 100, h: 100, enabled: true },
                      { label: "b", x: 500, y: 0, w: 100, h: 100, enabled: true }], []).some(p => p.level === "warn"))
// Placing an old preset's computer from its links.
assert.deepStrictEqual(L.placeFromLinks(me, "LAPTOP", [{ from: "omarchy", dir: "down", to: "LAPTOP" }], 2560, 1600), { x: 0, y: 1440 })
console.log("layout tests passed")
