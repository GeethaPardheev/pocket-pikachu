import AppKit
import WebKit
import ApplicationServices
import CoreAudio

struct TypingActivity {
    var until = 0.0
    var presses: [Double] = []
    mutating func pulse(at time: Double) {
        until = time + 0.7
        presses = Array(presses.filter { time - $0 < 2 }.suffix(39)); presses.append(time)
    }
    func active(at time: Double) -> Bool { time < until }
    func cadence(at time: Double) -> Double {
        let rate = Double(presses.filter { time - $0 < 2 }.count) / 2
        return rate >= 6 ? 0.065 : rate >= 2.5 ? 0.12 : 0.22
    }
}

struct TerminalEvent: Decodable {
    let kind: String
    let code: Int
    let duration: Int
    let time: Double
    let session: String
    let app: String
    var valid: Bool {
        ["success","failure","attention"].contains(kind) && duration >= 0 && duration < 31536000 &&
        session.count <= 32 && session.allSatisfy { $0.isLetter || $0.isNumber } &&
        ["terminal","iterm","vscode","jetbrains","unknown"].contains(app)
    }
    var message: String {
        let label = session == "terminal" ? "Terminal" : session
        switch kind {
        case "success": return "\(label): command finished"
        case "failure": return "\(label): failed (\(code))"
        default: return "\(label): needs your help"
        }
    }
}

struct WalkReminder {
    var next = 0.0
    var interval = 1200.0
    mutating func due(at now: Double, enabled: Bool) -> Bool {
        guard enabled, now >= next else { return false }
        next = now + interval
        return true
    }
}

enum PetHome: String { case none, cushion, box }

struct LifeState {
    var lastActivity = 0.0
    var sleepAfter = 180.0
    var forcedNap = false
    var focusEnd: Double? = nil
    var nextBreak = 0.0
    var breakInterval = 1800.0
    mutating func activity(at now: Double) { lastActivity = now; forcedNap = false }
    func sleeping(at now: Double, autoSleep: Bool) -> Bool {
        (focusEnd.map { now < $0 } ?? false) || forcedNap || (autoSleep && now - lastActivity >= sleepAfter)
    }
    mutating func completeFocus(at now: Double) -> Bool {
        guard let end = focusEnd, now >= end else { return false }
        focusEnd = nil; activity(at: now); nextBreak = now + breakInterval; return true
    }
    mutating func breakDue(at now: Double, enabled: Bool, sleeping: Bool) -> Bool {
        guard enabled, focusEnd == nil, !sleeping, now >= nextBreak else { return false }
        nextBreak = now + breakInterval; return true
    }
}

struct Excursion {
    enum Kind { case treat, chase }
    var kind: Kind
    var origin: NSPoint
    var target: NSPoint
    var start: Double
    var duration: Double
    func position(at now: Double) -> NSPoint {
        let progress = min(1, max(0, (now-start)/duration))
        let travel = progress < 0.4 ? progress/0.4 : progress < 0.6 ? 1 : (1-progress)/0.4
        let eased = travel * travel * (3 - 2 * travel)
        return NSPoint(x: origin.x + (target.x-origin.x)*eased, y: origin.y + (target.y-origin.y)*eased)
    }
}

struct BallGame {
    var origin: NSPoint
    var from: NSPoint
    var to: NSPoint
    var start: Double
    var duration = 1.0
    var runsLeft: Int
    var returning = false
    var ballFrom: NSPoint
    var ballTo: NSPoint
    var ballStart = 0.0
    var ballDuration = 1.0
    let pause = 0.35
    let radius = 15.0
    init(origin: NSPoint, start: Double, runs: Int) {
        self.origin = origin; from = origin; to = origin; ballFrom = origin; ballTo = origin; self.start = start; runsLeft = runs
    }
    func position(at now: Double) -> NSPoint {
        let t = min(1, max(0, (now-start)/duration)), eased = t*t*(3-2*t)
        return NSPoint(x: from.x+(to.x-from.x)*eased, y: from.y+(to.y-from.y)*eased)
    }
    func waiting(at now: Double) -> Bool { now < start }
    func finished(at now: Double) -> Bool { now >= start+duration }
    // The ball shoots off and slows to a stop, so it settles before the cat arrives.
    func ballPosition(at now: Double) -> NSPoint {
        let t = min(1, max(0, (now-ballStart)/ballDuration)), eased = 1-(1-t)*(1-t)*(1-t)
        return NSPoint(x: ballFrom.x+(ballTo.x-ballFrom.x)*eased, y: ballFrom.y+(ballTo.y-ballFrom.y)*eased)
    }
    // Radians the ball has rolled; rolling to the right turns clockwise.
    func ballRoll(at now: Double) -> Double {
        let p = ballPosition(at: now)
        return hypot(p.x-ballFrom.x, p.y-ballFrom.y)/radius*(ballTo.x >= ballFrom.x ? -1 : 1)
    }
    mutating func run(to target: NSPoint, at now: Double) {
        let distance = hypot(target.x-to.x, target.y-to.y)
        ballFrom = ballTo; ballTo = target; ballStart = now; ballDuration = min(2.5, max(0.8, distance/400))
        travel(to: target, at: now, distance: distance); runsLeft -= 1
    }
    mutating func goHome(at now: Double) { travel(to: origin, at: now, distance: hypot(origin.x-to.x, origin.y-to.y)); returning = true }
    // A quick swat, then a steady run while the ball is still rolling; never teleports, never crawls.
    private mutating func travel(to target: NSPoint, at now: Double, distance: Double) {
        from = to; to = target; start = now+pause; duration = min(4, max(1, distance/250))
    }
}

func direction(_ dx: Double, _ dy: Double) -> Int? {
    guard hypot(dx, dy) > 22 else { return nil }
    let degrees = atan2(dx, dy) * 180 / .pi
    return Int((degrees + 360).truncatingRemainder(dividingBy: 360) / 22.5 + 0.5) % 16
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    var typingPhase: Int? = nil
    var home: PetHome = .none
    var homeDepth = 0.0
    var snoozing = false
    var happy = false
    var stretching = false
    var dancing = false
    var mirrored = false
    var headphones = false
    var gazeDirection: Int? = nil
    var clock = 0.0
    var caption: String? = nil
    var sprite: NSImage? { didSet { needsDisplay = true } }
    var downPoint = NSPoint.zero
    var downOrigin = NSPoint.zero
    var moved = false
    weak var owner: Companion?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let sx = bounds.width / 192, sy = bounds.height / 208
        if home == .cushion {
            NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.48, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7*sx,y: 0,width: 178*sx,height: 30*sy)).fill()
            NSColor(calibratedRed: 0.53, green: 0.68, blue: 0.62, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 14*sx,y: 7*sy,width: 164*sx,height: 22*sy)).fill()
        } else if home == .box {
            NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.19, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12*sx,y: 2*sy,width: 168*sx,height: 67*sy), xRadius: 4*sx, yRadius: 4*sy).fill()
        }
        var body = bounds
        body.origin.y -= homeDepth * 17 * sy
        if snoozing { body.size.height -= (1 + sin(clock*1.8))*1.5*sy }
        if headphones && !snoozing { body.origin.y += sin(clock*4)*2*sy }
        if happy { body.origin.y += sin(clock*5)*1.2*sy }
        if dancing { body.origin.y += abs(sin(clock*7))*7*sy; body.origin.x += sin(clock*3.5)*6*sx }
        if stretching {
            let lift = max(0, sin(clock*2.5))
            body.size.height -= 8*sy; body.origin.y += lift*6*sy
        }
        NSGraphicsContext.saveGraphicsState()
        // Poses face left; on the left half of the screen flip them so Pikachu faces into the screen.
        if mirrored { let flip = NSAffineTransform(); flip.translateX(by: bounds.width, yBy: 0); flip.scaleX(by: -1, yBy: 1); flip.concat() }
        sprite?.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        if home == .box {
            NSColor(calibratedRed: 0.76, green: 0.54, blue: 0.32, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 10*sx,y: 0,width: 172*sx,height: 39*sy),xRadius: 3*sx,yRadius: 3*sy).fill()
            NSColor(calibratedRed: 0.90, green: 0.73, blue: 0.48, alpha: 1).setFill()
            NSRect(x: 88*sx,y: 0,width: 16*sx,height: 39*sy).fill()
        }
        if snoozing { label("z z z", at: NSRect(x: 140*sx,y: 150*sy,width: 45*sx,height: 20*sy),size: 12*sx) }
        if happy { label("♡", at: NSRect(x: 140*sx,y: 155*sy,width: 36*sx,height: 25*sy),size: 22*sx) }
        if let phase = typingPhase {
            // Runtime vector keyboard; no typed characters are displayed or stored.
            let sx = bounds.width / 192, sy = bounds.height / 208
            let board = NSRect(x: 33*sx, y: 9*sy, width: 126*sx, height: 35*sy)
            NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
            NSBezierPath(roundedRect: board, xRadius: 5*sx, yRadius: 5*sy).fill()
            for r in 0..<3 { for c in 0..<10 {
                let key = NSRect(x: (39+Double(c)*11.5)*sx, y: (14+Double(r)*8)*sy, width: 8.5*sx, height: 5.5*sy)
                (c == (phase % 2 == 0 ? 2 : 7) && r == 1 ? NSColor.systemTeal : NSColor(calibratedWhite: 0.68, alpha: 1)).setFill()
                NSBezierPath(roundedRect: key, xRadius: sx, yRadius: sy).fill()
            } }
            for side in 0..<2 {
                let lift = phase % 2 == side ? 0.0 : 7.0
                let paw = NSRect(x: (57+Double(side)*52)*sx, y: (28+lift)*sy, width: 24*sx, height: 18*sy)
                NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.56, alpha: 1).setFill()
                let shape = NSBezierPath(ovalIn: paw); shape.fill()
                NSColor(calibratedRed: 0.62, green: 0.44, blue: 0.26, alpha: 1).setStroke()
                shape.lineWidth = 0.8*sx; shape.stroke()
            }
        }
    }
    func label(_ text: String, at rect: NSRect, size: Double, color: NSColor = .darkGray) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: rect,withAttributes: [.font: NSFont.systemFont(ofSize: size,weight: .medium),.foregroundColor: color,.paragraphStyle: paragraph])
    }
    override func mouseDown(with event: NSEvent) {
        owner?.beginDrag()
        downPoint = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - downPoint.x, dy = point.y - downPoint.y
        guard hypot(dx, dy) > 3 else { return }
        moved = true
        window?.setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy))
        owner?.play(dx < 0 ? 2 : 1, duration: 0.2)
    }
    override func mouseUp(with event: NSEvent) {
        if moved { owner?.screenChanged(); owner?.savePosition() }
        else if event.clickCount > 1 { owner?.jump() }
        else { owner?.wave() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = owner?.menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class TreatView: NSView {
    weak var owner: Companion?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        NSColor(calibratedRed: 0.93,green: 0.63,blue: 0.35,alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 9,y: 9,width: 29,height: 20)).fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 11,y: 19)); tail.line(to: NSPoint(x: 1,y: 8));tail.line(to: NSPoint(x: 1,y: 30));tail.close();tail.fill()
        NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 29,y: 20,width: 3,height: 3)).fill()
    }
    override func mouseDown(with event: NSEvent) { owner?.eatTreat() }
}

// Pikachu tail silhouette as a template menu-bar icon: narrow base, two steps, big flat-topped block.
func tailIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18)); image.lockFocus()
    let s = 18.0/20
    let pts: [(Double, Double)] = [(2,0),(5,0),(6,4),(10,3.5),(11.5,8.5),(20,8),(19,19.5),(8.5,20),(9,14),(5,14.5),(6,10),(1.5,10.5),(2.5,5)]
    let path = NSBezierPath(); path.move(to: NSPoint(x: pts[0].0*s, y: pts[0].1*s)); for q in pts.dropFirst() { path.line(to: NSPoint(x: q.0*s, y: q.1*s)) }; path.close()
    NSColor.black.setFill(); path.fill(); image.unlockFocus(); image.isTemplate = true
    return image
}

