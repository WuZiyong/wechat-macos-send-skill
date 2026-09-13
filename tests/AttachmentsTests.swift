import AppKit
import Foundation

enum TestFailure: Error { case failed(String) }

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure.failed(message) }
}

func expectFailure(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch { return }
    throw TestFailure.failed(message)
}

func bitmap(_ red: Int) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 8, bitsPerPixel: 32)!
    var pixel = [red, 0, 0, 255]
    for y in 0..<2 { for x in 0..<2 { image.setPixel(&pixel, atX: x, y: y) } }
    return image
}

func richDraft(data: Data, name: String, caption: String = "") throws -> NSPasteboardItem {
    let wrapper = FileWrapper(regularFileWithContents: data)
    wrapper.preferredFilename = name
    let attachment = NSTextAttachment(fileWrapper: wrapper)
    let text = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
    text.append(NSAttributedString(string: caption))
    let encoded = try text.data(from: NSRange(location: 0, length: text.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    let item = NSPasteboardItem()
    item.setData(encoded, forType: .rtfd)
    return item
}

@main
enum AttachmentsTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wechatctl-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = root.appendingPathComponent("测试 report.txt")
        try Data("first version\n".utf8).write(to: url)
        let file = try Attachment(kind: .file, path: url.path)

        try expectFailure("directories must be rejected") { _ = try Attachment(kind: .file, path: root.path) }
        try expectFailure("missing paths must be rejected") { _ = try Attachment(kind: .file, path: root.appendingPathComponent("missing").path) }
        try expectFailure("text is not an image") { _ = try Attachment(kind: .image, path: url.path) }
        let empty = root.appendingPathComponent("empty.bin")
        try Data().write(to: empty)
        _ = try Attachment(kind: .file, path: empty.path)

        let staging = root.appendingPathComponent("staging")
        let staged = try file.stage(in: staging)
        try file.write(to: board, stagedURL: staged)
        try expect(file.matches(board), "file URL round-trip with Chinese/spaces")
        let saved = ClipboardSnapshot(board)
        board.clearContents()
        board.setString("unrelated", forType: .string)
        try expect(saved.restore(to: board) && file.matches(board), "restore file clipboard")

        board.clearContents()
        board.setString(url.path, forType: .string)
        try expect(!file.matches(board), "plain path must not verify as attachment")
        board.clearContents()
        board.writeObjects([try richDraft(data: Data("first version\n".utf8), name: url.lastPathComponent)])
        try expect(file.matches(board), "file embedded in RTFD")
        board.clearContents()
        board.writeObjects([try richDraft(data: Data("first version\n".utf8), name: url.lastPathComponent, caption: "extra")])
        try expect(!file.matches(board), "caption must not pass single-attachment verification")

        let key = file.sendKey(contact: "Alice")
        try expect(key != file.sendKey(contact: "Bob"), "recipient participates in deduplication")
        try Data("second version\n".utf8).write(to: url)
        let changed = try Attachment(kind: .file, path: url.path)
        try expect(key != changed.sendKey(contact: "Alice"), "same filename with different bytes is a new payload")
        try expectFailure("mutation before staging must be rejected") { _ = try file.stage(in: staging) }
        try file.write(to: board, stagedURL: staged)
        try expect(file.matches(board), "staged bytes remain stable when original changes")
        try expect(!changed.matches(board), "wrong file bytes must fail")
        let renamed = root.appendingPathComponent("renamed.txt")
        try fm.copyItem(at: staged, to: renamed)
        let renamedFile = try Attachment(kind: .file, path: renamed.path)
        try expect(key != renamedFile.sendKey(contact: "Alice"), "visible filename participates in deduplication")
        try expect(!renamedFile.matches(board), "same bytes but wrong filename must fail")

        let red = bitmap(255)
        let png = red.representation(using: .png, properties: [:])!
        let tiff = red.representation(using: .tiff, properties: [:])!
        let imageURL = root.appendingPathComponent("photo.png")
        try png.write(to: imageURL)
        let image = try Attachment(kind: .image, path: imageURL.path)
        let imageAsFile = try Attachment(kind: .file, path: imageURL.path)
        try expect(image.sendKey(contact: "Alice") != imageAsFile.sendKey(contact: "Alice"), "image and file modes do not collide")
        try expect(pixelDigest(png) == pixelDigest(tiff), "equivalent PNG/TIFF pixels")
        try image.write(to: board, stagedURL: nil)
        try expect(image.matches(board), "NSImage pasteboard round-trip")
        let savedImage = ClipboardSnapshot(board)
        board.clearContents()
        board.setString("temporary", forType: .string)
        try expect(savedImage.restore(to: board) && image.matches(board), "restore image clipboard")
        board.clearContents()
        board.writeObjects([try richDraft(data: png, name: "photo.png")])
        try expect(image.matches(board), "image embedded in RTFD")

        let wrong = NSPasteboardItem()
        wrong.setData(bitmap(0).representation(using: .png, properties: [:])!, forType: .png)
        board.clearContents()
        board.writeObjects([wrong])
        try expect(!image.matches(board), "same dimensions but different pixels must fail")
        board.clearContents()
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setData(png, forType: .png); second.setData(png, forType: .png)
        board.writeObjects([first, second])
        try expect(!image.matches(board), "two attachments must fail")
        let mixed = NSPasteboardItem()
        mixed.setData(png, forType: .png); mixed.setString("unrequested caption", forType: .string)
        board.clearContents(); board.writeObjects([mixed])
        try expect(!image.matches(board), "image plus plain caption must fail")
        let richMixed = try richDraft(data: png, name: "photo.png", caption: "hidden in RTFD")
        richMixed.setData(png, forType: .png)
        board.clearContents(); board.writeObjects([richMixed])
        try expect(!image.matches(board), "matching thumbnail must not hide extra rich-text content")
        try expect(pixelDigest(Data("invalid".utf8)) == nil, "invalid image data must fail")

        board.clearContents()
        let emptyBoard = ClipboardSnapshot(board)
        board.setString("temporary", forType: .string)
        try expect(emptyBoard.restore(to: board) && (board.pasteboardItems ?? []).isEmpty, "restore empty clipboard")
        try Data("edited after preparation".utf8).write(to: imageURL)
        try image.write(to: board, stagedURL: nil)
        try expect(image.matches(board), "prepared image bytes are frozen")

        pruneStagedAttachments(in: staging)
        try expect(fm.fileExists(atPath: staged.path), "keep staging for asynchronous upload")
        pruneStagedAttachments(in: staging, now: Date().addingTimeInterval(8 * 86_400))
        try expect(!fm.fileExists(atPath: staged.path), "expire old private staging")
        print("ATTACHMENT_TESTS_OK")
    }
}
