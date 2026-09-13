import Foundation
import AppKit
import CoreGraphics
import Vision
import ImageIO
import ApplicationServices
import CryptoKit
import Darwin

var savedClipboard: ClipboardSnapshot?
var operationLock: Int32 = -1

func cleanup() {
    if let snapshot = savedClipboard {
        savedClipboard = nil
        if !snapshot.restore(to: .general) { fputs("WARNING clipboard_restore_failed\n", stderr) }
    }
    if operationLock >= 0 { close(operationLock); operationLock = -1 }
}

func fail(_ message: String, _ code: Int32 = 2) -> Never {
    cleanup()
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

struct Win { let id: CGWindowID; let bounds: CGRect; let name: String; let pid: pid_t }

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
              let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              let b = w[kCGWindowBounds as String] as? [String:Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double,
              width > 400, height > 400 else { continue }
        let name = w[kCGWindowName as String] as? String ?? ""
        candidates.append(Win(id: id, bounds: CGRect(x:x,y:y,width:width,height:height), name:name, pid: pid))
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
    request.recognitionLanguages = ["zh-Hans", "en-US"]
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
    do {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try data.write(to: recentStateURL, options: .atomic)
    } catch { fail("recent_state_write_failed", 18) }
}

func verifyTitle(_ contact: String, timeoutMs: UInt32 = 2200) -> (Bool, String) {
    let start = DispatchTime.now().uptimeNanoseconds
    var observed = ""
    repeat {
        let win = mainWindow(), url = capture(win, label: "title")
        let texts = ocr(titleCrop(loadImage(url)))
        if ProcessInfo.processInfo.environment["WECHAT_KEEP_DEBUG"] != "1" { try? FileManager.default.removeItem(at: url) }
        observed = texts.map { $0.0 }.joined(separator: " | ")
        let target = norm(contact)
        let nonASCII = target.unicodeScalars.contains { $0.value >= 128 }
        if texts.contains(where: {
            let exact = norm($0.0) == target
            let threshold: Float = (exact && nonASCII) ? 0.45 : 0.55
            return contactMatches($0.0, contact) && $0.1 >= threshold
        }) { return (true, observed) }
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

/// Rich drafts must not be mistaken for an empty string. The sentinel is replaced
/// only by a copy originating from WeChat, never by our original payload.
func copyComposer(_ win: Win, attachment: Bool = false) -> Bool {
    click(composerPoint(win)); sleepMs(60)
    if attachment { requireAttachmentFocus(win) }
    postKey(0, flags: .maskCommand); sleepMs(30)
    let sentinel = "__WECHAT_EMPTY_PROBE_\(UUID().uuidString)__"
    setClipboard(sentinel)
    let count = NSPasteboard.general.changeCount
    postKey(8, flags: .maskCommand)
    for _ in 0..<10 {
        sleepMs(30)
        if NSPasteboard.general.changeCount != count {
            if attachment { requireAttachmentFocus(win) }
            return true
        }
    }
    if attachment { requireAttachmentFocus(win) }
    return false
}

func readComposer(_ win: Win) -> String? {
    guard copyComposer(win) else { return nil }
    // A copied image/file is nonempty even if it has no string representation.
    return getClipboard() ?? "__WECHAT_RICH_DRAFT__"
}

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

/// Attachments use the inline rich composer only. A sheet, another window or an
/// unidentifiable input is not a verified draft and must never trigger Send.
func requireAttachmentFocus(_ win: Win) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == win.pid else {
        fail("attachment_focus_lost", 20)
    }
    let app = AXUIElementCreateApplication(win.pid)
    guard let windowValue = axAttribute(app, kAXFocusedWindowAttribute),
          CFGetTypeID(windowValue) == AXUIElementGetTypeID(),
          let focusedValue = axAttribute(app, kAXFocusedUIElementAttribute),
          CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
        fail("attachment_composer_unverifiable", 20)
    }
    let window = windowValue as! AXUIElement
    let focused = focusedValue as! AXUIElement
    let children = axAttribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let hasSheet = children.contains { (axAttribute($0, kAXRoleAttribute) as? String) == kAXSheetRole }
    guard !hasSheet,
          (axAttribute(focused, kAXRoleAttribute) as? String) == kAXTextAreaRole,
          let owner = axAttribute(focused, kAXWindowAttribute), CFEqual(owner, window),
          let positionValue = axAttribute(window, kAXPositionAttribute),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          let sizeValue = axAttribute(window, kAXSizeAttribute),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        fail("attachment_composer_unverifiable", 20)
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
          abs(position.x - win.bounds.minX) < 4, abs(position.y - win.bounds.minY) < 4,
          abs(size.width - win.bounds.width) < 4, abs(size.height - win.bounds.height) < 4 else {
        fail("attachment_window_changed", 20)
    }
}

func acquireOperationLock() {
    let path = recentStateURL.deletingLastPathComponent().appendingPathComponent("operation.lock").path
    let descriptor = Darwin.open(path, O_CREAT | O_WRONLY, 0o600)
    guard descriptor >= 0 else { fail("operation_lock_failed", 18) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        close(descriptor)
        fail("another_operation_in_progress", 18)
    }
    operationLock = descriptor
}

@main
enum WeChatCLI {
    static func main() {
        defer { cleanup() }
        let args = CommandLine.arguments
        let mode = args.count > 1 ? args[1] : ""
        let attachmentKind: AttachmentKind? = mode.hasSuffix("-image") ? .image : mode.hasSuffix("-file") ? .file : nil
        let sending = ["send", "send-image", "send-file"].contains(mode)
        let dryrun = mode == "dryrun"

        // Offline diagnostics do not activate WeChat, change the clipboard, or paste.
        if mode == "validate-image" || mode == "validate-file" {
            guard args.count == 3, let attachmentKind else { fail("invalid_argument_count") }
            do {
                _ = try Attachment(kind: attachmentKind, path: args[2])
                print("ATTACHMENT_OK kind=\(attachmentKind.rawValue)")
            } catch { fail(String(describing: error), 19) }
            return
        }

        if mode == "doctor" {
            guard args.count == 2 else { fail("invalid_argument_count") }
            if !AXIsProcessTrusted() { fail("accessibility_denied", 10) }
            acquireOperationLock()
            activateWeChat()
            let w = mainWindow()
            print("DOCTOR_OK window=\(w.id) x=\(Int(w.bounds.minX)) y=\(Int(w.bounds.minY)) w=\(Int(w.bounds.width)) h=\(Int(w.bounds.height))")
            return
        }

        guard mode == "check" || dryrun || sending else {
            fail("usage: wechatctl <doctor|check CONTACT|send CONTACT TEXT|send-image CONTACT PATH|send-file CONTACT PATH|dryrun CONTACT TEXT|validate-image PATH|validate-file PATH>")
        }
        guard args.count == (mode == "check" ? 3 : 4) else { fail("invalid_argument_count") }
        let contact = args[2]
        let message = args.count >= 4 ? args[3] : ""
        if contact.isEmpty { fail("empty_contact") }
        if attachmentKind == nil && (sending || dryrun) && (message.isEmpty || message.count > 2000) { fail("invalid_message") }
        let payload: Attachment?
        do { payload = try attachmentKind.map { try Attachment(kind: $0, path: message) } }
        catch { fail(String(describing: error), 19) }
        if !AXIsProcessTrusted() { fail("accessibility_denied", 10) }

        let started = DispatchTime.now().uptimeNanoseconds
        acquireOperationLock()
        savedClipboard = ClipboardSnapshot(.general)

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
            return
        }

        let key = payload?.sendKey(contact: contact) ?? sendKey(contact, message)
        if sending, ProcessInfo.processInfo.environment["WECHAT_ALLOW_REPEAT"] != "1",
           let state = readRecentState(), state["key"] as? String == key,
           let ts = state["ts"] as? Double, Date().timeIntervalSince1970 - ts < 120 {
            if state["status"] as? String == "sent" {
                let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                print("ALREADY_SENT_RECENTLY contact=\(contact) elapsed_ms=\(ms)")
                return
            }
            fail("recent_send_uncertain_do_not_retry", 17)
        }

        let win = mainWindow()
        if copyComposer(win, attachment: payload != nil) {
            fail("composer_not_empty", 12)
        }

        if let payload {
            sendAttachment(payload, contact: contact, key: key, win: win, started: started)
            return
        }

        setClipboard(message)
        click(composerPoint(win)); sleepMs(40)
        postKey(9, flags: .maskCommand); sleepMs(80)

        let verifyWin = mainWindow()
        guard let drafted = readComposer(verifyWin), drafted == message else {
            fail("draft_verify_failed", 13)
        }
        if dryrun {
            postKey(51); sleepMs(60)
            if readComposer(mainWindow()) != nil { fail("dryrun_cleanup_failed", 16) }
            let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            print("DRYRUN_OK contact=\(contact) elapsed_ms=\(ms)")
            return
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
    }
}

func sendAttachment(_ payload: Attachment, contact: String, key: String,
                    win: Win, started: UInt64) {
    let stagingRoot = recentStateURL.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
    pruneStagedAttachments(in: stagingRoot)
    let stagedURL: URL?
    do {
        stagedURL = payload.kind == .file ? try payload.stage(in: stagingRoot) : nil
    } catch { fail(String(describing: error), 19) }

    // Staging a large file may take time; do not reuse a stale empty-draft check.
    guard verifyTitle(contact, timeoutMs: 900).0 else { fail("pre_paste_contact_verify_failed", 11) }
    if copyComposer(win, attachment: true) { fail("composer_not_empty", 12) }
    do { try payload.write(to: .general, stagedURL: stagedURL) }
    catch { fail(String(describing: error), 19) }

    // Some client versions can submit attachments on paste. Persist uncertainty
    // before the first paste as well as before the explicit Send action.
    writeRecentState("pending", key: key)
    requireAttachmentFocus(win)
    postKey(9, flags: .maskCommand)
    sleepMs(200)
    guard copyComposer(win, attachment: true), payload.matches(.general) else {
        fail("attachment_draft_verify_failed", 21)
    }

    let title = verifyTitle(contact, timeoutMs: 900)
    guard title.0 else { fail("pre_send_contact_verify_failed", 11) }
    // Title verification can take time: re-read the draft immediately before Send.
    guard copyComposer(win, attachment: true), payload.matches(.general) else {
        fail("attachment_pre_send_mismatch", 21)
    }
    requireAttachmentFocus(win)
    click(sendPoint(win)); sleepMs(150)
    var cleared = false
    for _ in 0..<24 {
        if !copyComposer(win, attachment: true) { cleared = true; break }
        sleepMs(100)
    }
    guard cleared else { fail("send_unconfirmed_attachment_remains", 14) }
    guard verifyTitle(contact, timeoutMs: 900).0 else { fail("post_send_contact_verify_failed", 15) }
    writeRecentState("sent", key: key)
    let ms = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    print("SENT contact=\(contact) kind=\(payload.kind.rawValue) elapsed_ms=\(ms)")
}
