// ClaudePet for macOS: a tiny pixel dog that shows what Claude Code is doing.
// Reads the state files written by claudepet/hook.py from ~/.claudepet/sessions/.
// Built automatically by `claudepet start` (swiftc -O mac/ClaudePetMac.swift -o ~/.claudepet/ClaudePetMac).
//
//   click  → pet the dog (hearts, wakes it up)     hover → label shows what Claude is doing
//   drag   → move it (position is remembered)      right-click → Dog / Cat, Size, Show as, Move to corner, Quit
//   Show as: Pet (floating pet + label), Pill (pixel head + status + timer), Menu bar (pixel status chip)
import AppKit

// MARK: - files & config
let home: URL = {
    if let h = ProcessInfo.processInfo.environment["CLAUDEPET_HOME"] { return URL(fileURLWithPath: h) }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claudepet")
}()
let sessionsDir = home.appendingPathComponent("sessions")
let configURL = home.appendingPathComponent("config.json")
let pidURL = home.appendingPathComponent("pet.pid")
let pidPath = strdup(pidURL.path)

func readJSON(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}
func num(_ v: Any?, _ fallback: Double) -> Double { (v as? NSNumber)?.doubleValue ?? fallback }
func loadConfig() -> [String: Any] { readJSON(configURL) ?? [:] }
func saveConfig(_ updates: [String: Any]) {
    var cfg = loadConfig()
    for (k, v) in updates { cfg[k] = v }
    if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: configURL, options: .atomic)
    }
}

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

// MARK: - states
let RANK: [String: Int] = ["idle": 0, "done": 1, "thinking": 2, "working": 3, "permission": 4]
let STALE: [String: Double] = ["thinking": 300, "working": 900, "permission": 1800]
let TEXT: [String: String] = ["asleep": "Idle", "idle": "Idle", "thinking": "Thinking", "working": "Working",
                              "permission": "Needs you", "done": "Done"]
let DOT: [String: NSColor] = ["asleep": .systemGray, "idle": .systemGray, "thinking": .systemBlue,
                              "working": .systemOrange, "permission": .systemRed, "done": .systemGreen]
let SLEEP_AFTER = 120.0

/// Most urgent state across all Claude Code sessions, its detail, and the last activity time.
func readState() -> (String, String, Double) {
    let now = Date().timeIntervalSince1970
    let doneSecs = num(loadConfig()["done_secs"], 6)
    var best = "idle", detail = ""
    var last = 0.0
    let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
    for f in files where f.pathExtension == "json" && !f.lastPathComponent.hasPrefix(".") {
        guard let s = readJSON(f) else { continue }
        let ts = num(s["ts"], 0), age = now - ts
        if age > 86400 { try? FileManager.default.removeItem(at: f); continue }
        var st = (s["state"] as? String) ?? "idle"
        if st == "done" && age > doneSecs { st = "idle" }
        if let limit = STALE[st], age > limit { st = "idle" }
        last = max(last, ts)
        if (RANK[st] ?? 0) > (RANK[best] ?? 0) { best = st; detail = (s["detail"] as? String) ?? "" }
    }
    return (best, detail, last)
}

// MARK: - pixel art (16 × 15)
let SW = 16, SH = 15
let DOG_BODY = [
    "....ooooooo.....",
    "..oobbbbbbboo...",
    ".oddbbbbbbbddo..",
    "odddbbbbbbbdddo.",
    "odddbEbbbEbdddo.",
    "odddbEbbbEbdddo.",
    "odddbbbnbbbdddo.",
    ".oddbbcccbbddo..",
    "..oobbcpcbboo...",
    "...obbbbbbbo..ob",
    "..obbcccccbbo.ob",
    "..obbcccccbboob.",
    "..obbbbbbbbbo...",
]
let CAT_BODY = [
    "..o.........o...",
    ".obo.......obo..",
    ".opbooooooobpo..",
    "obbbbdbdbdbbbbo.",
    "obbbbbbbbbbbbbo.",
    "obbbEbbbbbEbbbo.",
    "obbbEbbbbbEbbbo.",
    "owwbbbbpbbbbwwo.",
    ".obbbbcccbbbbo.d",
    "..oobbbbbbboo..d",
    "..obbcccccbbo.d.",
    "..obbcccccbbodd.",
    "..obbbbbbbbbo...",
]
let LEGS = [["..ob.ob..bo.bo..", "..oo.oo..oo.oo.."],
            ["...ob.ob.bo.bo..", "...oo.oo.oo.oo.."]]
