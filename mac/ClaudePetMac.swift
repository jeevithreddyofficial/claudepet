// ClaudePet for macOS: a tiny pixel dog that shows what Claude Code is doing.
// Reads the state files written by claudepet/hook.py from ~/.claudepet/sessions/.
// Built automatically by `claudepet start` (swiftc -O mac/ClaudePetMac.swift -o ~/.claudepet/ClaudePetMac).
//
//   click  → pet the dog (hearts, wakes it up)     hover → label shows what Claude is doing
//   drag   → move it (position is remembered)      right-click → Dog / Cat, Size, Move to corner, Quit
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
let GLYPHS: [String: [String]] = [
    "z": ["111", "001", "010", "100", "111"],
    "!": ["1", "1", "1", "0", "1"],
    "heart": ["01010", "11111", "11111", "01110", "00100"],
    "spark": ["010", "111", "010"],
    "dot": ["1"],
]

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
var WIN: NSSize { NSSize(width: max(CGFloat(GW) * S, 72), height: ART_H + 2 + LABEL_H) }   // 72 × 68 at Medium
let JUMP = [0, -1, -2, -3, -3, -2, -1, 0, 0, -1, -2, -1, 0]

final class Particle {
    var x: Double, y: Double, life: Int
    let vy: Double, glyph: String, color: NSColor
    init(_ x: Double, _ y: Double, _ glyph: String, _ color: NSColor, vy: Double, life: Int) {
        self.x = x; self.y = y; self.glyph = glyph; self.color = color; self.vy = vy; self.life = life
    }
}
struct Px { let x: Int, y: Int, w: Int, h: Int, c: NSColor }

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

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // -- state ---------------------------------------------------------------------
    func poll() {
        var (st, det, last) = readState()
        lastActivity = last
        let quiet = Date().timeIntervalSince1970 - max(last, lastPoke)
        if st == "idle" && quiet > SLEEP_AFTER { st = "asleep" }
        if st != state { state = st; since = t; particles.removeAll() }
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
        let ox = (bounds.width - CGFloat(GW) * S) / 2      // centre the art if the window is wider than it
        for p in pixels {
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
        let r = NSRect(x: (bounds.width - w) / 2, y: ART_H + 2, width: w, height: h)
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

    func showMenu(_ e: NSEvent) {
        let m = NSMenu()
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
        m.addItem(sizeItem)
        m.addItem(.separator())
        let reset = NSMenuItem(title: "Move to corner", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        let quit = NSMenuItem(title: "Quit ClaudePet", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        m.addItem(reset); m.addItem(.separator()); m.addItem(quit)
        NSMenu.popUpContextMenu(m, with: e, for: self)
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
        w.setFrame(NSRect(x: midX - WIN.width / 2, y: top - WIN.height, width: WIN.width, height: WIN.height), display: true)
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
        panel.contentView = dog
        panel.orderFrontRegardless()

        dog.poll()
        let timer = Timer(timeInterval: 0.11, repeats: true) { [weak self] _ in self?.dog.tick() }
        RunLoop.main.add(timer, forMode: .common)
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