final class ThunderView: NSView {
    struct Bolt { var down: Bool; var main: [NSPoint]; var glow: NSImage; var core: NSImage; var leaderStart: Double; var strokes: [(at: Double, strength: Double)] }
    var phase = 0.0 { didSet { needsDisplay = true } }
    var duration = 2.4
    var origin = NSPoint.zero            // Pikachu's head: the call goes up from here
    var target = NSPoint.zero            // where the sky answers
    var bolts: [Bolt] = []
    var sparks: [(birth: Double, angle: Double, speed: Double, length: Double)] = []
    // Timing as fractions of the 2.4 s clip. Pikachu's charge goes up on "CHUUU", the sky answers a beat later with a
    // leader racing down to the target, the return stroke blazes and re-strikes the same channel; a second, smaller
    // strike lands on the tail of the cry.
    static let plan: [(down: Bool, leader: Double, strokes: [(at: Double, strength: Double)])] = [
        (false, 0.21, [(0.242, 0.8)]),
        (true, 0.255, [(0.29, 1.0), (0.333, 0.7), (0.39, 0.85), (0.44, 0.45)]),
        (true, 0.525, [(0.5417, 0.7), (0.575, 0.4)])]
    static let dischargeStart = 0.21, firstStroke = 0.29, quiet = 0.66
    static func discharge(_ p: Double) -> Double {
        var k = 0.0
        for bolt in plan where bolt.down { for s in bolt.strokes where p >= s.at { k += s.strength * (p-s.at < 0.006 ? 1 : exp(-(p-s.at-0.006)/0.016)) } }
        return min(1, k)
    }
    func prepare(origin from: NSPoint, target to: NSPoint) {
        origin = from; target = to; bolts = []
        sparks = Self.plan.filter { $0.down }.flatMap { $0.strokes }.flatMap { s in (0..<14).map { _ in (s.at, Double.random(in: 0.3...(Double.pi-0.3)), Double.random(in: 200...700)*s.strength, Double.random(in: 8...26)) } }
        warm()
    }
    func warm() {
        guard bolts.count < Self.plan.count else { return }
        let n = bolts.count, spec = Self.plan[n]
        bolts.append(renderBolt(down: spec.down, strength: n == 0 ? 0.55 : n == 1 ? 1.0 : 0.65, leaderStart: spec.leader, strokes: spec.strokes))
    }
    // Midpoint displacement at nine levels gives the fine tortuosity of a real channel.
    func channel(from a: NSPoint, to b: NSPoint, depth: Int, jag: Double) -> [NSPoint] {
        if depth == 0 { return [a, b] }
        let dx = b.x-a.x, dy = b.y-a.y, len = max(1, hypot(dx, dy)), off = Double.random(in: -jag...jag)*len
        let m = NSPoint(x: (a.x+b.x)/2 - dy/len*off, y: (a.y+b.y)/2 + dx/len*off)
        return channel(from: a, to: m, depth: depth-1, jag: jag) + channel(from: m, to: b, depth: depth-1, jag: jag).dropFirst()
    }
    func polyline(_ pts: [NSPoint], scale: Double = 1) -> NSBezierPath { let p = NSBezierPath(); p.move(to: NSPoint(x: pts[0].x*scale, y: pts[0].y*scale)); for q in pts.dropFirst() { p.line(to: NSPoint(x: q.x*scale, y: q.y*scale)) }; p.lineJoinStyle = .round; p.lineCapStyle = .round; return p }
    // One channel, ordered in the direction it propagates, with a handful of dimmer branches. White core, blue-violet glow.
    func renderBolt(down: Bool, strength: Double, leaderStart: Double, strokes: [(at: Double, strength: Double)]) -> Bolt {
        let w = bounds.width, h = bounds.height
        let start = down ? NSPoint(x: min(w-20, max(20, target.x + Double.random(in: -w*0.25...w*0.25))), y: h+30) : origin
        let end = down ? NSPoint(x: target.x + Double.random(in: -12...12), y: target.y) : NSPoint(x: min(w-20, max(20, origin.x + Double.random(in: -w*0.15...w*0.15))), y: h+30)
        let main = channel(from: start, to: end, depth: 9, jag: 0.13)
        var paths: [([NSPoint], Double)] = [(main, 1)]
        for _ in 0..<Int(Double.random(in: 4...7)*strength+1) {
            let i = Int.random(in: main.count/6..<max(main.count/6+1, main.count*5/6)), p = main[i]
            let dir = atan2(end.y-p.y, end.x-p.x) + Double.random(in: 0.35...1.0) * (Bool.random() ? 1 : -1)
            let len = hypot(end.x-p.x, end.y-p.y)*Double.random(in: 0.12...0.4)
            let branch = channel(from: p, to: NSPoint(x: p.x+cos(dir)*len, y: p.y+sin(dir)*len), depth: 6, jag: 0.2)
            paths.append((branch, Double.random(in: 0.3...0.5)))
            if Bool.random() {
                let q = branch[Int.random(in: 2..<max(3, branch.count-2))], d2 = dir + Double.random(in: -0.8...0.8), l2 = len*Double.random(in: 0.25...0.5)
                paths.append((channel(from: q, to: NSPoint(x: q.x+cos(d2)*l2, y: q.y+sin(d2)*l2), depth: 5, jag: 0.22), 0.18))
            }
        }
        let glow = NSImage(size: NSSize(width: w/4, height: h/4)); glow.lockFocus()
        for (pts, weight) in paths {
            let path = polyline(pts, scale: 0.25)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 10*strength; shadow.shadowColor = NSColor(calibratedRed: 0.55, green: 0.62, blue: 1, alpha: min(1, weight*1.1)); shadow.set()
            NSColor(calibratedRed: 0.7, green: 0.76, blue: 1, alpha: 0.7*weight).setStroke(); path.lineWidth = 2.4*weight*strength; path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        glow.unlockFocus()
        let core = NSImage(size: bounds.size); core.lockFocus()
        for (pts, weight) in paths {
            let path = polyline(pts)
            NSColor(calibratedRed: 0.86, green: 0.9, blue: 1, alpha: 0.55*weight).setStroke(); path.lineWidth = 6*weight*strength; path.stroke()
            NSColor(calibratedWhite: 1, alpha: min(1, weight+0.3)).setStroke(); path.lineWidth = max(1, 2.4*weight*strength); path.stroke()
        }
        core.unlockFocus()
        return Bolt(down: down, main: main, glow: glow, core: core, leaderStart: leaderStart, strokes: strokes)
    }
    func hotSpot(_ c: NSPoint, _ r: Double, _ k: Double, warm: Bool = false) {
        let mid = warm ? NSColor(calibratedRed: 1, green: 0.75, blue: 0.4, alpha: 0.35*k) : NSColor(calibratedRed: 0.8, green: 0.85, blue: 1, alpha: 0.35*k)
        NSGradient(colorsAndLocations: (NSColor(calibratedWhite: 1, alpha: 0.9*k), 0), (mid, 0.4), (.clear, 1))?.draw(in: NSBezierPath(ovalIn: NSRect(x: c.x-r, y: c.y-r, width: 2*r, height: 2*r)), relativeCenterPosition: .zero)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let p = phase
        // A little storm darkness for contrast; it lifts once the flashes are over.
        let dim = p < 0.15 ? p/0.15*0.24 : p > Self.quiet ? max(0, (0.92-p)/0.26)*0.24 : 0.24
        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.08, alpha: dim).setFill(); bounds.fill()
        // Cheek sparks while charging: small, brief, white-blue.
        if p > 0.06 && p < Self.dischargeStart {
            srand48(Int(p*90)); let grow = (p-0.06)/(Self.dischargeStart-0.06)
            for _ in 0..<Int(2+5*grow) where drand48() < 0.6 {
                let a = drand48()*2 * .pi, r = 18+drand48()*(30+50*grow), b = a + (drand48()-0.5)*1.2
                let path = polyline(channel(from: NSPoint(x: origin.x+cos(a)*r*0.3, y: origin.y-30+sin(a)*r*0.3), to: NSPoint(x: origin.x+cos(b)*r, y: origin.y-30+sin(b)*r), depth: 3, jag: 0.28))
                NSColor(calibratedRed: 0.75, green: 0.8, blue: 1, alpha: 0.6).setStroke(); path.lineWidth = 2.2; path.stroke()
                NSColor(calibratedWhite: 1, alpha: 0.9).setStroke(); path.lineWidth = 0.9; path.stroke()
            }
        }
        var impact = 0.0
        for bolt in bolts {
            let first = bolt.strokes[0].at
            // Leader: a dim channel creeping along the path before the return stroke (up from Pikachu, down from the sky).
            if p >= bolt.leaderStart && p < first {
                let f = (p-bolt.leaderStart)/(first-bolt.leaderStart), count = max(2, Int(Double(bolt.main.count)*f))
                let path = polyline(Array(bolt.main.prefix(count)))
                NSColor(calibratedRed: 0.6, green: 0.65, blue: 0.95, alpha: 0.45).setStroke(); path.lineWidth = 3; path.stroke()
                NSColor(calibratedRed: 0.9, green: 0.92, blue: 1, alpha: 0.8).setStroke(); path.lineWidth = 1.1; path.stroke()
            }
            var k = 0.0
            for s in bolt.strokes where p >= s.at { k += s.strength * (p-s.at < 0.006 ? 1 : exp(-(p-s.at-0.006)/0.016)) }
            k = min(1, k)
            guard k > 0.02 else { continue }
            // The whole sky blinks cool white on each return stroke; the channel re-lights along the same path.
            NSColor(calibratedRed: 0.9, green: 0.93, blue: 1, alpha: 0.34*k*k).setFill(); bounds.fill()
            bolt.glow.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: min(1, k*1.1))
            bolt.core.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: k)
            if bolt.down { impact = max(impact, k) } else { hotSpot(origin, 24+40*k, k) }
        }
        // Impact: blinding spot, a low ground ring, sparks thrown upward, and a warm scorch glow that lingers.
        if impact > 0 {
            hotSpot(target, 40+110*impact, impact)
            let u = min(1, max(0, (p-Self.firstStroke)/0.09)), ring = 10+170*u
            if u < 1 { let ringPath = NSBezierPath(ovalIn: NSRect(x: target.x-ring, y: target.y-ring*0.35, width: 2*ring, height: ring*0.7)); NSColor(calibratedRed: 0.85, green: 0.9, blue: 1, alpha: 0.6*(1-u)).setStroke(); ringPath.lineWidth = 5*(1-u)+1; ringPath.stroke() }
        }
        if p > Self.firstStroke && p < 0.95 { hotSpot(target, 26, 0.5*max(0, (0.95-p)/(0.95-Self.firstStroke)), warm: true) }
        for spark in sparks where p >= spark.birth {
            let t = (p-spark.birth)*duration
            guard t < 0.7 else { continue }
            let head = NSPoint(x: target.x+cos(spark.angle)*spark.speed*t, y: target.y+sin(spark.angle)*spark.speed*t - 1100*t*t)
            let tail = NSPoint(x: head.x-cos(spark.angle)*spark.length*0.6, y: head.y-(sin(spark.angle)*spark.speed-2200*t)*0.012)
            let path = NSBezierPath(); path.move(to: tail); path.line(to: head); path.lineCapStyle = .round
            let a = max(0, 1-t/0.7)
            NSColor(calibratedRed: 1, green: 0.85, blue: 0.5, alpha: 0.9*a).setStroke(); path.lineWidth = 2.6; path.stroke()
            NSColor(calibratedWhite: 1, alpha: a).setStroke(); path.lineWidth = 1.1; path.stroke()
        }
    }
}