let DOG_PAL: [Character: NSColor] = ["o": hex("#3a2412"), "b": hex("#d29a5e"), "c": hex("#f5e4c8"), "p": hex("#ef6f8a"),
                                     "d": hex("#7a4f2c"), "n": hex("#1e120a"), "E": hex("#141414")]
let CAT_PAL: [Character: NSColor] = ["o": hex("#2b2d35"), "b": hex("#a3a8b3"), "c": hex("#eceef2"), "p": hex("#f29bb0"),
                                     "d": hex("#626874"), "w": hex("#eceef2"), "E": hex("#141414")]

// MARK: - pet kind & size (chosen from the right-click menu, saved in config.json)
var PET = (loadConfig()["pet"] as? String) == "cat" ? "cat" : "dog"
var PAL: [Character: NSColor] { PET == "cat" ? CAT_PAL : DOG_PAL }
let SIZES: [(String, CGFloat)] = [("Small", 1.5), ("Medium", 2), ("Big", 3)]
var SIZE = SIZES.contains { $0.0 == (loadConfig()["size"] as? String) } ? loadConfig()["size"] as! String : "Medium"
let MODES: [(String, String)] = [("Pet", "pet"), ("Pill", "pill"), ("Menu bar", "menubar")]
var MODE = MODES.contains { $0.1 == (loadConfig()["mode"] as? String) } ? loadConfig()["mode"] as! String : "pet"
let GLYPHS: [String: [String]] = [
    "z": ["111", "001", "010", "100", "111"],
    "!": ["1", "1", "1", "0", "1"],
    "heart": ["01010", "11111", "11111", "01110", "00100"],
    "spark": ["010", "111", "010"],
    "dot": ["1"],
    "check": ["00001", "00011", "10110", "11100", "01000"],
    "bolt": ["00110", "01100", "11111", "00110", "01100"],
]
let SUBTITLE: [String: String] = ["asleep": "Napping", "idle": "Ready when you are", "thinking": "Mulling it over",
                                  "working": "Busy with tools", "permission": "Waiting for you", "done": "All finished"]

func dogFrame(legs: Int, eyesOpen: Bool, flip: Bool) -> [[Character]] {
    var rows = ((PET == "cat" ? CAT_BODY : DOG_BODY) + LEGS[legs % 2]).map { Array($0) }
    if !eyesOpen {   // top eye pixel → fur, bottom → a closed-eye line
        let src = rows
        for y in 0..<rows.count {
            for x in 0..<SW where src[y][x] == "E" {
                rows[y][x] = (y + 1 < src.count && src[y + 1][x] == "E") ? "b" : "o"
            }
        }
    }
    return flip ? rows.map { Array($0.reversed()) } : rows
}

// MARK: - layout (points)
let GW = 36, GH = 24               // art canvas in art pixels
var S: CGFloat { SIZES.first { $0.0 == SIZE }?.1 ?? 2 }   // points per art pixel
var ART_H: CGFloat { CGFloat(GH) * S }
var LABEL_H: CGFloat { 14 + 2 * S }
var FONT_SIZE: CGFloat { 8 + S }
var PILL_H: CGFloat { 12 + 8 * S }   // 24 / 28 / 36
var WIN: NSSize {   // 72 × 68 at Medium; just the label in pill mode
    MODE == "pill" ? NSSize(width: (PILL_H * 7.5).rounded(), height: PILL_H)
                   : NSSize(width: max(CGFloat(GW) * S, 72), height: ART_H + 2 + LABEL_H)
}
let JUMP = [0, -1, -2, -3, -3, -2, -1, 0, 0, -1, -2, -1, 0]

final class Particle {
    var x: Double, y: Double, life: Int
    let vy: Double, glyph: String, color: NSColor
    init(_ x: Double, _ y: Double, _ glyph: String, _ color: NSColor, vy: Double, life: Int) {
        self.x = x; self.y = y; self.glyph = glyph; self.color = color; self.vy = vy; self.life = life
    }
}
struct Px { let x: Int, y: Int, w: Int, h: Int, c: NSColor }

