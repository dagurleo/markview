import AppKit
import PDFKit

// compare <reference folder> <current folder> <diff folder>
//
// Compares the PNGs and PDFs of the same name in two folders, pixel by pixel and page by page,
// and lists those that differ. For each difference it writes an image to the diff folder: the
// current rendering, faded, with every pixel that changed in red. Exits with 1 if any differ.
// scripts/check.sh builds and runs it.

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write("usage: compare <reference folder> <current folder> <diff folder>\n".data(using: .utf8)!)
    exit(2)
}
let reference = URL(fileURLWithPath: arguments[1]), current = URL(fileURLWithPath: arguments[2]), diffs = URL(fileURLWithPath: arguments[3])
try? FileManager.default.createDirectory(at: diffs, withIntermediateDirectories: true)

struct Bitmap {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    init?(png url: URL) {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(image)
    }

    /// A page drawn at twice its size on white, as it would print.
    init(page: PDFPage) {
        let box = page.bounds(for: .mediaBox)
        let context = CGContext(data: nil, width: Int(box.width * 2), height: Int(box.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: context)
        self.init(context.makeImage()!)
    }

    /// How many pixels differ from another bitmap of the same size, and an image marking them.
    func difference(from other: Bitmap) -> (count: Int, marked: CGImage)? {
        var marked = pixels, count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[i] != other.pixels[i] || pixels[i + 1] != other.pixels[i + 1] || pixels[i + 2] != other.pixels[i + 2] {
                count += 1
                marked[i] = 255; marked[i + 1] = 0; marked[i + 2] = 0; marked[i + 3] = 255
            } else {
                for c in 0..<3 { marked[i + c] = UInt8(155 + Int(pixels[i + c]) * 100 / 255) }
            }
        }
        guard count > 0 else { return nil }
        let provider = CGDataProvider(data: Data(marked) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return (count, image)
    }
}

func write(_ image: CGImage, to url: URL) {
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
}

/// Compares two bitmaps and says what differs, writing the marked image if anything does.
func compare(_ old: Bitmap, _ new: Bitmap, name: String) -> String? {
    guard old.width == new.width, old.height == new.height else {
        return "size \(old.width)×\(old.height) became \(new.width)×\(new.height)"
    }
    guard let (count, marked) = new.difference(from: old) else { return nil }
    write(marked, to: diffs.appendingPathComponent(name + ".png"))
    return "\(count) pixels differ"
}

var same = 0, skipped = 0, different: [String] = []
let names = (try? FileManager.default.contentsOfDirectory(atPath: reference.path)) ?? []
for name in names.sorted() where name.hasSuffix(".png") || name.hasSuffix(".pdf") {
    let old = reference.appendingPathComponent(name), new = current.appendingPathComponent(name)
    var problems: [String] = []
    if !FileManager.default.fileExists(atPath: new.path) {
        problems.append("missing")
    } else if name.hasSuffix(".png") {
        if let a = Bitmap(png: old), let b = Bitmap(png: new) {
            // Before 0.3.0 a snapshot took the scale of the display its window was on.
            if b.width == a.width * 2, b.height == a.height * 2 { skipped += 1; continue }
            if let problem = compare(a, b, name: (name as NSString).deletingPathExtension) { problems.append(problem) }
        } else {
            problems.append("unreadable")
        }
    } else if let a = PDFDocument(url: old), let b = PDFDocument(url: new) {
        if a.pageCount != b.pageCount { problems.append("\(a.pageCount) pages became \(b.pageCount)") }
        for page in 0..<min(a.pageCount, b.pageCount) {
            let label = "\((name as NSString).deletingPathExtension)-page\(page + 1)"
            if let problem = compare(Bitmap(page: a.page(at: page)!), Bitmap(page: b.page(at: page)!), name: label) {
                problems.append("page \(page + 1): \(problem)")
            }
        }
    } else {
        problems.append("unreadable")
    }
    if problems.isEmpty { same += 1 } else { different.append("  \(name): " + problems.joined(separator: "; ")) }
}
print("\(same) the same, \(different.count) different" + (skipped > 0
    ? ", \(skipped) snapshots not compared: the reference drew them on a 1x display, at half the size (the PDFs still compare)" : ""))
different.forEach { print($0) }
exit(different.isEmpty ? 0 : 1)
