import Foundation
import AppKit
import CoreGraphics
import Vision
import ImageIO
import ApplicationServices
import CryptoKit

func fail(_ message: String, _ code: Int32 = 2) -> Never {
    fputs("ERROR \(message)\n", stderr)
    exit(code)
}

func run(_ executable: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = args
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("process_failed \(executable)", 3) }
}

func sleepMs(_ ms: UInt32) { usleep(ms * 1000) }

func postKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
    guard let src = CGEventSource(stateID: .combinedSessionState) else { fail("event_source") }
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { fail("key_event") }
        e.flags = flags; e.post(tap: .cghidEventTap)
    }
}

func click(_ point: CGPoint) {
    guard let src = CGEventSource(stateID: .combinedSessionState) else { fail("event_source") }
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                              mouseCursorPosition: point, mouseButton: .left) else { fail("mouse_event") }
        e.post(tap: .cghidEventTap)
        sleepMs(type == .mouseMoved ? 60 : 35)
    }
}

func setClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func getClipboard() -> String? {
    NSPasteboard.general.string(forType: .string)
}

struct Win { let id: CGWindowID; let bounds: CGRect; let name: String }

func mainWindow() -> Win {
    guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String:Any]] else { fail("window_list") }
    var candidates: [Win] = []
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner.localizedCaseInsensitiveContains("wechat") || owner.contains("微信") else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? -1
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
        guard layer == 0, alpha > 0 else { continue }
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let b = w[kCGWindowBounds as String] as? [String:Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double,
              width > 400, height > 400 else { continue }
        let name = w[kCGWindowName as String] as? String ?? ""
        candidates.append(Win(id: id, bounds: CGRect(x:x,y:y,width:width,height:height), name:name))
    }
    guard !candidates.isEmpty else { fail("wechat_window_not_found", 4) }
    let titled = candidates.filter { $0.name == "微信" || $0.name.localizedCaseInsensitiveCompare("WeChat") == .orderedSame }
    return (titled.isEmpty ? candidates : titled).max { a,b in
        a.bounds.width * a.bounds.height < b.bounds.width * b.bounds.height
    }!
}

func activateWeChat() {
    try? run("/usr/bin/open", ["-a", "WeChat"])
    sleepMs(120)
    let apps = NSWorkspace.shared.runningApplications
    if let app = apps.first(where: { ($0.bundleIdentifier ?? "").contains("xinWeChat") || ($0.localizedName ?? "") == "WeChat" }) {
        app.activate(options: [])
    }
    sleepMs(160)
}

func capture(_ win: Win, label: String) -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wechatctl-v2", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(label)-\(UUID().uuidString).png")
    do { try run("/usr/sbin/screencapture", ["-x", "-l", String(win.id), url.path]) }
    catch { fail("capture_failed", 5) }
    return url
}

func loadImage(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("image_load", 5) }
    return img
}

func titleCrop(_ img: CGImage) -> CGImage {
    let w = CGFloat(img.width), h = CGFloat(img.height)
    let rect = CGRect(x: w * 0.20, y: 0, width: w * 0.30, height: h * 0.16).integral
    guard let crop = img.cropping(to: rect) else { fail("title_crop", 5) }
    return crop
}