/// The pet's animated pixel head (shared by the pill and the menu bar), vertically centred on midY.
/// `bobs` lets it bounce; `halo` draws a thin outline behind it. Returns its width (15 art pixels).
@discardableResult
func drawHead(_ st: String, t: Int, age: Int, petAge: Int?, peek: Bool, x hx: CGFloat, midY: CGFloat, q: CGFloat,
              halo: NSColor?, bobs: Bool = true) -> CGFloat {
    var eyes = true, bob = 0
    switch st {
    case "asleep": eyes = peek; bob = (t / 10) % 2
    case "idle": eyes = !(t % 45 == 0 || t % 45 == 1); bob = (t / 12) % 2
    case "thinking": eyes = !(t % 30 == 0)
    case "working": bob = -(t / 2 % 2)
    case "permission": bob = (t / 3) % 2 == 1 ? -1 : 0
    case "done": eyes = false; bob = age < 6 ? [0, -1, -2, -2, -1, 0][age] : 0
    default: break
    }
    if let pa = petAge { eyes = false; if pa < 6 { bob = [0, -1, -2, -2, -1, 0][pa] } }
    if !bobs { bob = 0 }
    let rowsN = PET == "cat" ? 10 : 9
    let head = Array(dogFrame(legs: 0, eyesOpen: eyes, flip: false).prefix(rowsN)).map { Array($0.prefix(15)) }
    let hy = (midY - CGFloat(rowsN) * q / 2).rounded() + CGFloat(bob) * q * 0.5
    func cell(_ x: Int, _ y: Int) -> NSRect { NSRect(x: hx + CGFloat(x) * q, y: hy + CGFloat(y) * q, width: q, height: q) }
    if let halo = halo {
        halo.setFill()
        for (y, row) in head.enumerated() { for (x, ch) in row.enumerated() where ch != "." { cell(x, y).insetBy(dx: -1, dy: -1).fill() } }
    }
    for (y, row) in head.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." { PAL[ch]?.setFill(); cell(x, y).fill() }
    }
    return 15 * q
}

/// The little animated pixel icon for a state (shared by the pill and the menu bar). Returns its width.
@discardableResult
func drawBadge(_ st: String, t: Int, age: Int, petAge: Int?, x bx: CGFloat, midY: CGFloat, q bq: CGFloat) -> CGFloat {
    let accent = DOT[st] ?? .systemGray
    func badge(_ g: String, _ c: NSColor, dy: CGFloat = 0) {
        let rows = GLYPHS[g] ?? []
        let gy = midY - CGFloat(rows.count) * bq / 2 + dy
        c.setFill()
        for (y, row) in rows.enumerated() {
            for (x, b) in row.enumerated() where b == "1" {
                NSRect(x: bx + CGFloat(x) * bq, y: gy + CGFloat(y) * bq, width: bq, height: bq).fill()
            }
        }
    }
    if let pa = petAge { badge("heart", hex("#ff6b8b"), dy: -CGFloat(pa % 4) * bq * 0.5); return 5 * bq }
    switch st {
    case "asleep": badge("z", hex("#9fb0ff"), dy: -CGFloat((t / 5) % 4) * bq * 0.5); return 3 * bq
    case "thinking":
        for i in 0..<3 {
            let up = (t / 3) % 3 == i ? -bq : 0
            accent.setFill(); NSRect(x: bx + CGFloat(i * 2) * bq, y: midY - bq / 2 + up, width: bq, height: bq).fill()
        }
        return 5 * bq
    case "working": badge("bolt", (t / 2) % 2 == 0 ? accent : hex("#fde68a")); return 5 * bq
    case "permission": if (t / 3) % 2 == 0 { badge("!", accent) }; return bq
    case "done":
        badge("check", accent)
        if age < 40 && (t / 2) % 2 == 0 { hex("#ffd166").setFill(); NSRect(x: bx + 5 * bq, y: midY - 4 * bq, width: bq, height: bq).fill() }
        return 6 * bq
    default: return 0
    }
}

// MARK: - the dog
final class DogView: NSView {
    var t = 0
    var state = "asleep", detail = "", since = 0
    var lastActivity = 0.0, lastPoke = Date().timeIntervalSince1970
    var particles: [Particle] = []
    var walkX = 0, walkDir = 1, petUntil = -1, petStart = -100
    var hovering = false, dragging = false
    var dragStart = NSPoint.zero, winStart = NSPoint.zero
    var pixels: [Px] = []
    var stateDate = Date()

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // -- state ---------------------------------------------------------------------
    func poll() {
        var (st, det, last) = readState()
        lastActivity = last
        let quiet = Date().timeIntervalSince1970 - max(last, lastPoke)
        if st == "idle" && quiet > SLEEP_AFTER { st = "asleep" }
        if st != state { state = st; since = t; stateDate = Date(); particles.removeAll() }
        detail = det
    }

    func tick() {
        if t % 2 == 0 { poll() }
        compose()
        t += 1
        needsDisplay = true
    }

