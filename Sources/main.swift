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

final class PetRootView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        for button in subviews where (900...902).contains(button.tag) {
            button.frame = NSRect(x: Double(button.tag-900)*bounds.width/3, y: 1, width: bounds.width/3, height: 24)
        }
    }
}
final class PetControlButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: isHighlighted ? 0.32 : 0.17, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1,dy: 1), xRadius: 6,yRadius: 6).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: 0,y: 4,width: bounds.width,height: 16),withAttributes: [.font: NSFont.systemFont(ofSize: 10,weight: .medium),.foregroundColor: NSColor.white,.paragraphStyle: paragraph])
    }
}
final class PetVoiceButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.26, alpha: isHighlighted ? 1 : 0.94).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: 23, y: 5, width: 53, height: 17), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 17, y: 11, width: 4, height: 8), xRadius: 2, yRadius: 2).fill()
        let mic = NSBezierPath(); mic.move(to: NSPoint(x: 14, y: 13)); mic.curve(to: NSPoint(x: 24, y: 13), controlPoint1: NSPoint(x: 14, y: 5), controlPoint2: NSPoint(x: 24, y: 5)); mic.move(to: NSPoint(x: 19, y: 8)); mic.line(to: NSPoint(x: 19, y: 5)); mic.lineWidth = 1.4; NSColor.white.setStroke(); mic.stroke()
    }
}

