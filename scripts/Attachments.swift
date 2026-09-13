import AppKit
import CryptoKit
import Foundation
import ImageIO

enum AttachmentKind: String {
    case image, file
}

enum AttachmentError: Error, CustomStringConvertible {
    case invalidFile, invalidImage, animatedImage, clipboardWrite, stagingFailed

    var description: String {
        switch self {
        case .invalidFile: return "attachment_not_readable_regular_file"
        case .invalidImage: return "attachment_not_decodable_image"
        case .animatedImage: return "animated_image_use_send_file"
        case .clipboardWrite: return "attachment_clipboard_write_failed"
        case .stagingFailed: return "attachment_staging_failed"
        }
    }
}

/// Preserve every materialized representation, including images and file URLs.
struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { result[type] = data }
            }
            return result
        }
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let restored = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }
}

func fileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty {
        hash.update(data: block)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Compare decoded pixels, not PNG/TIFF encodings. Reject unsupported/huge images
/// before allocating a bitmap (the limit is a helper resource bound, not WeChat's).
func pixelDigest(_ data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 16_384, height <= 16_384,
          width * height <= 40_000_000,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let bytes = context.data else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var hash = SHA256()
    hash.update(data: Data("\(width)x\(height)\0".utf8))
    hash.update(data: Data(bytes: bytes, count: width * height * 4))
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}

struct Attachment {
    let kind: AttachmentKind
    let url: URL
    let digest: String
    let imageData: Data?
    let imagePixelDigest: String?

    init(kind: AttachmentKind, path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
              values.isRegularFile == true, values.isReadable == true else {
            throw AttachmentError.invalidFile
        }
        self.kind = kind
        self.url = url
        do { digest = try fileDigest(url) }
        catch { throw AttachmentError.invalidFile }
        if kind == .image {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw AttachmentError.invalidImage
            }
            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 0 else { throw AttachmentError.invalidImage }
            guard frameCount == 1 else { throw AttachmentError.animatedImage }
            guard let data = try? Data(contentsOf: url), let pixels = pixelDigest(data) else {
                throw AttachmentError.invalidImage
            }
            // Freeze image bytes so editing the original cannot change what is pasted.
            let dataDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard dataDigest == digest else { throw AttachmentError.invalidFile }
            imageData = data
            imagePixelDigest = pixels
        } else {
            imageData = nil
            imagePixelDigest = nil
        }
    }

    func sendKey(contact: String) -> String {
        // Structured framing separates kinds and filenames without delimiter collisions.
        let fields = ["attachment-v1", contact, kind.rawValue, url.lastPathComponent, digest]
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Files are pasted by URL and may be read asynchronously by WeChat. Keep a
    /// private snapshot for seven days; never remove it immediately after Send.
    func stage(in root: URL) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            guard try fileDigest(destination) == digest else { throw AttachmentError.stagingFailed }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw AttachmentError.stagingFailed
        }
    }

    func write(to pasteboard: NSPasteboard, stagedURL: URL?) throws {
        pasteboard.clearContents()
        if kind == .image {
            guard let data = imageData, let image = NSImage(data: data),
                  pasteboard.writeObjects([image]) else { throw AttachmentError.clipboardWrite }
        } else {
            guard let stagedURL, (try? fileDigest(stagedURL)) == digest,
                  pasteboard.writeObjects([stagedURL as NSURL]) else {
                throw AttachmentError.clipboardWrite
            }
        }
    }

    /// Only accept one rich clipboard item read back from the composer. Never
    /// accept a filename or a path copied as plain text as proof of an attachment.
    func matches(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, items.count == 1 else { return false }
        let text = pasteboard.string(forType: .string) ?? ""
        let attachmentOnlyText = text.isEmpty || text == "\u{FFFC}"
        // A rich-text selection can include a thumbnail plus unrequested content.
        // Validate the whole selection before considering standalone image types.
        if items[0].data(forType: .rtfd) != nil {
            return attachmentOnlyText && matchesRichText(items[0])
        }
        if kind == .image {
            guard attachmentOnlyText else { return false }
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = items[0].data(forType: type),
                   let pixels = pixelDigest(data), pixels == imagePixelDigest { return true }
            }
            return false
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL],
              urls.count == 1, urls[0].isFileURL,
              urls[0].lastPathComponent == url.lastPathComponent,
              let values = try? urls[0].resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true {
            // NSURL writers may also publish a plain-text representation. It is
            // only accepted alongside the verified rich file URL and byte hash.
            guard attachmentOnlyText || text == urls[0].path || text == urls[0].absoluteString else { return false }
            return (try? fileDigest(urls[0])) == digest
        }
        return false
    }

    private func matchesRichText(_ item: NSPasteboardItem) -> Bool {
        guard let data = item.data(forType: .rtfd),
              let text = try? NSAttributedString(data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtfd],
                  documentAttributes: nil),
              text.string == "\u{FFFC}" else { return false }
        guard let attachment = text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
              let wrapper = attachment.fileWrapper,
              wrapper.isRegularFile, let contents = wrapper.regularFileContents else { return false }
        if kind == .image {
            guard let pixels = pixelDigest(contents) else { return false }
            return pixels == imagePixelDigest
        }
        guard (wrapper.preferredFilename ?? wrapper.filename) == url.lastPathComponent else { return false }
        return SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined() == digest
    }
}

func pruneStagedAttachments(in root: URL, now: Date = Date()) {
    guard let directories = try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
    ) else { return }
    for directory in directories {
        guard UUID(uuidString: directory.lastPathComponent) != nil,
              let values = try? directory.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let created = values.creationDate, now.timeIntervalSince(created) > 7 * 86_400 else { continue }
        try? FileManager.default.removeItem(at: directory)
    }
}