final class SpeechBubbleView: NSView {
    var text = ""
    var k = 1.0            // pet scale: 1 at width 192
    var age = 0.0          // seconds since this text appeared
    var fade = 1.0         // 1 -> 0 while disappearing
    var tailX = 0.5        // where the tail points, as a fraction of the width
    var shout: Bool { text.contains("!") }
    static let pad = 15.0, tailH = 20.0, line = 3.4, shadow = 3.0, spike = 9.0
    static func font(_ k: Double) -> NSFont {
        let size = 16*k, base = NSFont.systemFont(ofSize: size, weight: .heavy)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    }
    static func attributes(_ k: Double, alpha: Double = 1) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
        return [.font: font(k), .foregroundColor: NSColor(calibratedRed: 0.29, green: 0.16, blue: 0.04, alpha: alpha), .paragraphStyle: paragraph,
                .strokeColor: NSColor(calibratedRed: 1, green: 0.97, blue: 0.75, alpha: alpha), .strokeWidth: -2.2]
    }
    static func textSize(_ text: String, k: Double, maxWidth: Double) -> NSSize {
        let rect = (text as NSString).boundingRect(with: NSSize(width: maxWidth, height: 600), options: [.usesLineFragmentOrigin], attributes: attributes(k))
        return NSSize(width: ceil(rect.width)+4, height: ceil(rect.height)+2)
    }
    static func size(for text: String, k: Double, maxWidth: Double) -> NSSize {
        let t = textSize(text, k: k, maxWidth: maxWidth), extra = text.contains("!") ? spike*k : 0
        return NSSize(width: t.width + 2*(pad+line+shadow+extra)*k + 6*k, height: t.height + 2*(pad*0.7+line+extra)*k + (tailH+shadow)*k + 8*k)
    }
    // Rounded comic bubble for talk, a spiky electric burst for shouts.
    func shape(_ box: NSRect, tip: NSPoint) -> NSBezierPath {
        let path: NSBezierPath
        if shout {
            path = NSBezierPath(); let n = 22, cx = box.midX, cy = box.midY, rx = box.width/2, ry = box.height/2
            for i in 0..<n {
                let a = Double(i)/Double(n)*2 * .pi, r = i % 2 == 0 ? 1.0 : 0.88
                let px = cx + cos(a)*rx*r, py = cy + sin(a)*ry*r
                i == 0 ? path.move(to: NSPoint(x: px, y: py)) : path.line(to: NSPoint(x: px, y: py))
            }
            path.close()
        } else { path = NSBezierPath(roundedRect: box, xRadius: 16*k, yRadius: 16*k) }
        // Curved tail towards the mouth.
        let tail = NSBezierPath(); let baseL = NSPoint(x: tip.x-13*k, y: box.minY+3*k), baseR = NSPoint(x: tip.x+13*k, y: box.minY+3*k)
        tail.move(to: baseL); tail.curve(to: tip, controlPoint1: NSPoint(x: tip.x-9*k, y: box.minY-8*k), controlPoint2: NSPoint(x: tip.x-2*k, y: tip.y+6*k))
        tail.curve(to: baseR, controlPoint1: NSPoint(x: tip.x+3*k, y: tip.y+6*k), controlPoint2: NSPoint(x: tip.x+10*k, y: box.minY-8*k)); tail.close()
        path.append(tail); path.windingRule = .nonZero; path.lineJoinStyle = .round
        return path
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let line = Self.line*k, shadow = Self.shadow*k, tailH = Self.tailH*k, extra = shout ? Self.spike*k : 0
        let tip = NSPoint(x: bounds.minX + bounds.width*tailX, y: 0)
        // Pop with squash and stretch, wobble, then a gentle bob; exit shrinks toward the tail.
        let pop = age < 0.6 ? 1 - exp(-age*11)*cos(age*20) : 1
        let squashX = age < 0.6 ? 1 + 0.12*exp(-age*9)*sin(age*28) : 1, squashY = age < 0.6 ? 1 - 0.10*exp(-age*9)*sin(age*28) : 1
        let wobble = age < 1.2 ? 3.5*exp(-age*3)*sin(age*14) : 0.6*sin(age*3)
        let scale = pop*(0.6+0.4*fade)
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: tip.x, yBy: tip.y + (age < 0.6 ? 0 : sin(age*4)*1.5*k)); t.rotate(byDegrees: wobble); t.scaleX(by: max(0.01, scale*squashX), yBy: max(0.01, scale*squashY)); t.translateX(by: -tip.x, yBy: -tip.y); t.concat()
        let box = NSRect(x: line+shadow+extra, y: tailH+line+extra, width: bounds.width-2*(line+shadow+extra), height: bounds.height-tailH-2*(line+extra)-shadow)
        let body = shape(box, tip: tip)
        NSColor(calibratedWhite: 0, alpha: 0.32*fade).setFill(); let sh = NSAffineTransform(); sh.translateX(by: shadow, yBy: -shadow); sh.transform(body).fill()
        NSGraphicsContext.saveGraphicsState(); body.addClip()
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.90, blue: 0.32, alpha: fade), ending: NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.10, alpha: fade))?.draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.33, green: 0.19, blue: 0.06, alpha: fade).setStroke(); body.lineWidth = line; body.stroke()
        NSColor(calibratedWhite: 1, alpha: 0.5*fade).setFill()
        NSBezierPath(roundedRect: NSRect(x: box.minX+14*k, y: box.maxY-10*k-extra*0.6, width: box.width-28*k, height: 4.5*k), xRadius: 2.2*k, yRadius: 2.2*k).fill()
        if shout {   // little bolts in two corners
            for (cx, cy, flip) in [(box.minX+9*k, box.maxY-10*k, 1.0), (box.maxX-9*k, box.minY+12*k, -1.0)] {
                let bolt = NSBezierPath(); bolt.move(to: NSPoint(x: cx-3*k*flip, y: cy+7*k)); bolt.line(to: NSPoint(x: cx+2*k*flip, y: cy+1*k)); bolt.line(to: NSPoint(x: cx-1*k*flip, y: cy+1*k)); bolt.line(to: NSPoint(x: cx+3*k*flip, y: cy-7*k)); bolt.line(to: NSPoint(x: cx-2*k*flip, y: cy-1*k)); bolt.line(to: NSPoint(x: cx+1*k*flip, y: cy-1*k)); bolt.close()
                NSColor(calibratedRed: 0.33, green: 0.19, blue: 0.06, alpha: 0.85*fade).setFill(); bolt.fill()
            }
        }
        // Typewriter reveal, about 30 characters a second.
        let shown = String(text.prefix(max(1, Int(age*30)+1)))
        let textRect = box.insetBy(dx: Self.pad*k+extra*0.5, dy: 0)
        let textHeight = Self.textSize(text, k: k, maxWidth: textRect.width).height
        (shown as NSString).draw(in: NSRect(x: textRect.minX, y: box.midY-textHeight/2-1*k, width: textRect.width, height: textHeight+4*k), withAttributes: Self.attributes(k, alpha: fade))
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class BallView: NSView {
    var roll = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        // Poké Ball style: red top, white bottom, black band and button. Geometry scales with the view (42x38 at pet size 192).
        let k = bounds.width/42, center = NSPoint(x: bounds.midX,y: bounds.midY), r = 15*k, spin = NSAffineTransform()
        spin.translateX(by: center.x,yBy: center.y); spin.rotate(byRadians: roll); spin.translateX(by: -center.x,yBy: -center.y)
        NSGraphicsContext.saveGraphicsState(); spin.concat()
        let ball = NSBezierPath(ovalIn: NSRect(x: center.x-r,y: center.y-r,width: 2*r,height: 2*r))
        NSColor.white.setFill(); ball.fill()
        NSGraphicsContext.saveGraphicsState(); ball.addClip()
        NSColor(calibratedRed: 0.87,green: 0.16,blue: 0.16,alpha: 1).setFill(); NSRect(x: center.x-r,y: center.y,width: 2*r,height: r).fill()
        NSColor(calibratedWhite: 0.12,alpha: 1).setFill(); NSRect(x: center.x-r,y: center.y-2*k,width: 2*r,height: 4*k).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.12,alpha: 1).setStroke(); ball.lineWidth = 1.6*k; ball.stroke()
        NSColor(calibratedWhite: 0.12,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: center.x-5.5*k,y: center.y-5.5*k,width: 11*k,height: 11*k)).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: center.x-3.3*k,y: center.y-3.3*k,width: 6.6*k,height: 6.6*k)).fill()
        NSColor(calibratedWhite: 1,alpha: 0.4).setFill(); NSBezierPath(ovalIn: NSRect(x: center.x-10*k,y: center.y+5*k,width: 8*k,height: 5*k)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class EmbeddedTerminal: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var web: WKWebView!
    var process: Process?
    let input = Pipe()
    let output = Pipe()
    let directory: URL
    let writer = DispatchQueue(label: "pikachu.terminal.input")
    var number = 0
    var closed = false
    var started = false
    var ready = false
    init(directory: URL) {
        self.directory = directory; super.init()
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self,name: "terminal")
        web = WKWebView(frame: .zero,configuration: config); web.navigationDelegate = self
        let folder = Bundle.main.resourceURL!.appendingPathComponent("terminal")
        web.loadFileURL(folder.appendingPathComponent("index.html"),allowingReadAccessTo: folder)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let expected = Bundle.main.resourceURL!.appendingPathComponent("terminal/index.html").standardizedFileURL
        decisionHandler(navigationAction.request.url?.standardizedFileURL == expected ? .allow : .cancel)
    }
    func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !closed, let data = message.body as? [String:Any],let kind = data["kind"] as? String else { return }
        if kind == "ready" && !started { ready = true; start(); send(["kind":"resize","cols":data["cols"] ?? 80,"rows":data["rows"] ?? 24]) }
        else if kind == "input", let text = data["data"] as? String, text.utf8.count <= 1000000 { send(["kind":"input","data":Data(text.utf8).base64EncodedString()]) }
        else if kind == "resize" { send(["kind":"resize","cols":data["cols"] ?? 80,"rows":data["rows"] ?? 24]) }
    }
    func start() {
        guard !closed,!started else { return }; started = true
        let task = Process(); process = task
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [Bundle.main.resourceURL!.appendingPathComponent("terminal/pty_host.py").path]
        task.currentDirectoryURL = directory; task.standardInput = input; task.standardOutput = output; task.standardError = output
        do { try task.run() } catch { display(Data("Could not open shell: \(error.localizedDescription)".utf8)); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let owner = self else { return }
            while true {
                let data = owner.output.fileHandleForReading.availableData
                if data.isEmpty { break }
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    guard !owner.closed else { done.signal(); return }
                    owner.web.callAsyncJavaScript("await window.feed(data)",arguments: ["data":data.base64EncodedString()],in: nil,in: .page) { _ in done.signal() }
                }
                // Limit outstanding renderer work. A closed/unresponsive web view must not block cleanup.
                _ = done.wait(timeout: .now()+5)
            }
            task.waitUntilExit()
            DispatchQueue.main.async { if !owner.closed { owner.display(Data("\r\n[Terminal ended · exit \(task.terminationStatus)]\r\n".utf8)) } }
        }
    }
    func display(_ data: Data) { web.callAsyncJavaScript("await window.feed(data)",arguments: ["data":data.base64EncodedString()],in: nil,in: .page,completionHandler: nil) }
    func send(_ object: [String:Any]) {
        guard !closed,let process = process,process.isRunning,let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        writer.async { [weak self] in
            guard let self = self else { return }
            do { try self.input.fileHandleForWriting.write(contentsOf: data+Data([10])) } catch { }
        }
    }
    func focus() { web.evaluateJavaScript("window.focusTerminal()",completionHandler: nil) }
    func stop() {
        guard !closed else { return }; closed = true
        web.configuration.userContentController.removeScriptMessageHandler(forName: "terminal")
        if let process = process,process.isRunning { process.terminate() }
        writer.async { [weak self] in try? self?.input.fileHandleForWriting.close() }
    }
}
final class TerminalDesk: NSObject, NSWindowDelegate, NSTabViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 720,height: 440),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
    let tabs = NSTabView()
    var terminals: [EmbeddedTerminal] = []
    var counter = 0
    var voice: GeminiVoice?
    override init() {
        super.init(); window.title = "Pocket Pikachu · Terminal Desk"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 650,height: 280); window.level = .floating
        let root = window.contentView!
        tabs.frame = NSRect(x: 8,y: 8,width: 704,height: 382); tabs.autoresizingMask = [.width,.height]; tabs.delegate = self; root.addSubview(tabs)
        for (title,selector,x,width) in [("+ Terminal",#selector(addDefault),8.0,100.0),("+ In folder…",#selector(addFolder),112.0,110.0),("End tab",#selector(closeTab),226.0,85.0),("Expand",#selector(expand),315.0,80.0),("Paste",#selector(paste),399.0,70.0),("Copy",#selector(copyText),473.0,70.0),("Voice",#selector(openVoice),547.0,75.0)] {
            let b = NSButton(title: title,target: self,action: selector); b.bezelStyle = .rounded; b.frame = NSRect(x: x,y: 402,width: width,height: 28); b.autoresizingMask = [.minYMargin]; root.addSubview(b)
        }
        addDefault()
    }
    @objc func addDefault() { add(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { add(url) }
    }
    func add(_ directory: URL) {
        counter += 1
        let terminal = EmbeddedTerminal(directory: directory); terminal.number = counter; terminals.append(terminal)
        let tab = NSTabViewItem(identifier: terminal); tab.label = "\(counter) · \(directory.lastPathComponent)"; tab.view = terminal.web
        tabs.addTabViewItem(tab); tabs.selectTabViewItem(tab)
        window.title = "Pocket Pikachu · Terminal Desk · \(terminals.count) tabs"
    }
    var selected: EmbeddedTerminal? { tabs.selectedTabViewItem?.identifier as? EmbeddedTerminal }
    @objc func closeTab() {
        guard let tab = tabs.selectedTabViewItem,let terminal = selected else { return }
        if terminal.process?.isRunning == true {
            let alert = NSAlert(); alert.messageText = "End this terminal?"; alert.informativeText = "This closes its shell and may interrupt commands running in this tab."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "End terminal")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        terminal.stop(); terminals.removeAll { $0 === terminal }; tabs.removeTabViewItem(tab)
        window.title = "Pocket Pikachu · Terminal Desk · \(terminals.count) tabs"
    }
    @objc func expand() { window.zoom(nil) }
    @objc func paste() {
        guard let text = NSPasteboard.general.string(forType: .string),text.utf8.count <= 1000000 else { return }
        selected?.web.callAsyncJavaScript("window.pasteText(text)",arguments: ["text":text],in: nil,in: .page,completionHandler: nil)
    }
    @objc func copyText() {
        selected?.web.evaluateJavaScript("window.copySelection()") { result,_ in
            if let text = result as? String,!text.isEmpty { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType: .string) }
        }
    }
    func tabView(_ tabView: NSTabView,didSelect tabViewItem: NSTabViewItem?) { selected?.focus() }
    func show(above pet: NSRect) {
        if !window.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(pet.center) } ?? NSScreen.main
            if let area = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: max(area.minX,min(pet.midX-window.frame.width/2,area.maxX-window.frame.width)),y: max(area.minY,min(pet.maxY+8,area.maxY-window.frame.height))))
            }
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); selected?.focus()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { window.orderOut(nil); return false }
    @objc func openVoice() { if voice == nil { voice = GeminiVoice(desk: self) }; voice?.show() }
    func voiceContext(_ completion: @escaping (String) -> Void) {
        let items = Array(terminals.prefix(8))
        var snapshots: [Int: String] = [:]
        var remaining = items.count
        guard remaining > 0 else { completion("No pet terminals are open."); return }
        for terminal in items {
            let id = terminal.number
            terminal.web.evaluateJavaScript("window.voiceSnapshot()") { [weak self, weak terminal] result, _ in
                if let self = self, let terminal = terminal, self.terminals.contains(where: { $0 === terminal }) {
                    snapshots[id] = "Tab \(id), selected=\(self.selected === terminal), shellAlive=\(terminal.process?.isRunning == true):\n" + String((result as? String ?? "Screen unavailable").suffix(4000))
                }
                remaining -= 1
                if remaining == 0 { completion(snapshots.keys.sorted().compactMap { snapshots[$0] }.joined(separator: "\n---\n")) }
            }
        }
    }
    func voiceAction(_ action: VoiceTerminalAction) -> [String:Any] {
        if action.name == "list_terminals" {
            return ["terminals":terminals.map { ["id":$0.number,"folder":$0.directory.lastPathComponent,"ready":$0.ready && $0.process?.isRunning == true,"selected":$0 === selected] as [String:Any] }]
        }
        if action.name == "create_terminal" { addDefault(); return ["created_terminal_id":counter,"status":"starting; list terminals before sending"] }
        guard let id = action.terminalID,let terminal = terminals.first(where: { $0.number == id }),terminal.ready,terminal.process?.isRunning == true,!terminal.closed else { return ["error":"That pet terminal does not exist or is not ready."] }
        if let tab = tabs.tabViewItems.first(where: { ($0.identifier as? EmbeddedTerminal) === terminal }) { tabs.selectTabViewItem(tab) }
        if action.name == "send_terminal" {
            let data = Data((action.text+(action.submit ? "\r" : "")).utf8)
            terminal.send(["kind":"input","data":data.base64EncodedString()])
            return ["status":"queued input; command outcome unknown","terminal_id":id,"text":action.text,"submitted":action.submit]
        }
        terminal.send(["kind":"input","data":Data([action.key == "escape" ? 27 : 3]).base64EncodedString()])
        return ["status":"queued interrupt key; process outcome unknown","terminal_id":id,"key":action.key]
    }
    func shutdown() { voice?.stop(); terminals.forEach { $0.stop() } }
}