    // -- animation -------------------------------------------------------------------
    func compose() {
        var out: [Px] = []
        func px(_ x: Int, _ y: Int, _ c: NSColor, _ w: Int = 1, _ h: Int = 1) { out.append(Px(x: x, y: y, w: w, h: h, c: c)) }
        func glyph(_ g: String, _ x: Int, _ y: Int, _ c: NSColor) {
            for (gy, row) in (GLYPHS[g] ?? []).enumerated() {
                for (gx, b) in row.enumerated() where b == "1" { px(x + gx, y + gy, c) }
            }
        }
        let ink = hex("#2a2a2a")
        func bubble(_ x: Int, _ y: Int) {
            px(x + 1, y, ink, 5, 1); px(x + 1, y + 6, ink, 5, 1)
            px(x, y + 1, ink, 1, 5); px(x + 6, y + 1, ink, 1, 5)
            px(x + 1, y + 1, .white, 5, 5)
            px(x + 1, y + 7, ink); px(x, y + 8, ink)
        }

        let st = state, age = t - since
        let petting = t < petUntil, petAge = t - petStart
        var legs = 0, eyes = true, flip = false, yoff = 0
        switch st {
        case "asleep": eyes = false; yoff = (t / 10) % 2
        case "idle": eyes = !(t % 45 == 0 || t % 45 == 1); yoff = (t / 12) % 2
        case "thinking":
            if t % 2 == 0 { walkX += walkDir; if abs(walkX) >= 6 { walkDir = -walkDir } }
            legs = (t / 2) % 2; flip = walkDir < 0
        case "working": legs = t % 2; yoff = -(t % 2)
        case "permission": yoff = (t / 3) % 2 == 1 ? -2 : 0
        case "done": eyes = false; yoff = age < JUMP.count ? JUMP[age] : 0
        default: break
        }
        if hovering && st == "asleep" { eyes = true }          // peeks at you
        if petting { eyes = false; if petAge < 7 { yoff = JUMP[petAge] } }
        if dragging { legs = (t / 2) % 2; eyes = true; yoff = 0 }
        if st != "thinking" { walkX += (walkX < 0 ? 1 : 0) - (walkX > 0 ? 1 : 0) }

        let x0 = (GW - SW) / 2 + walkX, y0 = GH - SH + yoff
        let rows = dogFrame(legs: legs, eyesOpen: eyes, flip: flip)
        for (y, row) in rows.enumerated() {
            var runStart = 0
            var runCh: Character = "."
            for (x, ch) in (row + ["."]).enumerated() where ch != runCh {
                if runCh != ".", let c = PAL[runCh] { px(x0 + runStart, y0 + y, c, x - runStart, 1) }
                runStart = x; runCh = ch
            }
        }
        let bx = min(x0 + 12, GW - 7), by = max(y0 - 8, 0)

        switch st {
        case "asleep":
            if t % 14 == 0 && !hovering {
                particles.append(Particle(Double(x0 + 12), Double(y0), "z", hex("#9fb0ff"), vy: -0.25, life: 36))
            }
        case "thinking":
            bubble(bx, by)
            for i in 0..<((t / 4) % 4) { px(bx + 1 + i * 2, by + 3, ink) }
        case "working":
            let ly = GH - 6
            px(x0 + 3, ly, PAL["o"]!, 10, 1); px(x0 + 3, ly + 1, PAL["o"]!, 1, 5); px(x0 + 12, ly + 1, PAL["o"]!, 1, 5)
            px(x0 + 4, ly + 1, hex("#9aa3ad"), 8, 5); px(x0 + 7, ly + 2, hex("#e8edf2"), 2, 2)
            px(x0 + 4 + (t % 2) * 5, ly - 1 - (t % 2), PAL["b"]!, 2, 1)
            px(x0 + 9 - (t % 2) * 5, ly - 1 - ((t + 1) % 2), PAL["b"]!, 2, 1)
            if t % 3 == 0 {
                particles.append(Particle(Double(x0 + Int.random(in: 4...11)), Double(ly - 2), "dot",
                                          hex(["#7dd3fc", "#a7f3d0", "#fde68a"].randomElement()!), vy: -0.6, life: 8))
            }
        case "permission":
            bubble(bx, by)
            if (t / 3) % 2 == 0 { glyph("!", bx + 3, by + 1, hex("#e5484d")) }
            let armY = y0 + 4 - 2 * ((t / 2) % 2)
            px(x0 + SW - 1, armY, PAL["o"]!, 2, 3); px(x0 + SW - 1, armY, PAL["b"]!, 2, 2)
        case "done":
            if age < 36 && t % 4 == 0 {
                particles.append(Particle(Double(x0 + Int.random(in: 0...12)), Double(y0), "spark",
                                          hex(["#ffd166", "#7ee081", "#7cc6ff", "#ff6b8b"].randomElement()!), vy: -0.5, life: 12))
            }
        default: break
        }
        if petting && t % 3 == 0 {
            particles.append(Particle(Double(x0 + Int.random(in: 2...10)), Double(y0), "heart", hex("#ff6b8b"), vy: -0.5, life: 12))
        }
        particles = particles.filter { p in
            p.y += p.vy; p.life -= 1
            if p.glyph == "z" { p.x += 0.15 }
            guard p.life > 0 && p.y > -5 else { return false }
            glyph(p.glyph, Int(p.x), Int(p.y), p.color)
            return true
        }
        pixels = out
    }