final class PetView: NSView {
    var typingPhase: Int? = nil
    var home: PetHome = .none
    var homeDepth = 0.0
    var snoozing = false
    var happy = false
    var stretching = false
    var dancing = false
    var headphones = false
    var gazeDirection: Int? = nil
    var headphonesFitAvailable = true
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
        sprite?.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
        if headphones && headphonesFitAvailable {
            // Ear-cup centers in each original 192x208 sprite, bottom-left coordinates.
            // The far cup is hidden for profile poses; both cups share the body transform.
            let fits: [(Double,Double,Double,Double,Bool)] = [
                (43,183,125,183,false), (48,184,106,194,true),
                (49,180,113,193,true), (57,180,119,193,true),
                (96,183,119,181,true), (82,147,137,179,true),
                (63,144,135,171,true), (73,133,148,158,false),
                (39,158,125,158,false), (33,152,107,141,false),
                (38,185,108,157,true), (60,184,111,160,true),
                (43,183,94,166,true), (62,184,113,176,true),
                (65,187,121,179,true), (68,188,135,181,true)
            ]
            let f = gazeDirection.map { fits[$0] } ?? (43,181,128,181,false)
            let bx = body.width/192, by = body.height/208
            func point(_ x: Double,_ y: Double) -> NSPoint { NSPoint(x: body.minX+x*bx,y: body.minY+y*by) }
            let band = NSBezierPath()
            band.move(to: point(f.0,f.1))
            band.curve(to: point(f.2,f.3),controlPoint1: point(f.0-3,max(f.1,f.3)+(f.4 ? 10 : 22)),controlPoint2: point(f.2+3,max(f.1,f.3)+(f.4 ? 10 : 22)))
            NSColor(calibratedWhite: 0.19,alpha: 1).setStroke(); band.lineWidth = 6*bx; band.stroke()
            let visible = f.4 ? [(gazeDirection! < 8 ? f.0 : f.2,gazeDirection! < 8 ? f.1 : f.3)] : [(f.0,f.1),(f.2,f.3)]
            for (x,y) in visible {
                let center = point(x,y)
                let cup = NSRect(x: center.x-9*bx,y: center.y-13*by,width: 18*bx,height: 26*by)
                NSColor(calibratedWhite: 0.16,alpha: 1).setFill()
                NSBezierPath(roundedRect: cup,xRadius: 6*bx,yRadius: 6*by).fill()
                NSColor.systemTeal.setFill()
                NSBezierPath(roundedRect: cup.insetBy(dx: 4*bx,dy: 4*by),xRadius: 3*bx,yRadius: 3*by).fill()
            }
        }
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
        if let text = caption {
            let area = NSRect(x: 3*sx,y: bounds.height-22*sy,width: bounds.width-6*sx,height: 21*sy)
            NSColor(calibratedWhite: 0.12, alpha: 0.93).setFill()
            NSBezierPath(roundedRect: area, xRadius: 7*sx,yRadius: 7*sy).fill()
            label(text,at: area.insetBy(dx: 2*sx,dy: 3*sy),size: 10*sx,color: .white)
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
        else if event.clickCount > 1 { owner?.play(4, duration: 0.9) }
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
    var sounds = false
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
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 239), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let root = PetRootView(frame: NSRect(origin: .zero, size: panel.frame.size))
        pet.owner = self; pet.frame = NSRect(x: 0, y: 72, width: 154, height: 167)
        pet.autoresizingMask = [.width, .height]
        root.addSubview(pet)
        let voiceButton = PetVoiceButton(title: "Voice", target: self, action: #selector(openPetVoice))
        voiceButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice")
        voiceButton.imagePosition = .imageLeading
        voiceButton.bezelStyle = .rounded
        voiceButton.frame = NSRect(x: 33, y: 41, width: 88, height: 26)
        voiceButton.autoresizingMask = [.minXMargin, .maxXMargin]
        voiceButton.toolTip = "Open Gemini voice controls"
        root.addSubview(voiceButton)
        let activity = NSTextField(labelWithString: "Voice ready")
        activity.alignment = .center; activity.font = .systemFont(ofSize: 10, weight: .medium)
        activity.textColor = .white; activity.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.9); activity.drawsBackground = true
        activity.frame = NSRect(x: 0,y: 27,width: 154,height: 14); activity.autoresizingMask = [.width]; root.addSubview(activity)
        for (title, selector, x) in [("Mute", #selector(mutePetVoice), 0.0), ("End", #selector(endPetVoice), 49.0), ("⚙", #selector(voiceSettings), 98.0)] {
            let button = PetControlButton(title: title,target: self,action: selector); button.bezelStyle = .rounded
            button.tag = 900 + Int(x / 49)
            button.frame = NSRect(x: x,y: 1,width: 48,height: 24); button.autoresizingMask = [.minXMargin,.maxXMargin]; root.addSubview(button)
        }
        Timer.scheduledTimer(withTimeInterval: 0.15,repeats: true) { [weak self, weak activity, weak voiceButton] _ in
            let voice = self?.terminalDesk?.voice
            let now = ProcessInfo.processInfo.systemUptime
            activity?.stringValue = voice?.starting == true ? "Connecting…" : voice?.connected == true ? (voice?.muted == true ? "Muted" : now - (voice?.outputPulse ?? 0) < 0.5 ? "▂▆█▅▂ Speaking" : now - (voice?.inputPulse ?? 0) < 0.5 ? "▂▄▆▄▂ Listening" : "Live") : "Voice ready"
            voiceButton?.title = voice?.connected == true || voice?.starting == true ? "Stop" : "Voice"
            voiceButton?.needsDisplay = true
            activity?.toolTip = voice?.status.stringValue
        }
        panel.contentView = root
        // Default to the Large preset; subviews follow through autoresizing.
        panel.setContentSize(NSSize(width: 192, height: 192 * 208 / 192 + 72))
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
        status.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pocket Pikachu")
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
                dance(); tick(); precondition(pet.dancing && pet.sprite === images["6-0"])
                thunderbolt(); tick(); precondition(actionRow == 8 && pet.sprite === images["8-0"] && pet.caption == "Pika… CHUUU!")
                remindFocus(); tick(); precondition(pet.caption == "Hey. Time to focus." && pet.sprite === images["8-0"])
                precondition(panel.frame.width == 384 || panel.frame.width == 192)
                huge(); precondition(panel.frame.width == 384 && pet.frame.width == 384)
                showBall(); moveBall(BallGame(origin: panel.frame.origin,start: 0,runs: 1),at: 0); precondition(ballPanel?.frame.width == 84 && ballPanel?.frame.height == 76); ballPanel?.orderOut(nil)
                large(); precondition(pet.frame.width == 192)
                previewTyping(); tick(); precondition((0..<8).contains { pet.sprite === images["9-\($0)"] } && pet.typingPhase == nil)
                print("PASS: ball game ran \(runs) runs of 20-30% of \(Int(width)) px, roamed up to \(Int(reach)) px from home, and came home; dance frames and bounce; focus reminder caption")
                NSApp.terminate(nil)
            }
            return
        }
        if typingEnabled { requestTypingAccess() }
    }
    func buildMenu() {
        add("Open terminals", #selector(openTerminals))
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
        if now >= audioCheck { audioCheck = now+2; audioActive = autoAudio && outputActive() }
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
        if life.completeFocus(at: now) { announce("Focus finished. Nice work!",for: 6); play(4,duration: 1.5); playSound(purr: false) }
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
                if trip.kind == .treat { treatPanel?.orderOut(nil); announce("Nom. Acceptable.",for: 2.5); play(0,duration: 1); playSound(purr: true) }
                else { announce("I meant to miss.",for: 2.5); play(5,duration: 1.2) }
            } else {
                panel.setFrameOrigin(trip.position(at: now))
                if trip.kind == .treat && now-trip.start > trip.duration*0.45 { treatPanel?.orderOut(nil) }
            }
        }
        if var game = ballGame {
            if !game.finished(at: now) { panel.setFrameOrigin(game.position(at: now)); moveBall(game,at: now) }
            else if game.returning { panel.setFrameOrigin(game.origin); ballGame = nil; ballPanel?.orderOut(nil); announce("Enough. I win.",for: 2.5); play(0,duration: 1); playSound(purr: true) }
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
        pet.headphonesFitAvailable = row == 0
        pet.sprite = images["\(row)-\(col)"]
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
            if event.kind == "attention" { playSound(purr: false) }
        }
    }
    var seenTerminalEvents: [String] = []
    @objc func mutePetVoice() { terminalDesk?.voice?.toggleMic() }
    @objc func endPetVoice() { terminalDesk?.voice?.stop() }
    @objc func voiceSettings() { if terminalDesk == nil { terminalDesk = TerminalDesk() }; terminalDesk?.openVoice() }
    @objc func openPetVoice() {
        if terminalDesk == nil { terminalDesk = TerminalDesk() }
        if terminalDesk?.voice == nil { terminalDesk?.voice = GeminiVoice(desk: terminalDesk!) }; terminalDesk?.voice?.quickStart()
    }
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
        if now-lastPetSound > 3 { lastPetSound = now; playSound(purr: true) }
    }
    @objc func nap() { life.forcedNap = true; actionUntil = 0; pettingUntil = 0; stretchUntil = 0; typing.until = 0; announce("Nap time",for: 2) }
    @objc func stretch() {
        let now = ProcessInfo.processInfo.systemUptime
        stretchUntil = now+3; life.nextBreak = now+life.breakInterval
        announce("Time for a little stretch",for: 5)
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
        play(3,duration: 3); playSound(purr: false)
    }
    @objc func remindFocus() {
        focusUntil = ProcessInfo.processInfo.systemUptime + 30
        play(8,duration: 3); playSound(purr: false)
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
        breakItem?.state = breakReminders ? .on : .off; soundItem?.state = sounds ? .on : .off
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
        life.activity(at: now); lastChase = now
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
    @objc func thunderbolt() { play(8,duration: 1.7); announce("Pika… CHUUU!",for: 1.7); playSound(purr: false) }
    @objc func dance() { let length = Double(danceFrames.count)*0.14; play(6,duration: length); announce("Dance break",for: length); playSound(purr: true) }
    @objc func playBall() {
        guard excursion == nil, ballGame == nil else { return }
        beginDrag(); let now = ProcessInfo.processInfo.systemUptime; lastChase = now
        var game = BallGame(origin: panel.frame.origin,start: now,runs: Int.random(in: 5...7))
        game.run(to: ballTarget(from: game.origin,screenOf: game.origin),at: now); ballGame = game; showBall(); moveBall(game,at: now)
        announce("Ball!",for: 2)
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
        sound?.stop(); sound = NSSound(data: data); sound?.volume = 0.35; sound?.play()
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
        panel.setContentSize(NSSize(width: width, height: width * 208 / 192 + 72)); screenChanged()
    }
    @objc func small() { resize(115) }
    @objc func large() { resize(192) }
    @objc func extraLarge() { resize(288) }
    @objc func huge() { resize(384) }
    @objc func wave() { play(3, duration: 1.0) }
    @objc func jump() { play(4, duration: 0.85) }
    @objc func think() { play(7, duration: 2.0) }
    @objc func togglePause() { paused.toggle(); pauseItem.title = paused ? "Resume cursor following" : "Pause cursor following" }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminalDesk?.shutdown(); timer?.invalidate(); removeKeyMonitors(); sound?.stop()
        if let trip = excursion { panel.setFrameOrigin(trip.origin) }
        if let game = ballGame { panel.setFrameOrigin(game.origin) }
        savePosition()
    }
}

extension NSRect { var center: NSPoint { NSPoint(x: midX,y: midY) } }

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