final class Companion: NSObject, NSApplicationDelegate {
    var panel: PetPanel!
    var pet = PetView()
    var status: NSStatusItem!
    let menu = NSMenu()
    var images: [String: NSImage] = [:]
    var timer: Timer?
    var paused = false
    var pauseItem: NSMenuItem!
    var actionRow = 0
    var actionStart = 0.0
    var actionUntil = 0.0
    var typing = TypingActivity()
    var typingEnabled = UserDefaults.standard.object(forKey: "typingEnabled") as? Bool ?? true
    var globalKeys: Any?
    var localKeys: Any?
    var permissionCheck = 0.0
    var typingItem: NSMenuItem!
    var typingStatus: NSMenuItem!
    var lastKeyActivity = 0.0
    var permissionItem: NSMenuItem!
    var life = LifeState()
    var autoSleep = true
    var mischief = true
    var breakReminders = true
    var walkReminders = true
    var walk = WalkReminder()
    var walkUntil = 0.0
    var walkItem: NSMenuItem!
    var focusReminders = true
    var focusReminder = WalkReminder(interval: 1800)
    var focusUntil = 0.0
    var focusReminderItem: NSMenuItem!
    var ballGame: BallGame?
    var ballPanel: PetPanel?
    var thunderPanel: PetPanel?
    var bubblePanel: PetPanel?
    var bubbleText: String?
    var bubbleSince = 0.0
    var bubbleFadeStart = 0.0
    var thunderStart = 0.0
    let thunderDuration = 2.4
    var thunderBase = NSPoint.zero
    var thunderRumbled = false
    var rumbleSound: NSSound?
    var sounds = false
    var voiceEnabled = UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool ?? true
    var voiceItem: NSMenuItem!
    var voiceClips: [String: NSSound] = [:]
    var voiceSound: NSSound?
    var ownAudioUntil = 0.0   // auto-headphones ignore the output device while our own clips play
    var home: PetHome = .cushion
    var lastMouse = NSPoint.zero
    var pettingTravel = 0.0
    var pettingWindow = 0.0
    var pettingUntil = 0.0
    var lastPetSound = 0.0
    var lastChase = 0.0
    var excursion: Excursion?
    var treatPanel: PetPanel?
    var treatExpires = 0.0
    var notice: String?
    var noticeUntil = 0.0
    var stretchUntil = 0.0
    var focusItem: NSMenuItem!
    var sleepItem: NSMenuItem!
    var mischiefItem: NSMenuItem!
    var breakItem: NSMenuItem!
    var soundItem: NSMenuItem!
    var homeItems: [PetHome: NSMenuItem] = [:]
    var sound: NSSound?
    var musicMode = false
    var autoAudio = UserDefaults.standard.object(forKey: "autoAudio") as? Bool ?? true
    var audioActive = false
    var audioCheck = 0.0
    var musicItem: NSMenuItem!
    var audioItem: NSMenuItem!
    var terminalEnabled = UserDefaults.standard.object(forKey: "terminalEnabled") as? Bool ?? true
    var terminalCheck = 0.0
    var terminalSince = Date().timeIntervalSince1970
    var terminalUntil = 0.0
    var terminalMessage: String?
    var terminalItem: NSMenuItem!
    var terminalHistory = NSMenu(title: "Terminal activity")
    var terminalDesk: TerminalDesk?
    let counts = [6,8,8,4,5,8,6,6,6,8,8]
    // Fun dance shows every action pose, starting with the paws-up row.
    lazy var danceFrames: [(Int, Int)] = [6,7,8,0,1,2,3,4,5].flatMap { r in (0..<counts[r]).map { (r, $0) } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else { NSApp.terminate(nil); return }
        for row in 0..<11 {
            for col in 0..<counts[row] {
                let key = "\(row)-\(col)"
                guard let image = NSImage(contentsOf: resources.appendingPathComponent("frames/\(key).png")) else {
                    let alert = NSAlert(); alert.messageText = "Pocket Pikachu’s artwork is missing."
                    alert.informativeText = "Keep the complete app bundle together."; alert.runModal()
                    NSApp.terminate(nil); return
                }
                images[key] = image
            }
        }
        // Pikachu's cries; a missing clip just stays silent.
        for name in ["pika","pika-pika","pikachu","thunderbolt","chaa","pika-question","pika-pi","sleepy"] {
            if let sound = NSSound(contentsOf: resources.appendingPathComponent("voice/\(name).wav"), byReference: false) { voiceClips[name] = sound }
        }
        // Optional music-mode frames with real headphones; missing files just mean no swap.
        for (row, n) in [(0, 6), (9, 8)] { for col in 0..<n where images["h\(row)-\(col)"] == nil {
            if let image = NSImage(contentsOf: resources.appendingPathComponent("frames/h\(row)-\(col).png")) { images["h\(row)-\(col)"] = image }
        } }
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 167), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        pet.owner = self; pet.frame = NSRect(x: 0, y: 0, width: 154, height: 167)
        pet.autoresizingMask = [.width, .height]
        root.addSubview(pet)
        panel.contentView = root
        // Default to the Large preset; subviews follow through autoresizing.
        panel.setContentSize(NSSize(width: 192, height: 192 * 208 / 192))
        if let index = CommandLine.arguments.firstIndex(of: "--render-pet-controls"), CommandLine.arguments.count > index+1 {
            pet.sprite = images["0-0"]
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
            }
            NSApp.terminate(nil); return
        }
        let prefs = UserDefaults.standard
        autoSleep = prefs.object(forKey: "autoSleep") as? Bool ?? true
        mischief = prefs.object(forKey: "mischief") as? Bool ?? true
        breakReminders = prefs.object(forKey: "breakReminders") as? Bool ?? true
        walkReminders = prefs.object(forKey: "walkReminders") as? Bool ?? true
        focusReminders = prefs.object(forKey: "focusReminders") as? Bool ?? true
        sounds = prefs.bool(forKey: "sounds")
        home = PetHome(rawValue: prefs.string(forKey: "home") ?? "cushion") ?? .cushion
        let start = ProcessInfo.processInfo.systemUptime
        life.lastActivity = start; life.nextBreak = start + life.breakInterval; lastChase = start
        lastMouse = NSEvent.mouseLocation
        walk.next = start + 1200; focusReminder.next = start + 1800
        buildMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = tailIcon(); status.button?.toolTip = "Pocket Pikachu"
        status.menu = menu
        // Read the saved position before defaults can overwrite it.
        var restored = false
        if let x = prefs.object(forKey: "petX") as? Double, let y = prefs.object(forKey: "petY") as? Double {
            let candidate = NSRect(x: x, y: y, width: panel.frame.width, height: panel.frame.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(candidate) }) { panel.setFrameOrigin(candidate.origin); restored = true }
        }
        if !restored { resetPosition() }
        panel.orderFrontRegardless()
        tick()
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index+1 {
            let report = "accessibilityTrusted=\(AXIsProcessTrusted())\ntypingEnabled=\(typingEnabled)\nglobalMonitor=\(globalKeys != nil)\n"
            try? report.write(toFile: CommandLine.arguments[index+1],atomically: true,encoding: .utf8)
        }
        if CommandLine.arguments.contains("--voice-tool-smoke") {
            openTerminals(); let desk = terminalDesk!; desk.openVoice(); let voice = desk.voice!
            voice.connected = true; voice.actions.state = .off
            func call(_ id: String,_ name: String,_ args: [String:Any]) { voice.handle(["toolCall":["functionCalls":[["id":id,"name":name,"args":args]]]]) }
            let initial = desk.terminals.count
            call("blocked","create_terminal",[:]); precondition(desk.terminals.count == initial)
            voice.actions.state = .on
            call("new","create_terminal",[:]); call("new","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
            call("missing","send_terminal",["terminal_id":99999,"text":"bad","submit":true]); precondition(voice.replies["missing"]?["response"] as? [String:String] != nil)
            let target = desk.terminals.last!
            var tries = 0
            Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { timer in
                tries += 1
                if target.ready {
                    timer.invalidate()
                    call("send","send_terminal",["terminal_id":target.number,"text":"printf 'VOICE_%s\\n' 'ROUTE_OK'","submit":true])
                    DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                        target.web.evaluateJavaScript("Array.from({length:term.buffer.active.length},(_,i)=>term.buffer.active.getLine(i).translateToString()).join('\\n')") { result,_ in
                            guard (result as? String)?.contains("VOICE_ROUTE_OK") == true else { print("FAIL voice terminal input"); voice.stop(); desk.shutdown(); exit(1) }
                            call("interrupt","interrupt_terminal",["terminal_id":target.number,"key":"ctrl_c"])
                            voice.handle(["toolCallCancellation":["ids":["cancelled"]]])
                            call("cancelled","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
                            voice.actions.state = .off; call("hangup", "hang_up", [:]); precondition(!voice.connected); call("after-stop","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
                            print("PASS: voice tool toggle, stable target IDs, duplicate suppression, shell delivery, cancellation, and stop gate")
                            desk.voiceContext { text in
                                precondition(text.contains("VOICE_ROUTE_OK") && text.contains("Tab \(target.number)"))
                                print("PASS: bounded rendered terminal context and hang-up with controls disabled")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                } else if tries > 30 { timer.invalidate(); desk.shutdown(); exit(1) }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--terminal-smoke"), CommandLine.arguments.count > index+1 {
            openTerminals()
            let destination = CommandLine.arguments[index+1]
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { [weak self] timer in
                attempts += 1
                guard let terminal = self?.terminalDesk?.selected else { return }
                if terminal.ready {
                    timer.invalidate()
                    terminal.send(["kind":"input","data":Data("printf 'PIKA_%s\\n' 'TERMINAL_OK'\n".utf8).base64EncodedString()])
                    DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                        terminal.web.evaluateJavaScript("Array.from({length:term.buffer.active.length},(_,i)=>term.buffer.active.getLine(i).translateToString()).join('\\n')") { value,error in
                            guard let text = value as? String,text.contains("PIKA_TERMINAL_OK") else { print("FAIL terminal renderer: \(String(describing: error))"); self?.terminalDesk?.shutdown(); exit(1) }
                            terminal.web.takeSnapshot(with: nil) { image,error in
                                if let image = image,let tiff = image.tiffRepresentation,let rep = NSBitmapImageRep(data: tiff),let png = rep.representation(using: .png,properties: [:]) { try? png.write(to: URL(fileURLWithPath: destination)) }
                                print("PASS: embedded terminal renders real shell output")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                } else if attempts > 30 { print("FAIL: terminal did not load"); timer.invalidate(); NSApp.terminate(nil) }
            }
            return
        }
        if CommandLine.arguments.contains("--play-smoke") {
            let home = panel.frame.origin
            let width = (NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main)!.visibleFrame.width
            func checkRun(_ a: NSPoint,_ b: NSPoint) { let d = hypot(b.x-a.x,b.y-a.y); precondition(d >= width*0.2-1 && d <= width*0.3+1,"run length \(Int(d)) px outside 20-30% of \(Int(width)) px") }
            playBall(); precondition(ballGame != nil && ballPanel?.isVisible == true); checkRun(home,ballGame!.to)
            var moved = false, runs = 1, last = ballGame!.to, reach = 0.0
            Timer.scheduledTimer(withTimeInterval: 0.05,repeats: true) { [self] timer in
                if let game = ballGame {
                    if panel.frame.origin != home { moved = true }
                    reach = max(reach,hypot(panel.frame.minX-home.x,panel.frame.minY-home.y))
                    if game.to != last && !game.returning { checkRun(last,game.to); runs += 1; last = game.to }
                    return
                }
                timer.invalidate()
                precondition(moved && panel.frame.origin == home && ballPanel?.isVisible == false && (5...7).contains(runs), "ball game moved=\(moved) runs=\(runs) home=\(panel.frame.origin == home)")
                let area = (NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main)!.frame
                panel.setFrameOrigin(NSPoint(x: area.minX+10,y: panel.frame.minY)); tick(); precondition(pet.mirrored)
                panel.setFrameOrigin(NSPoint(x: area.maxX-panel.frame.width-10,y: panel.frame.minY)); tick(); precondition(!pet.mirrored)
                panel.setFrameOrigin(home)
                dance(); tick(); precondition(pet.dancing && pet.sprite === images["6-0"])
                precondition(voiceClips.count == 8); say("pika"); precondition(voiceSound?.isPlaying == true); voiceSound?.stop()
                let t0 = ProcessInfo.processInfo.systemUptime
                thunderbolt(); print("thunderbolt prepared in \(Int((ProcessInfo.processInfo.systemUptime-t0)*1000)) ms"); tick(); precondition(actionRow == 8 && pet.sprite === images["8-0"] && pet.caption == "Pika… CHUUU!" && thunderPanel?.isVisible == true && ((thunderPanel?.contentView as? ThunderView)?.bolts.count ?? 0) >= 1)
                for _ in 0..<4 { (thunderPanel?.contentView as? ThunderView)?.warm() }; precondition((thunderPanel?.contentView as? ThunderView)?.bolts.count == 3)
                if let view = thunderPanel?.contentView as? ThunderView { precondition(hypot(view.target.x-view.origin.x,view.target.y-view.origin.y) > panel.frame.width) }
                remindFocus(); tick(); precondition(pet.caption == "Hey. Time to focus." && pet.sprite === images["8-0"])
                precondition(bubblePanel?.isVisible == true && (bubblePanel?.contentView as? SpeechBubbleView)?.text == "Hey. Time to focus." && (bubblePanel?.frame.width ?? 0) > panel.frame.width*0.6)
                precondition(panel.frame.width == 384 || panel.frame.width == 192)
                huge(); precondition(panel.frame.width == 384 && pet.frame.width == 384)
                showBall(); moveBall(BallGame(origin: panel.frame.origin,start: 0,runs: 1),at: 0); precondition(ballPanel?.frame.width == 84 && ballPanel?.frame.height == 76); ballPanel?.orderOut(nil)
                large(); precondition(pet.frame.width == 192)
                previewTyping(); tick(); precondition((0..<8).contains { pet.sprite === images["9-\($0)"] || pet.sprite === images["h9-\($0)"] } && pet.typingPhase == nil)
                toggleMusic(); tick(); precondition((0..<8).contains { pet.sprite === images["h9-\($0)"] }); typing.until = 0; tick(); precondition((0..<6).contains { pet.sprite === images["h0-\($0)"] }); toggleMusic()
                print("PASS: ball game ran \(runs) runs of 20-30% of \(Int(width)) px, roamed up to \(Int(reach)) px from home, and came home; dance frames and bounce; focus reminder caption")
                NSApp.terminate(nil)
            }
            return
        }
        if typingEnabled { requestTypingAccess() }
    }
    func buildMenu() {
        add("Open terminals", #selector(openTerminals)); add("Voice assistant…", #selector(voiceSettings))
        terminalItem = add("Terminal notifications", #selector(toggleTerminal))
        let history = NSMenuItem(title: "Recent terminal activity",action: nil,keyEquivalent: "")
        history.submenu = terminalHistory; menu.addItem(history)
        let title = NSMenuItem(title: "Pocket Pikachu", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(.separator())
        add("Wave", #selector(wave)); add("Jump", #selector(jump)); add("Thinking", #selector(think))
        add("Pet Pikachu", #selector(petNow)); add("Give a fish treat", #selector(giveTreat))
        add("Nap now", #selector(nap)); add("Stretch now", #selector(stretch))
        add("Play with cursor", #selector(playCursor))
        add("Fun dance", #selector(dance)); add("Play ball", #selector(playBall)); add("Thunderbolt", #selector(thunderbolt))
        menu.addItem(.separator())
        focusItem = add("Focus timer: off", #selector(startFocus))
        add("Start 5-minute focus", #selector(shortFocus))
        add("Try a 10-second focus", #selector(testFocus))
        add("Cancel focus", #selector(cancelFocus))
        menu.addItem(.separator())
        sleepItem = add("Auto nap after 3 minutes", #selector(toggleSleep))
        mischiefItem = add("Occasional cursor play", #selector(toggleMischief))
        walkItem = add("Walk reminders every 20 minutes", #selector(toggleWalk))
        add("Preview walk reminder", #selector(remindWalk))
        focusReminderItem = add("Focus reminders every 30 minutes", #selector(toggleFocusReminders))
        add("Preview focus reminder", #selector(remindFocus))
        breakItem = add("Stretch reminders every 30 minutes", #selector(toggleBreaks))
        musicItem = add("Headphones — manual music mode", #selector(toggleMusic))
        audioItem = add("Auto headphones when audio output is active", #selector(toggleAudio))
        voiceItem = add("Pikachu voice", #selector(toggleVoice))
        soundItem = add("Sounds and purring", #selector(toggleSounds))
        for (name, style) in [("No home",PetHome.none),("Cushion",PetHome.cushion),("Cardboard box",PetHome.box)] {
            let item = add(name,#selector(selectHome(_:))); item.representedObject = style.rawValue; homeItems[style] = item
        }
        menu.addItem(.separator())
        pauseItem = add("Pause cursor following", #selector(togglePause))
        typingItem = add("Typing reactions", #selector(toggleTyping))
        typingStatus = NSMenuItem(title: "Typing detection: checking…",action: nil,keyEquivalent: ""); menu.addItem(typingStatus)
        add("Open keyboard permission settings…", #selector(openTypingSettings))
        permissionItem = add("Allow typing detection…", #selector(requestTypingAccess))
        add("Preview typing", #selector(previewTyping))
        add("Reset position", #selector(resetPosition))
        add("Small", #selector(small)); add("Large", #selector(large)); add("Extra large", #selector(extraLarge)); add("Huge", #selector(huge))
        menu.addItem(.separator()); add("Quit Pocket Pikachu", #selector(quit), "q")
    }
    @discardableResult func add(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    func play(_ row: Int, duration: Double) {
        actionRow = row; actionStart = ProcessInfo.processInfo.systemUptime; actionUntil = actionStart + duration
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now >= terminalCheck { terminalCheck = now+1; checkTerminals() }
        if now >= permissionCheck { permissionCheck = now + 1; refreshTypingMonitor() }
        if now >= audioCheck { audioCheck = now+2; audioActive = autoAudio && now > ownAudioUntil && outputActive() }
        let point = NSEvent.mouseLocation
        let distance = hypot(point.x-lastMouse.x,point.y-lastMouse.y)
        if distance > 0.5 { life.activity(at: now) }
        let face = NSRect(x: panel.frame.minX+panel.frame.width*0.2,y: panel.frame.minY+pet.frame.minY+pet.frame.height*0.55,width: panel.frame.width*0.6,height: pet.frame.height*0.35)
        if face.contains(point) && NSEvent.pressedMouseButtons == 0 && distance > 0.5 {
            if now-pettingWindow > 1.5 { pettingWindow = now; pettingTravel = 0 }
            pettingTravel += min(distance,30)
            if pettingTravel > 55 { petNow(); pettingTravel = 0 }
        } else if !face.contains(point) { pettingTravel = 0 }
        lastMouse = point
        if life.completeFocus(at: now) { announce("Focus finished. Nice work!",for: 6); play(4,duration: 1.5); playSound(purr: false); say("pikachu") }
        if walk.due(at: now,enabled: walkReminders) { remindWalk() }
        if focusReminder.due(at: now,enabled: focusReminders) && life.focusEnd == nil { remindFocus() }
        let sleeping = life.sleeping(at: now,autoSleep: autoSleep && !musicMode && !audioActive)
        if life.breakDue(at: now,enabled: breakReminders,sleeping: sleeping) { stretch() }
        if let end = life.focusEnd {
            let seconds = max(0,Int(ceil(end-now)))
            focusItem.title = String(format: "Focus %02d:%02d — click to cancel",seconds/60,seconds%60)
        } else { focusItem.title = "Start 25-minute focus" }
        if now > treatExpires { treatPanel?.orderOut(nil) }
        if let trip = excursion {
            if now >= trip.start+trip.duration {
                panel.setFrameOrigin(trip.origin); excursion = nil
                if trip.kind == .treat { treatPanel?.orderOut(nil); announce("Nom. Acceptable.",for: 2.5); play(0,duration: 1); playSound(purr: true); say("chaa") }
                else { announce("I meant to miss.",for: 2.5); play(5,duration: 1.2); say("sleepy") }
            } else {
                panel.setFrameOrigin(trip.position(at: now))
                if trip.kind == .treat && now-trip.start > trip.duration*0.45 { treatPanel?.orderOut(nil) }
            }
        }
        if let sky = thunderPanel, sky.isVisible {
            let phase = (now-thunderStart)/thunderDuration
            if phase >= 1 { sky.orderOut(nil); if ballGame == nil && excursion == nil { panel.setFrameOrigin(thunderBase) } }
            else {
                (sky.contentView as? ThunderView)?.warm(); (sky.contentView as? ThunderView)?.phase = phase
                let shake = ThunderView.discharge(phase)
                if !thunderRumbled && phase >= ThunderView.firstStroke { thunderRumbled = true; rumble() }
                if ballGame == nil && excursion == nil && NSEvent.pressedMouseButtons == 0 { panel.setFrameOrigin(NSPoint(x: thunderBase.x+Double.random(in: -3...3)*shake, y: thunderBase.y+Double.random(in: -2...2)*shake)) }
            }
        }
        if var game = ballGame {
            if !game.finished(at: now) { panel.setFrameOrigin(game.position(at: now)); moveBall(game,at: now) }
            else if game.returning { panel.setFrameOrigin(game.origin); ballGame = nil; ballPanel?.orderOut(nil); announce("Enough. I win.",for: 2.5); play(0,duration: 1); playSound(purr: true); say("pika-pika") }
            else if game.runsLeft > 0 { game.run(to: ballTarget(from: game.to,screenOf: game.origin),at: now); ballGame = game }
            else { game.goHome(at: now); ballGame = game }
        }
        if mischief && !sleeping && life.focusEnd == nil && !typing.active(at: now) && excursion == nil && ballGame == nil && now > actionUntil && now > pettingUntil && now-lastChase > 75 && distance > 1 && NSEvent.pressedMouseButtons == 0 {
            let range = hypot(point.x-panel.frame.midX,point.y-panel.frame.midY)
            if range > 65 && range < 240 { startChase() }
        }
        pet.typingPhase = nil
        pet.snoozing = false; pet.happy = false; pet.stretching = false; pet.clock = now
        pet.home = home
        pet.headphones = musicMode || audioActive
        let goal = home == .box && (sleeping || now < pettingUntil) ? 1.0 : 0.0
        pet.homeDepth += (goal-pet.homeDepth)*0.12
        pet.caption = now < noticeUntil ? notice : nil
        var row = 0, col = Int(now / 0.2) % 6, dancing = false
        if let game = ballGame {
            if game.waiting(at: now) { row = 4; col = min(4,Int((now-game.start+game.pause)/0.07)) }
            else { row = game.to.x < game.from.x ? 2 : 1; col = Int(now/0.1)%8 }
        } else if let trip = excursion {
            if trip.kind == .treat { row = 4; col = min(4,Int((now-trip.start)/trip.duration*5)) }
            else { row = trip.target.x < trip.origin.x ? 2 : 1; if now-trip.start > trip.duration*0.6 { row = row == 1 ? 2 : 1 }; col = Int(now/0.1)%8 }
        } else if now < pettingUntil {
            row = 0; col = 1; pet.happy = true
        } else if now < stretchUntil {
            row = 7; col = 3; pet.stretching = true
        } else if now < actionUntil {
            if actionRow == 6 { (row, col) = danceFrames[Int((now - actionStart) / 0.14) % danceFrames.count]; dancing = true }
            else if actionRow == 8, thunderPanel?.isVisible == true {
                let phase = (now-thunderStart)/thunderDuration, power = ThunderView.discharge(phase)
                row = 8; col = phase < 0.11 ? 0 : phase < 0.242 ? 1 : phase < 0.47 ? (power > 0.5 ? 3 : 2) : phase < ThunderView.quiet ? (power > 0.3 ? 3 : 4) : phase < 0.82 ? 4 : 5
            }
            else { row = actionRow; col = Int((now - actionStart) / 0.14) % counts[row] }
        } else if typing.active(at: now) {
            let cadence = typing.cadence(at: now)
            row = 9; col = Int(now / cadence) % counts[9]
            if cadence < 0.1 { pet.caption = "Turbo paws" }
        } else if sleeping {
            row = 0; col = 1; pet.snoozing = true
            if let end = life.focusEnd { pet.caption = "Focus · \(max(0,Int(ceil((end-now)/60)))) min" }
        }
        if now < terminalUntil { pet.caption = terminalMessage }
        if now < walkUntil { pet.caption = "Stand up & take a short walk" }
        if now < focusUntil { pet.caption = "Hey. Time to focus." }
        pet.dancing = dancing
        pet.gazeDirection = nil
        let screenMidX = (NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main)?.frame.midX ?? panel.frame.midX
        pet.mirrored = row != 1 && row != 2 && panel.frame.midX < screenMidX   // running rows already carry their direction
        // Music mode swaps in the headphone render when one exists for this frame.
        pet.sprite = (pet.headphones ? images["h\(row)-\(col)"] : nil) ?? images["\(row)-\(col)"]
        updateBubble(pet.caption, at: now)
    }
    @objc func toggleTerminal() {
        terminalEnabled.toggle(); UserDefaults.standard.set(terminalEnabled,forKey: "terminalEnabled")
        terminalUntil = 0; terminalSince = Date().timeIntervalSince1970; syncOptions()
    }
    func checkTerminals() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketPikachu/events")
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: [.fileSizeKey,.isSymbolicLinkKey]) else { return }
        var events: [TerminalEvent] = []
        let wall = Date().timeIntervalSince1970
        for file in files.prefix(256) where file.pathExtension == "json" {
            guard let info = try? file.resourceValues(forKeys: [.fileSizeKey,.isSymbolicLinkKey]), info.isSymbolicLink != true,
                  (info.fileSize ?? 9999) <= 1024,
                  let data = try? Data(contentsOf: file), let event = try? JSONDecoder().decode(TerminalEvent.self,from: data),
                  event.valid, event.time >= terminalSince, event.time <= wall+5, wall-event.time < 120 else { continue }
            events.append(event)
        }
        terminalSince = floor(wall)-1
        guard terminalEnabled else { return }
        for event in events.sorted(by: { $0.time < $1.time }) {
            // One event per session per second; ignore repeated polling of the same file.
            let identity = "\(event.session)-\(event.time)-\(event.kind)-\(event.code)"
            guard !seenTerminalEvents.contains(identity) else { continue }
            seenTerminalEvents.append(identity); if seenTerminalEvents.count > 256 { seenTerminalEvents.removeFirst() }
            terminalMessage = event.message; terminalUntil = ProcessInfo.processInfo.systemUptime+12
            let item = NSMenuItem(title: event.message,action: nil,keyEquivalent: "")
            terminalHistory.insertItem(item,at: 0)
            if terminalHistory.items.count > 12 { terminalHistory.removeItem(at: 12) }
            if event.kind == "attention" { playSound(purr: false); say("pika-question") }
        }
    }
    var seenTerminalEvents: [String] = []
    @objc func voiceSettings() { if terminalDesk == nil { terminalDesk = TerminalDesk() }; terminalDesk?.openVoice() }
    @objc func openTerminals() {
        if terminalDesk == nil { terminalDesk = TerminalDesk() }
        terminalDesk?.show(above: panel.frame)
    }
    func savePosition() { UserDefaults.standard.set(panel.frame.minX, forKey: "petX"); UserDefaults.standard.set(panel.frame.minY, forKey: "petY") }
    func announce(_ text: String, for duration: Double = 3) { notice = text; noticeUntil = ProcessInfo.processInfo.systemUptime+duration }
    func beginDrag() {
        excursion = nil; ballGame = nil; ballPanel?.orderOut(nil); life.activity(at: ProcessInfo.processInfo.systemUptime)
        pettingUntil = 0; stretchUntil = 0
    }
    @objc func petNow() {
        let now = ProcessInfo.processInfo.systemUptime
        pettingUntil = now+2.2; life.activity(at: now)
        if now-lastPetSound > 3 { lastPetSound = now; playSound(purr: true); say("chaa") }
    }
    @objc func nap() { life.forcedNap = true; actionUntil = 0; pettingUntil = 0; stretchUntil = 0; typing.until = 0; announce("Nap time",for: 2); say("sleepy") }
    @objc func stretch() {
        let now = ProcessInfo.processInfo.systemUptime
        stretchUntil = now+3; life.nextBreak = now+life.breakInterval
        announce("Time for a little stretch",for: 5); say("sleepy")
    }
    func startTimer(_ seconds: Double) {
        beginDrag(); life.focusEnd = ProcessInfo.processInfo.systemUptime+seconds
        actionUntil = 0; typing.until = 0; treatPanel?.orderOut(nil)
        announce("Focus together",for: 2)
    }
    @objc func startFocus() { if life.focusEnd != nil { cancelFocus() } else { startTimer(25*60) } }
    @objc func shortFocus() { startTimer(5*60) }
    @objc func testFocus() { startTimer(10) }
    @objc func cancelFocus() { life.focusEnd = nil; life.activity(at: ProcessInfo.processInfo.systemUptime); announce("Focus cancelled") }
    @objc func remindWalk() {
        walkUntil = ProcessInfo.processInfo.systemUptime + 30
        play(3,duration: 3); playSound(purr: false); say("pika-pi")
    }
    @objc func remindFocus() {
        focusUntil = ProcessInfo.processInfo.systemUptime + 30
        play(8,duration: 3); playSound(purr: false); say("pikachu")
    }
    @objc func toggleFocusReminders() {
        focusReminders.toggle(); focusReminder.next = ProcessInfo.processInfo.systemUptime + 1800
        if !focusReminders { focusUntil = 0 }
        UserDefaults.standard.set(focusReminders,forKey: "focusReminders"); syncOptions()
    }
    @objc func toggleWalk() {
        walkReminders.toggle(); walk.next = ProcessInfo.processInfo.systemUptime + 1200
        if !walkReminders { walkUntil = 0 }
        UserDefaults.standard.set(walkReminders,forKey: "walkReminders"); syncOptions()
    }
    @objc func toggleSleep() { autoSleep.toggle(); UserDefaults.standard.set(autoSleep,forKey: "autoSleep"); syncOptions() }
    @objc func toggleMischief() { mischief.toggle(); UserDefaults.standard.set(mischief,forKey: "mischief"); syncOptions() }
    @objc func toggleBreaks() { breakReminders.toggle(); life.nextBreak = ProcessInfo.processInfo.systemUptime+life.breakInterval; UserDefaults.standard.set(breakReminders,forKey: "breakReminders"); syncOptions() }
    @objc func toggleVoice() { voiceEnabled.toggle(); UserDefaults.standard.set(voiceEnabled,forKey: "voiceEnabled"); if !voiceEnabled { voiceSound?.stop() }; syncOptions() }
    // One cry at a time; `force` lets Thunderbolt cut in.
    func say(_ name: String, force: Bool = false) {
        guard voiceEnabled, let clip = voiceClips[name] else { return }
        if let current = voiceSound, current.isPlaying { if force { current.stop() } else { return } }
        clip.stop(); clip.volume = 0.7; clip.play(); voiceSound = clip; ownAudio(clip)
    }
    func ownAudio(_ sound: NSSound?) { ownAudioUntil = max(ownAudioUntil, ProcessInfo.processInfo.systemUptime + (sound?.duration ?? 1) + 3) }
    @objc func toggleSounds() { sounds.toggle(); UserDefaults.standard.set(sounds,forKey: "sounds"); if !sounds { sound?.stop() }; syncOptions() }
    @objc func selectHome(_ sender: NSMenuItem) {
        home = PetHome(rawValue: sender.representedObject as? String ?? "none") ?? .none
        UserDefaults.standard.set(home.rawValue,forKey: "home"); syncOptions()
        if home == .box { petNow(); announce("My box now.",for: 2) }
    }
    @objc func toggleMusic() { musicMode.toggle(); syncOptions() }
    @objc func toggleAudio() { autoAudio.toggle(); UserDefaults.standard.set(autoAudio,forKey: "autoAudio"); audioCheck = 0; if !autoAudio { audioActive = false }; syncOptions() }
    func outputActive() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,mScope: kAudioObjectPropertyScopeGlobal,mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device) == noErr, device != 0 else { return false }
        var running: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,mScope: kAudioObjectPropertyScopeGlobal,mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device,&address,0,nil,&size,&running) == noErr && running != 0
    }
    func syncOptions() {
        terminalItem?.state = terminalEnabled ? .on : .off
        walkItem?.state = walkReminders ? .on : .off
        focusReminderItem?.state = focusReminders ? .on : .off
        musicItem?.state = musicMode ? .on : .off; audioItem?.state = autoAudio ? .on : .off
        sleepItem?.state = autoSleep ? .on : .off; mischiefItem?.state = mischief ? .on : .off
        breakItem?.state = breakReminders ? .on : .off; soundItem?.state = sounds ? .on : .off; voiceItem?.state = voiceEnabled ? .on : .off
        for (style,item) in homeItems { item.state = style == home ? .on : .off }
    }
    func clampedOrigin(_ point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return point }
        return NSPoint(x: min(max(point.x,f.minX),f.maxX-panel.frame.width), y: min(max(point.y,f.minY),f.maxY-panel.frame.height))
    }
    @objc func playCursor() { startChase() }
    func startChase() {
        guard excursion == nil, ballGame == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        life.activity(at: now); lastChase = now; say("pika-question")
        let cursor = NSEvent.mouseLocation
        let dx = cursor.x-panel.frame.midX, dy = cursor.y-panel.frame.midY
        let distance = max(1,hypot(dx,dy)), amount = min(70,distance*0.5)
        let target = clampedOrigin(NSPoint(x: panel.frame.minX+dx/distance*amount,y: panel.frame.minY+dy/distance*amount))
        excursion = Excursion(kind: .chase,origin: panel.frame.origin,target: target,start: now,duration: 1.7)
    }
    @objc func giveTreat() {
        if treatPanel == nil {
            let window = PetPanel(contentRect: NSRect(x: 0,y: 0,width: 42,height: 38),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating
            window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            let view = TreatView(frame: NSRect(x: 0,y: 0,width: 42,height: 38)); view.owner = self; window.contentView = view
            window.isReleasedWhenClosed = false; treatPanel = window
        }
        guard let window = treatPanel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? panel.frame
        let x = panel.frame.minX-52 >= f.minX ? panel.frame.minX-52 : min(f.maxX-42,panel.frame.maxX+10)
        window.setFrameOrigin(NSPoint(x: x,y: max(f.minY,panel.frame.minY+10)))
        window.orderFrontRegardless(); treatExpires = ProcessInfo.processInfo.systemUptime+20
        announce("Click the fish",for: 3)
    }
    // Speech bubble above the head: pops in on new text, bobs while shown, fades for 0.25 s after the text goes away.
    func updateBubble(_ text: String?, at now: Double) {
        if let text = text, text != bubbleText { bubbleText = text; bubbleSince = now; bubbleFadeStart = 0 }
        if text == nil, bubbleText != nil, bubbleFadeStart == 0 { bubbleFadeStart = now }
        guard let shown = bubbleText else { bubblePanel?.orderOut(nil); return }
        let fade = bubbleFadeStart == 0 ? 1.0 : max(0, 1 - (now-bubbleFadeStart)/0.25)
        if fade == 0 { bubbleText = nil; bubbleFadeStart = 0; bubblePanel?.orderOut(nil); return }
        if bubblePanel == nil {
            let window = PetPanel(contentRect: .zero,styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating; window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isReleasedWhenClosed = false
            window.contentView = SpeechBubbleView(frame: .zero); bubblePanel = window
        }
        guard let window = bubblePanel, let view = window.contentView as? SpeechBubbleView else { return }
        let k = panel.frame.width/192, age = now-bubbleSince
        let size = SpeechBubbleView.size(for: shown, k: k, maxWidth: panel.frame.width*1.6)
        // Tail tip sits just above the head, toward the side the face is on.
        let tipX = panel.frame.midX + (pet.mirrored ? 0.08 : -0.08)*panel.frame.width, tipY = panel.frame.maxY - 0.10*panel.frame.height
        let screen = (NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var x = tipX - size.width/2; x = min(max(screen.minX, x), screen.maxX-size.width)
        let y = min(tipY, screen.maxY-size.height)
        view.text = shown; view.k = k; view.fade = fade; view.tailX = (tipX-x)/size.width; view.age = age
        window.setFrame(NSRect(x: x,y: y,width: size.width,height: size.height),display: false); view.frame = NSRect(origin: .zero,size: size); view.needsDisplay = true
        if !window.isVisible { window.order(.above,relativeTo: panel.windowNumber) }
    }
    @objc func thunderbolt() { play(8,duration: thunderDuration); announce("Pika… CHUUU!",for: thunderDuration); say("thunderbolt",force: true); strikeScreen() }
    // Full-screen click-through lightning on the screen Pikachu is on, aimed at its head.
    func strikeScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(panel.frame.center) }) ?? NSScreen.main else { return }
        if thunderPanel == nil {
            let sky = PetPanel(contentRect: screen.frame,styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            sky.isOpaque = false; sky.backgroundColor = .clear; sky.hasShadow = false; sky.level = .floating; sky.ignoresMouseEvents = true
            sky.hidesOnDeactivate = false; sky.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; sky.isReleasedWhenClosed = false
            sky.contentView = ThunderView(frame: NSRect(origin: .zero,size: screen.frame.size)); thunderPanel = sky
        }
        guard let sky = thunderPanel, let view = sky.contentView as? ThunderView else { return }
        sky.setFrame(screen.frame,display: false); view.frame = NSRect(origin: .zero,size: screen.frame.size)
        view.duration = thunderDuration
        let head = NSPoint(x: panel.frame.midX-screen.frame.minX,y: panel.frame.maxY-panel.frame.height*0.16-screen.frame.minY)
        let mouse = NSEvent.mouseLocation, area = screen.visibleFrame
        var aim = NSPoint(x: mouse.x-screen.frame.minX,y: mouse.y-screen.frame.minY)
        if !area.contains(mouse) || hypot(mouse.x-panel.frame.midX,mouse.y-panel.frame.midY) < panel.frame.width*1.3 {
            // Strike open ground on the far side of the screen from Pikachu.
            let left = panel.frame.midX > screen.frame.midX
            aim = NSPoint(x: (left ? Double.random(in: 0.12...0.45) : Double.random(in: 0.55...0.88))*screen.frame.width, y: area.minY-screen.frame.minY + Double.random(in: 40...max(41, area.height*0.3)))
        }
        view.prepare(origin: head,target: aim)
        thunderStart = ProcessInfo.processInfo.systemUptime; view.phase = 0; thunderBase = panel.frame.origin; thunderRumbled = false
        sky.order(.above,relativeTo: panel.windowNumber)
    }
    // Thunder: filtered noise burst with a sub-bass roll, decaying over two seconds.
    func rumble() {
        guard voiceEnabled else { return }
        let rate = 22050, length = rate*2
        var pcm = Data(), brown = 0.0, low = 0.0
        for i in 0..<length {
            let t = Double(i)/Double(rate)
            brown = (brown + (Double.random(in: -1...1))*0.08).clamped(to: -1...1); low += (brown-low)*0.08
            // Sharp crack first, then the deep roll with a second peak under the next strikes.
            let crack = t < 0.16 ? Double.random(in: -1...1) * exp(-t*28) : 0
            let envelope = min(1, t/0.03) * exp(-t*1.4) * (0.7+0.3*sin(t*17)) + (t > 0.3 && t < 0.75 ? 0.7 : 0) + (t > 0.9 && t < 1.1 ? 0.4 : 0)
            let value = (low*3.6 + 0.4*sin(2 * .pi*40*t)) * envelope + crack*0.9
            var sample = Int16(max(-1, min(1, value))*9000).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ s: String) { data.append(s.data(using: .ascii)!) }
        func number<T: FixedWidthInteger>(_ n: T) { var le = n.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(pcm.count+36)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(rate)); number(UInt32(rate*2)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(pcm.count)); data.append(pcm)
        rumbleSound?.stop(); rumbleSound = NSSound(data: data); rumbleSound?.volume = 0.65; rumbleSound?.play(); ownAudio(rumbleSound)
    }
    @objc func dance() { let length = Double(danceFrames.count)*0.14; play(6,duration: length); announce("Dance break",for: length); playSound(purr: true); say("pika-pika") }
    @objc func playBall() {
        guard excursion == nil, ballGame == nil else { return }
        beginDrag(); let now = ProcessInfo.processInfo.systemUptime; lastChase = now
        var game = BallGame(origin: panel.frame.origin,start: now,runs: Int.random(in: 5...7))
        game.run(to: ballTarget(from: game.origin,screenOf: game.origin),at: now); ballGame = game; showBall(); moveBall(game,at: now)
        announce("Ball!",for: 2); say("pika-question")
    }
    func ballTarget(from current: NSPoint, screenOf origin: NSPoint) -> NSPoint {
        // Each run covers 20-30% of the screen width at a random angle, like a screensaver bounce.
        let center = NSPoint(x: origin.x+panel.frame.width/2,y: origin.y+panel.frame.height/2)
        guard let f = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame else { return origin }
        let area = NSRect(x: f.minX,y: f.minY,width: max(0,f.width-panel.frame.width),height: max(0,f.height-panel.frame.height))
        for _ in 0..<40 {
            let angle = Double.random(in: 0..<2 * .pi), reach = f.width*Double.random(in: 0.2...0.3)
            let dx = cos(angle)*reach, dy = sin(angle)*reach
            let candidate = NSPoint(x: current.x+dx,y: current.y+dy)
            if area.contains(candidate) { return candidate }
        }
        return NSPoint(x: area.midX,y: area.midY)
    }
    func showBall() {
        if ballPanel == nil {
            let window = PetPanel(contentRect: NSRect(x: 0,y: 0,width: 42,height: 38),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating
            window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            window.contentView = BallView(frame: NSRect(x: 0,y: 0,width: 42,height: 38)); window.isReleasedWhenClosed = false; ballPanel = window
        }
        ballPanel?.order(.above,relativeTo: panel.windowNumber)
    }
    // Ball coordinates are pet origins; the ball rests in front of the paws and scales with the pet (42x38 at width 192).
    func moveBall(_ game: BallGame, at now: Double) {
        let p = game.ballPosition(at: now), k = panel.frame.width/192
        ballPanel?.setFrame(NSRect(x: p.x+panel.frame.width/2-21*k,y: p.y+pet.frame.minY-6*k,width: 42*k,height: 38*k),display: true)
        (ballPanel?.contentView as? BallView)?.roll = game.ballRoll(at: now)/k
    }
    func eatTreat() {
        guard let treat = treatPanel, excursion == nil, ballGame == nil else { return }
        beginDrag(); let now = ProcessInfo.processInfo.systemUptime
        let target = clampedOrigin(NSPoint(x: treat.frame.midX-panel.frame.width/2,y: panel.frame.minY))
        excursion = Excursion(kind: .treat,origin: panel.frame.origin,target: target,start: now,duration: 1.5)
        treatExpires = now+2
    }
    func playSound(purr: Bool) {
        guard sounds else { return }
        let rate = 22050, length = Int(Double(rate)*(purr ? 0.8 : 0.35))
        var pcm = Data()
        for i in 0..<length {
            let t = Double(i)/Double(rate), fade = sin(.pi*Double(i)/Double(length))
            let base = purr ? (sin(2 * .pi * 95*t)+0.25*sin(2 * .pi * 190*t))*(0.55+0.45*sin(2 * .pi * 25*t)) : sin(2 * .pi * 660*t)
            var value = Int16(base*fade*2400).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ s: String) { data.append(s.data(using: .ascii)!) }
        func number<T: FixedWidthInteger>(_ n: T) { var le = n.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(pcm.count+36)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(rate)); number(UInt32(rate*2)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(pcm.count)); data.append(pcm)
        sound?.stop(); sound = NSSound(data: data); sound?.volume = 0.35; sound?.play(); ownAudio(sound)
    }
    func removeKeyMonitors() {
        if let monitor = globalKeys { NSEvent.removeMonitor(monitor) }; globalKeys = nil
        if let monitor = localKeys { NSEvent.removeMonitor(monitor) }; localKeys = nil
    }
    func refreshTypingMonitor() {
        let allowed = AXIsProcessTrusted()
        syncOptions()
        typingItem?.state = typingEnabled ? .on : .off
        permissionItem?.isHidden = allowed || !typingEnabled
        typingStatus?.title = !typingEnabled ? "Typing detection: off" : !allowed ? "Typing detection: permission needed" : lastKeyActivity > 0 ? "Typing detection: receiving keys" : "Typing detection: waiting for keys"
        guard typingEnabled && allowed else { removeKeyMonitors(); return }
        if globalKeys == nil {
            globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                let now = ProcessInfo.processInfo.systemUptime
                self?.receiveTyping(at: now)
            }
        }
        if localKeys == nil {
            localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let now = ProcessInfo.processInfo.systemUptime
                self?.receiveTyping(at: now)
                return event
            }
        }
    }
    func receiveTyping(at now: Double) {
        typing.pulse(at: now); life.activity(at: now); lastKeyActivity = now
        actionUntil = 0; pettingUntil = 0; stretchUntil = 0
    }
    @objc func openTypingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func requestTypingAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshTypingMonitor()
    }
    @objc func toggleTyping() {
        typingEnabled.toggle(); UserDefaults.standard.set(typingEnabled, forKey: "typingEnabled")
        if typingEnabled { requestTypingAccess() } else { typing.until = 0; removeKeyMonitors() }
        refreshTypingMonitor()
    }
    @objc func previewTyping() { let now = ProcessInfo.processInfo.systemUptime; receiveTyping(at: now); typing.until = now + 3; lastKeyActivity = 0 }
    @objc func resetPosition() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.minY + 24)); savePosition()
    }
    @objc func screenChanged() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) { resetPosition() }
    }
    func resize(_ width: Double) {
        panel.setContentSize(NSSize(width: width, height: width * 208 / 192)); screenChanged()
    }
    @objc func small() { resize(115) }
    @objc func large() { resize(192) }
    @objc func extraLarge() { resize(288) }
    @objc func huge() { resize(384) }
    @objc func wave() { play(3, duration: 1.0); say("pika") }
    @objc func jump() { play(4, duration: 0.85); say("pika-pika") }
    @objc func think() { play(7, duration: 2.0) }
    @objc func togglePause() { paused.toggle(); pauseItem.title = paused ? "Resume cursor following" : "Pause cursor following" }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminalDesk?.shutdown(); timer?.invalidate(); removeKeyMonitors(); sound?.stop(); voiceSound?.stop(); rumbleSound?.stop()
        if thunderPanel?.isVisible == true && ballGame == nil && excursion == nil { panel.setFrameOrigin(thunderBase) }
        if let trip = excursion { panel.setFrameOrigin(trip.origin) }
        if let game = ballGame { panel.setFrameOrigin(game.origin) }
        savePosition()
    }
}

extension NSRect { var center: NSPoint { NSPoint(x: midX,y: midY) } }
extension Double { func clamped(to r: ClosedRange<Double>) -> Double { min(max(self, r.lowerBound), r.upperBound) } }

if CommandLine.arguments.contains("--self-test") {
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"claude","submit":true]) != nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":true,"text":"claude","submit":true]) == nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"a\nb","submit":true]) == nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"ok"]) == nil)
    precondition(VoiceTerminalAction.parse("delete_files",[:]) == nil)
    precondition(VoiceTerminalAction.parse("interrupt_terminal",["terminal_id":2,"key":"escape"]) != nil)
    precondition(VoiceTerminalAction.parse("interrupt_terminal",["terminal_id":-1]) == nil)
    let terminal = TerminalEvent(kind: "failure",code: 1,duration: 4,time: 1,session: "ttys001",app: "vscode")
    precondition(terminal.valid && terminal.message == "ttys001: failed (1)")
    precondition(!TerminalEvent(kind: "execute",code: 0,duration: 0,time: 1,session: "terminal",app: "unknown").valid)
    precondition(!TerminalEvent(kind: "success",code: 0,duration: 0,time: 1,session: "bad\nlabel",app: "unknown").valid)
    let cases: [(Double, Double, Int)] = [(0,100,0),(100,0,4),(0,-100,8),(-100,0,12),(100,100,2),(100,-100,6),(-100,-100,10),(-100,100,14)]
    for (x,y,want) in cases { precondition(direction(x,y) == want) }
    for i in 0..<16 {
        let a = Double(i) * 22.5 * .pi / 180
        precondition(direction(sin(a)*100,cos(a)*100) == i)
    }
    precondition(direction(0,0) == nil)
    var activity = TypingActivity()
    precondition(!activity.active(at: 10))
    activity.pulse(at: 10)
    precondition(activity.active(at: 10.5))
    activity.pulse(at: 10.6)
    precondition(activity.active(at: 11.2))
    precondition(!activity.active(at: 11.4))
    guard let resources = Bundle.main.resourceURL else { fatalError("Missing bundle resources") }
    for (r,n) in [6,8,8,4,5,8,6,6,6,8,8].enumerated() {
        for c in 0..<n { precondition(NSImage(contentsOf: resources.appendingPathComponent("frames/\(r)-\(c).png")) != nil) }
    }
    var reminder = WalkReminder(next: 1200)
    precondition(!reminder.due(at: 1199,enabled: true))
    precondition(!reminder.due(at: 1200,enabled: false))
    precondition(reminder.due(at: 1200,enabled: true))
    precondition(!reminder.due(at: 1201,enabled: true))
    precondition(reminder.due(at: 2400,enabled: true))
    precondition(reminder.due(at: 10000,enabled: true) && reminder.next == 11200)
    var focusReminder = WalkReminder(next: 1800,interval: 1800)
    precondition(!focusReminder.due(at: 1799,enabled: true) && focusReminder.due(at: 1800,enabled: true) && focusReminder.next == 3600)
    var game = BallGame(origin: .zero,start: 0,runs: 5)
    game.run(to: NSPoint(x: 300,y: 400),at: 0)
    func near(_ a: NSPoint,_ x: Double,_ y: Double) -> Bool { abs(a.x-x) < 1e-6 && abs(a.y-y) < 1e-6 }
    precondition(game.duration == 2 && game.ballDuration == 1.25 && game.start == 0.35 && game.waiting(at: 0.3) && !game.waiting(at: 0.35))
    precondition(near(game.position(at: 0.2),0,0) && near(game.position(at: 1.35),150,200) && !game.finished(at: 2.3) && game.finished(at: 2.4))
    precondition(near(game.ballPosition(at: 0),0,0) && near(game.ballPosition(at: 0.625),262.5,350) && near(game.ballPosition(at: 1.25),300,400) && near(game.ballPosition(at: 9),300,400))
    precondition(abs(game.ballRoll(at: 1.25)+500/15) < 1e-6)
    var runs = 1, clock = 0.0
    while true {
        clock = game.start+game.duration
        if game.returning { break }
        if game.runsLeft > 0 { runs += 1; game.run(to: NSPoint(x: Double(runs)*10,y: 5),at: clock) } else { game.goHome(at: clock) }
    }
    precondition(runs == 5 && game.runsLeft == 0 && game.duration == 1 && game.finished(at: clock) && near(game.position(at: clock),0,0) && game.to == game.origin && game.ballTo == NSPoint(x: 50,y: 5))
    var life = LifeState(lastActivity: 10, nextBreak: 1800)
    precondition(!life.sleeping(at: 189,autoSleep: true))
    precondition(life.sleeping(at: 190,autoSleep: true))
    life.activity(at: 191); precondition(!life.sleeping(at: 191,autoSleep: true))
    life.focusEnd = 200; precondition(life.sleeping(at: 195,autoSleep: false))
    precondition(!life.completeFocus(at: 199)); precondition(life.completeFocus(at: 200)); precondition(!life.completeFocus(at: 201))
    precondition(!life.breakDue(at: 201,enabled: true,sleeping: false))
    precondition(life.breakDue(at: 2000,enabled: true,sleeping: false))
    let trip = Excursion(kind: .chase,origin: .zero,target: NSPoint(x: 100,y: 50),start: 10,duration: 2)
    precondition(trip.position(at: 10) == .zero && trip.position(at: 12) == .zero)
    precondition(trip.position(at: 11) == trip.target)
    for i in 0..<100 { activity.pulse(at: 20+Double(i)*0.01) }
    precondition(activity.presses.count == 40 && activity.cadence(at: 21) == 0.065)
    print("PASS: life/focus/break transitions, excursion return, typing speed/storage; 16 cursor directions, compass cases, deadzone, typing renewal/expiry, and sprite resources")
} else if CommandLine.arguments.contains("--audio-startup-smoke") {
    _ = NSApplication.shared
    let desk = TerminalDesk(); let voice = GeminiVoice(desk: desk)
    do { try voice.startAudio(); print("PASS: audio engine started; no network session or audio storage") }
    catch { let e = error as NSError; print("FAIL: \(e.domain) \(e.code)") }
    voice.stop(); desk.shutdown()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-voice"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let desk = TerminalDesk(); let voice = GeminiVoice(desk: desk)
    let view = voice.window.contentView!; view.wantsLayer = true; view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds,to: rep)
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
    desk.shutdown()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-gallery"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let canvas = NSImage(size: NSSize(width: 768,height: 832))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.9,alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 768,height: 832).fill()
    for i in 0..<16 {
        let view = PetView(frame: NSRect(x: 0,y: 0,width: 192,height: 208))
        view.sprite = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("frames/\(9+i/8)-\(i%8).png"))
        view.clock = 1; view.home = .cushion; view.gazeDirection = i
        view.headphones = true; view.typingPhase = nil
        view.snoozing = false; view.happy = false
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: Double(i%4)*192,yBy: Double(3-i/4)*208); transform.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    canvas.unlockFocus()
    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
} else {
    let app = NSApplication.shared
    let delegate = Companion()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