    // -- drawing --------------------------------------------------------------------
    override func draw(_ dirtyRect: NSRect) {
        if MODE == "pill" { drawPill(); return }
        let ox = (bounds.width - CGFloat(GW) * S) / 2      // centre the art if the window is wider than it
        for p in pixels where MODE != "pill" {
            p.c.setFill()
            NSRect(x: ox + CGFloat(p.x) * S, y: CGFloat(p.y) * S, width: CGFloat(p.w) * S, height: CGFloat(p.h) * S).fill()
        }
        // status label: a small capsule with a coloured dot
        var text = TEXT[state] ?? ""
        if hovering && !detail.isEmpty && ["thinking", "working", "permission"].contains(state) { text = detail }
        if text.count > 16 { text = String(text.prefix(15)) + "…" }
        let font = NSFont.systemFont(ofSize: FONT_SIZE, weight: .medium)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let tw = ceil(str.size().width)
        let w = min(bounds.width, tw + 6 + 4 + 14), h = LABEL_H
        let r = NSRect(x: (bounds.width - w) / 2, y: MODE == "pill" ? 0 : ART_H + 2, width: w, height: h)
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        let capsule = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
        capsule.fill()
        NSColor.separatorColor.setStroke()
        capsule.lineWidth = 0.5
        capsule.stroke()
        (DOT[state] ?? .systemGray).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + 7, y: r.midY - 3, width: 6, height: 6)).fill()
        str.draw(at: NSPoint(x: r.minX + 7 + 6 + 4, y: r.midY - str.size().height / 2))
    }

    /// Pill mode: the pet's animated pixel head, a pixel status badge, what Claude is doing,
    /// how long it's been at it, and a colour + motion that matches the state.
    func drawPill() {
        let st = state, age = t - since
        let petting = t < petUntil, petAge = t - petStart
        let accent = DOT[st] ?? .systemGray
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let h = bounds.height
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let capsule = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)

        // background: glass + a tint of the state colour (pulsing when Claude needs you)
        let pulse = 0.5 + 0.5 * sin(Double(t) * 0.45)
        NSColor.windowBackgroundColor.withAlphaComponent(0.93).setFill(); capsule.fill()
        let tint: CGFloat = st == "permission" ? 0.10 + 0.14 * pulse : (["asleep", "idle"].contains(st) ? 0.04 : 0.12)
        accent.withAlphaComponent(tint).setFill(); capsule.fill()

        NSGraphicsContext.saveGraphicsState()
        capsule.addClip()
        // indeterminate progress sweep along the bottom while Claude is busy
        if st == "thinking" || st == "working" {
            let speed = st == "working" ? 0.05 : 0.025
            let ph = (Double(t) * speed).truncatingRemainder(dividingBy: 1.3) - 0.3
            let barW = r.width * 0.3, barH = max(2, S)
            let g = NSGradient(colors: [accent.withAlphaComponent(0), accent, accent.withAlphaComponent(0)])
            g?.draw(in: NSRect(x: r.minX + CGFloat(ph) * r.width, y: r.maxY - barH, width: barW, height: barH), angle: 0)
        }
        // a quick shine across the pill when a turn finishes
        if st == "done" && age < 14 {
            let x = r.minX + r.width * CGFloat(age) / 10 - 20
            let g = NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(dark ? 0.18 : 0.5),
                                        NSColor.white.withAlphaComponent(0)])
            g?.draw(in: NSRect(x: x, y: r.minY, width: 26, height: r.height), angle: 0)
        }
        NSGraphicsContext.restoreGraphicsState()

        let border = st == "permission" ? accent.withAlphaComponent(0.45 + 0.5 * pulse)
                   : (["asleep", "idle"].contains(st) ? NSColor.separatorColor : accent.withAlphaComponent(0.45))
        border.setStroke()
        capsule.lineWidth = st == "permission" ? 1.5 : 1
        capsule.stroke()

        // -- the pet's head, in pixels -----------------------------------------------
        let q = max(1.5, ((h - 6) / 10 * 2).rounded(.down) / 2)          // points per art pixel
        let hx = h * 0.32
        drawHead(st, t: t, age: age, petAge: petting ? petAge : nil, peek: hovering, x: hx, midY: h / 2, q: q,
                 halo: dark ? NSColor.white.withAlphaComponent(0.3) : nil)

        // -- status badge (pixel icon) next to the head ----------------------------------
        let bq = max(1, (q * 0.75 * 2).rounded() / 2)
        let bx = hx + 15 * q + q * 0.5
        let badgeW = drawBadge(st, t: t, age: age, petAge: petting ? petAge : nil, x: bx, midY: h / 2, q: bq)

        // -- text -------------------------------------------------------------------
        let textX = bx + max(badgeW, 5 * bq) + q * 2.5
        let busy = ["thinking", "working", "permission"].contains(st)
        var right = ""
        if busy {
            let secs = Int(Date().timeIntervalSince(stateDate))
            right = String(format: "%d:%02d", secs / 60, secs % 60)
        }
        let small = NSFont.monospacedDigitSystemFont(ofSize: FONT_SIZE, weight: .regular)
        let rightStr = NSAttributedString(string: right, attributes: [.font: small, .foregroundColor: NSColor.tertiaryLabelColor])
        let rightW = right.isEmpty ? 0 : ceil(rightStr.size().width)
        let padR = h * 0.42
        if !right.isEmpty { rightStr.draw(at: NSPoint(x: r.maxX - padR - rightW, y: (h - rightStr.size().height) / 2)) }

        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let title = NSFont.systemFont(ofSize: FONT_SIZE + 1, weight: .semibold)
        let sub = NSFont.systemFont(ofSize: FONT_SIZE, weight: .regular)
        let line = NSMutableAttributedString(string: TEXT[st] ?? "", attributes: [.font: title, .foregroundColor: NSColor.labelColor, .paragraphStyle: para])
        let second = (busy && !detail.isEmpty) ? detail : (SUBTITLE[st] ?? "")
        line.append(NSAttributedString(string: "  " + second, attributes: [.font: sub, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
        let lh = ceil(line.size().height)
        let textW = r.maxX - padR - (right.isEmpty ? 0 : rightW + 6) - textX
        line.draw(with: NSRect(x: textX, y: (h - lh) / 2, width: max(0, textW), height: lh), options: [.usesLineFragmentOrigin])
    }

    // -- mouse ---------------------------------------------------------------------
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }

    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { showMenu(e); return }
        dragStart = NSEvent.mouseLocation; winStart = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        if !dragging && hypot(p.x - dragStart.x, p.y - dragStart.y) < 3 { return }
        dragging = true
        window?.setFrameOrigin(NSPoint(x: winStart.x + p.x - dragStart.x, y: winStart.y + p.y - dragStart.y))
    }

    override func mouseUp(with e: NSEvent) {
        if dragging {
            dragging = false
            if let w = window {
                let primaryH = NSScreen.screens.first?.frame.height ?? 0
                saveConfig(["x": Int(w.frame.minX), "y": Int(primaryH - w.frame.maxY)])   // top-left coords
            }
        } else if !e.modifierFlags.contains(.control) {
            petStart = t; petUntil = t + 16
            lastPoke = Date().timeIntervalSince1970          // wakes it up
            if state == "asleep" { poll() }
        }
    }

    override func rightMouseDown(with e: NSEvent) { showMenu(e) }

    func showMenu(_ e: NSEvent) { NSMenu.popUpContextMenu(makeMenu(), with: e, for: self) }

    func makeMenu() -> NSMenu {
        let m = NSMenu()
        if MODE == "menubar" {                                  // no hover label up there, so show the detail here
            var info = TEXT[state] ?? ""
            if !detail.isEmpty && ["thinking", "working", "permission"].contains(state) { info += ": " + detail }
            m.addItem(NSMenuItem(title: info, action: nil, keyEquivalent: ""))
            m.addItem(.separator())
        }
        for (title, value) in [("Dog", "dog"), ("Cat", "cat")] {
            let it = NSMenuItem(title: title, action: #selector(choosePet(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = value; it.state = PET == value ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (name, _) in SIZES {
            let it = NSMenuItem(title: name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = name; it.state = SIZE == name ? .on : .off
            sizes.addItem(it)
        }
        sizeItem.submenu = sizes
        if MODE != "menubar" { m.addItem(sizeItem) }
        let modeItem = NSMenuItem(title: "Show as", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for (name, value) in MODES {
            let it = NSMenuItem(title: name, action: #selector(chooseMode(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = value; it.state = MODE == value ? .on : .off
            modes.addItem(it)
        }
        modeItem.submenu = modes
        m.addItem(modeItem)
        m.addItem(.separator())
        let reset = NSMenuItem(title: "Move to corner", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        let quit = NSMenuItem(title: "Quit ClaudePet", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        if MODE != "menubar" { m.addItem(reset); m.addItem(.separator()) }
        m.addItem(quit)
        return m
    }

    @objc func choosePet(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        PET = v; saveConfig(["pet": v])
        compose(); needsDisplay = true
    }

    @objc func chooseSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, let w = window else { return }
        let top = w.frame.maxY, midX = w.frame.midX           // keep the pet where it is: same top edge & centre
        SIZE = v; saveConfig(["size": v])
        refit(w, midX: midX, y: top - WIN.height)
    }

    @objc func chooseMode(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String, v != MODE, let w = window else { return }
        let old = MODE, bottom = w.frame.minY, midX = w.frame.midX   // pet ↔ pill: the pill sits where the label was
        MODE = v; saveConfig(["mode": v])
        if v != "menubar" { refit(w, midX: midX, y: old == "menubar" ? w.frame.maxY - WIN.height : bottom) }
        (NSApp.delegate as? AppDelegate)?.applyMode()
    }

    /// Resize the window for the current size/mode, centred on midX with its bottom edge at y.
    func refit(_ w: NSWindow, midX: CGFloat, y: CGFloat) {
        w.setFrame(NSRect(x: midX - WIN.width / 2, y: y, width: WIN.width, height: WIN.height), display: true)
        frame = NSRect(origin: .zero, size: WIN)
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        if loadConfig()["x"] is NSNumber { saveConfig(["x": Int(w.frame.minX), "y": Int(primaryH - w.frame.maxY)]) }
        needsDisplay = true
    }

    @objc func resetPosition() {
        saveConfig(["x": NSNull(), "y": NSNull()])
        window?.setFrameOrigin(defaultOrigin())
    }

    @objc func quit() { unlink(pidPath); NSApp.terminate(nil) }
}

func defaultOrigin() -> NSPoint {
    let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    return NSPoint(x: vf.maxX - WIN.width - 12, y: vf.minY + 8)     // bottom-right, above the Dock
}

func savedOrigin() -> NSPoint? {
    let cfg = loadConfig()
    guard let x = cfg["x"] as? NSNumber, let y = cfg["y"] as? NSNumber else { return nil }
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let o = NSPoint(x: x.doubleValue, y: primaryH - y.doubleValue - WIN.height)
    return NSScreen.screens.contains { $0.visibleFrame.intersects(NSRect(origin: o, size: WIN)) } ? o : nil
}

// MARK: - app
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var dog: DogView!
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        dog = DogView(frame: NSRect(origin: .zero, size: WIN))
        panel = NSPanel(contentRect: NSRect(origin: savedOrigin() ?? defaultOrigin(), size: WIN),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar                                  // floats above normal windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = dog              // shown (or not, in menu bar mode) by applyMode()

        dog.poll()
        applyMode()
        let timer = Timer(timeInterval: 0.11, repeats: true) { [weak self] _ in self?.dog.tick(); self?.updateStatusItem() }
        RunLoop.main.add(timer, forMode: .common)
    }

    // -- menu bar mode ------------------------------------------------------------------
    func applyMode() {
        if MODE == "menubar" {
            panel.orderOut(nil)
            guard statusItem == nil else { return }
            let si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            si.button?.target = self
            si.button?.action = #selector(statusClicked)
            si.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            si.button?.imagePosition = .imageLeft
            statusItem = si
            updateStatusItem()
        } else {
            if let si = statusItem { NSStatusBar.system.removeStatusItem(si); statusItem = nil }
            panel.orderFrontRegardless()
        }
    }

    @objc func statusClicked() {
        guard let si = statusItem else { return }
        si.menu = dog.makeMenu()
        si.button?.performClick(nil)     // opens the menu
        si.menu = nil
    }

    /// Draw the menu bar item: a solid chip (so it reads on any wallpaper) holding the pet's pixel head,
    /// a pixel status icon and the status word, all centred on the same line. A thin progress line
    /// slides along the bottom while Claude is busy; the chip pulses red when Claude needs you.
    func updateStatusItem() {
        guard let b = statusItem?.button else { return }
        // the real bar height (taller than `thickness` on Macs with a notch)
        let h = max(NSStatusBar.system.thickness, b.window?.frame.height ?? 0)
        let st = dog.state, t = dog.t, age = dog.t - dog.since
        let petAge: Int? = dog.t < dog.petUntil ? dog.t - dog.petStart : nil
        let accent = DOT[st] ?? .systemGray
        let text = TEXT[st] ?? ""
        let font = NSFont.systemFont(ofSize: min(13, max(11, (h * 0.36).rounded())), weight: .semibold)
        let textW = ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)

        let chipH = min(h - 4, (h * 0.64).rounded()), chipY = ((h - chipH) / 2).rounded()
        let q = max(1, ((chipH - 3) / 10 * 2).rounded(.down) / 2)        // head fills the chip, crisp half-points
        let bq = max(1, (q * 0.75 * 2).rounded() / 2)
        let padX = (chipH * 0.3).rounded()
        let headX = padX, badgeX = headX + 15 * q + q * 1.5
        let textX = badgeX + 5 * bq + q * 1.5, width = (textX + textW + padX).rounded()
        let mid = h / 2

        b.image = NSImage(size: NSSize(width: width, height: h), flipped: true) { _ in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let chip = NSRect(x: 0.5, y: chipY + 0.5, width: width - 1, height: chipH - 1)
            let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
            let pulse = 0.5 + 0.5 * sin(Double(t) * 0.45)
            let quiet = ["asleep", "idle"].contains(st)

            // solid base so it never washes out, then the state colour on top
            (dark ? NSColor(white: 0.1, alpha: 0.82) : NSColor(white: 1, alpha: 0.9)).setFill(); path.fill()
            if !quiet { accent.withAlphaComponent(st == "permission" ? 0.22 + 0.25 * pulse : 0.22).setFill(); path.fill() }
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            if st == "thinking" || st == "working" {
                let ph = (Double(t) * (st == "working" ? 0.05 : 0.025)).truncatingRemainder(dividingBy: 1.3) - 0.3
                NSGradient(colors: [accent.withAlphaComponent(0), accent, accent.withAlphaComponent(0)])?
                    .draw(in: NSRect(x: CGFloat(ph) * width, y: chip.maxY - 2, width: width * 0.4, height: 2), angle: 0)
            }
            if st == "done" && age < 14 {
                NSGradient(colors: [.init(white: 1, alpha: 0), .init(white: 1, alpha: dark ? 0.3 : 0.7), .init(white: 1, alpha: 0)])?
                    .draw(in: NSRect(x: width * CGFloat(age) / 10 - 16, y: chip.minY, width: 20, height: chip.height), angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
            (quiet ? NSColor(white: dark ? 1 : 0, alpha: 0.18) : accent.withAlphaComponent(st == "permission" ? 0.5 + 0.5 * pulse : 0.75)).setStroke()
            path.lineWidth = 1; path.stroke()

            drawHead(st, t: t, age: age, petAge: petAge, peek: false, x: headX, midY: mid, q: q,
                     halo: dark ? NSColor.white.withAlphaComponent(0.3) : nil, bobs: st == "done" || petAge != nil)
            if st == "idle" && petAge == nil {
                NSColor.systemGray.setFill(); NSRect(x: badgeX + 1.5 * bq, y: mid - bq, width: 2 * bq, height: 2 * bq).fill()
            } else {
                drawBadge(st, t: t, age: age, petAge: petAge, x: badgeX, midY: mid, q: bq)
            }
            // centre the word on its capital letters, so it lines up with the pixel art
            let ink = dark ? NSColor.white : NSColor(white: 0.08, alpha: 1)
            let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
            let baseline = (mid + font.capHeight / 2).rounded()
            str.draw(at: NSPoint(x: textX, y: baseline - font.ascender))
            return true
        }
        b.title = ""
        b.toolTip = dog.detail.isEmpty ? text : "\(text): \(dog.detail)"
    }

    func applicationWillTerminate(_ n: Notification) { unlink(pidPath) }
}

try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
try? String(getpid()).write(to: pidURL, atomically: true, encoding: .utf8)
signal(SIGTERM) { _ in unlink(pidPath); exit(0) }
signal(SIGINT) { _ in unlink(pidPath); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, not in Cmd-Tab
let delegate = AppDelegate()
app.delegate = delegate
app.run()