func ocr(_ img: CGImage) -> [(String, Float)] {
    var out: [(String, Float)] = []
    let request = VNRecognizeTextRequest { req, _ in
        for obs in (req.results as? [VNRecognizedTextObservation]) ?? [] {
            if let top = obs.topCandidates(1).first { out.append((top.string, top.confidence)) }
        }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.02
    try? VNImageRequestHandler(cgImage: img, options: [:]).perform([request])
    return out
}

func norm(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .filter { !$0.isWhitespace && !$0.isNewline }
}

func contactMatches(_ candidate: String, _ contact: String) -> Bool {
    let c = norm(candidate), t = norm(contact)
    if c == t { return true }
    let asciiTarget = t.unicodeScalars.allSatisfy { $0.value < 128 }
    return asciiTarget && t.count >= 3 && c.hasPrefix(t) && c.count == t.count + 1
}

func sendKey(_ contact: String, _ message: String) -> String {
    let digest = SHA256.hash(data: Data((contact + "\0" + message).utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

let recentStateURL: URL = {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("wechat-macos-send", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("v2-recent-state.json")
}()

func readRecentState() -> [String:Any]? {
    guard let data = try? Data(contentsOf: recentStateURL) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
}

func writeRecentState(_ status: String, key: String) {
    let obj: [String:Any] = ["status": status, "key": key, "ts": Date().timeIntervalSince1970]
    if let data = try? JSONSerialization.data(withJSONObject: obj) { try? data.write(to: recentStateURL, options: .atomic) }
}

func verifyTitle(_ contact: String, timeoutMs: UInt32 = 2200) -> (Bool, String) {
    let start = DispatchTime.now().uptimeNanoseconds
    var observed = ""
    repeat {
        let win = mainWindow(), url = capture(win, label: "title")
        let texts = ocr(titleCrop(loadImage(url)))
        if ProcessInfo.processInfo.environment["WECHAT_KEEP_DEBUG"] != "1" { try? FileManager.default.removeItem(at: url) }
        observed = texts.map { $0.0 }.joined(separator: " | ")
        if texts.contains(where: { contactMatches($0.0, contact) && $0.1 >= 0.55 }) { return (true, observed) }
        sleepMs(90)
    } while (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 < UInt64(timeoutMs)
    return (false, observed)
}

func composerPoint(_ win: Win) -> CGPoint {
    CGPoint(x: win.bounds.maxX - 240,
            y: win.bounds.maxY - 110)
}

func sendPoint(_ win: Win) -> CGPoint {
    CGPoint(x: win.bounds.maxX - 55,
            y: win.bounds.maxY - 45)
}

func readComposer(_ win: Win) -> String? {
    click(composerPoint(win)); sleepMs(60)
    postKey(0, flags: .maskCommand); sleepMs(30)
    let sentinel = "__WECHAT_EMPTY_PROBE_\(UUID().uuidString)__"
    setClipboard(sentinel); postKey(8, flags: .maskCommand); sleepMs(60)
    let got = getClipboard()
    return got == sentinel ? nil : got
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : ""
if !AXIsProcessTrusted() { fail("accessibility_denied", 10) }

if mode == "doctor" {
    activateWeChat()
    let w = mainWindow()
    print("DOCTOR_OK window=\(w.id) x=\(Int(w.bounds.minX)) y=\(Int(w.bounds.minY)) w=\(Int(w.bounds.width)) h=\(Int(w.bounds.height))")
    exit(0)
}

guard mode == "check" || mode == "dryrun" || mode == "send" else {
    fail("usage: wechatctl <doctor|check CONTACT|dryrun CONTACT MESSAGE|send CONTACT MESSAGE>")
}
guard args.count >= 3 else { fail("missing_contact") }
let contact = args[2]
let message = args.count >= 4 ? args[3] : ""
if contact.isEmpty { fail("empty_contact") }
if (mode == "send" || mode == "dryrun") && (message.isEmpty || message.count > 2000) { fail("invalid_message") }

let started = DispatchTime.now().uptimeNanoseconds
let oldClipboard = getClipboard()
defer { if let oldClipboard { setClipboard(oldClipboard) } }

activateWeChat()
setClipboard(contact)
postKey(3, flags: .maskCommand); sleepMs(90)
postKey(0, flags: .maskCommand); sleepMs(30)
postKey(9, flags: .maskCommand); sleepMs(160)
postKey(36); sleepMs(120)
let verified = verifyTitle(contact)
if !verified.0 { fail("contact_verify_failed observed=\(verified.1)", 11) }
if mode == "check" {
    let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    print("CONTACT_OK contact=\(contact) elapsed_ms=\(ms)")
    exit(0)
}

let key = sendKey(contact, message)
if mode == "send", ProcessInfo.processInfo.environment["WECHAT_ALLOW_REPEAT"] != "1",
   let state = readRecentState(), state["key"] as? String == key,
   let ts = state["ts"] as? Double, Date().timeIntervalSince1970 - ts < 120 {
    if state["status"] as? String == "sent" {
        let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        print("ALREADY_SENT_RECENTLY contact=\(contact) elapsed_ms=\(ms)")
        exit(0)
    }
    fail("recent_send_uncertain_do_not_retry", 17)
}

let win = mainWindow()
if let existing = readComposer(win), !existing.isEmpty {
    fail("composer_not_empty", 12)
}

setClipboard(message)
click(composerPoint(win)); sleepMs(40)
postKey(9, flags: .maskCommand); sleepMs(80)

let verifyWin = mainWindow()
guard let drafted = readComposer(verifyWin), drafted == message else {
    fail("draft_verify_failed", 13)
}
if mode == "dryrun" {
    postKey(51); sleepMs(60)
    if readComposer(mainWindow()) != nil { fail("dryrun_cleanup_failed", 16) }
    let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    print("DRYRUN_OK contact=\(contact) elapsed_ms=\(ms)")
    exit(0)
}

writeRecentState("pending", key: key)
click(sendPoint(verifyWin)); sleepMs(120)
var cleared = false
for _ in 0..<12 {
    if readComposer(mainWindow()) == nil { cleared = true; break }
    sleepMs(80)
}
if !cleared { fail("send_unconfirmed_composer_not_empty", 14) }

let postTitle = verifyTitle(contact, timeoutMs: 900)
if !postTitle.0 { fail("post_send_contact_verify_failed", 15) }
writeRecentState("sent", key: key)
let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
print("SENT contact=\(contact) elapsed_ms=\(ms)")
