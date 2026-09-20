import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalizes whatever an icon service returns into a 32x32 PNG data URL.
public enum IconImage {
    public static let size = 32

    public static func dataURL(fromImageData data: Data) -> String? {
        guard let image = decode(data),
              let scaled = resized(image),
              let png = pngData(scaled)
        else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    static func decode(_ data: Data) -> CGImage? {
        // ImageIO can open .ico files itself but ignores the 1-bit AND mask of
        // non-32-bit entries (verified on macOS 26), leaving masked pixels opaque.
        // So .ico goes through the port of the Electron app's own decoder.
        ICO.isICO(data) ? ICO.decode(data) : imageIO(data)
    }

    static func imageIO(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Aspect-fit into 32x32 with high-quality interpolation. (The Electron app
    /// stretched non-square images; icon services virtually always return square
    /// ones, and letterboxing is the better failure mode.)
    static func resized(_ image: CGImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.interpolationQuality = .high
        let scale = min(Double(size) / Double(image.width), Double(size) / Double(image.height))
        let w = Double(image.width) * scale
        let h = Double(image.height) * scale
        ctx.draw(image, in: CGRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest), out.length > 0 else { return nil }
        return out as Data
    }
}

/// .ico container parsing plus a BITMAPINFOHEADER DIB decoder (uncompressed 1/4/8
/// bit palettized, 24 and 32 bit, with the 1-bit AND transparency mask). Ported
/// from `decodeIco`/`decodeDib` in the Electron app's src/favicon.ts.
enum ICO {
    static func isICO(_ data: Data) -> Bool {
        let d = [UInt8](data.prefix(6))
        return data.count > 6 && u16(d, 0) == 0 && u16(d, 2) == 1
    }

    static func isPNG(_ bytes: [UInt8]) -> Bool {
        bytes.count > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
    }

    static func decode(_ data: Data) -> CGImage? {
        let d = [UInt8](data)
        let count = u16(d, 4)
        if count == 0 { return nil }

        var entries: [(width: Int, size: Int, offset: Int)] = []
        for i in 0..<count {
            let p = 6 + i * 16
            if p + 16 > d.count { break }
            entries.append((width: d[p] == 0 ? 256 : Int(d[p]), size: u32(d, p + 8), offset: u32(d, p + 12)))
        }

        // Smallest entry that is at least 32px wide; failing that, the largest.
        let bigEnough = entries.filter { $0.width >= IconImage.size }.sorted { $0.width < $1.width }
        let ordered = bigEnough.isEmpty ? entries.sorted { $0.width > $1.width } : bigEnough

        for entry in ordered {
            guard entry.offset < d.count else { continue }
            let end = min(d.count, entry.offset + entry.size)
            guard end > entry.offset else { continue }
            let bytes = Array(d[entry.offset..<end])
            if bytes.count < 8 { continue }
            let image = isPNG(bytes) ? IconImage.imageIO(Data(bytes)) : decodeDIB(bytes)
            if let image { return image }
        }
        return nil
    }

    static func decodeDIB(_ d: [UInt8]) -> CGImage? {
        guard d.count >= 40 else { return nil }
        let headerSize = u32(d, 0)
        guard headerSize >= 40, headerSize <= d.count else { return nil }

        let width = i32(d, 4)
        // XOR image and AND mask are stacked, so the stored height is doubled
        let height = i32(d, 8) / 2
        let bitCount = u16(d, 14)
        let compression = u32(d, 16)
        guard compression == 0, [1, 4, 8, 24, 32].contains(bitCount),
              width > 0, height > 0, width <= 1024, height <= 1024
        else { return nil }

        // Indexed formats carry a BGRX palette directly after the header
        let paletteEntries = bitCount <= 8 ? (u32(d, 32) != 0 ? u32(d, 32) : 1 << bitCount) : 0
        let pixelStart = headerSize + paletteEntries * 4
        let rowSize = ((width * bitCount + 31) / 32) * 4
        guard d.count >= pixelStart + rowSize * height else { return nil }

        // A 1bpp AND mask (1 = transparent) follows the colour data
        let maskStart = pixelStart + rowSize * height
        let maskRowSize = ((width + 31) / 32) * 4
        let hasMask = d.count >= maskStart + maskRowSize * height

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var anyOpaque = false

        for y in 0..<height {
            let srcRow = pixelStart + (height - 1 - y) * rowSize // rows are stored bottom-up
            let maskRow = maskStart + (height - 1 - y) * maskRowSize
            for x in 0..<width {
                let o = (y * width + x) * 4
                var alpha: UInt8 = 255
                let b: UInt8, g: UInt8, r: UInt8
                if bitCount >= 24 {
                    let s = srcRow + x * (bitCount / 8)
                    b = d[s]; g = d[s + 1]; r = d[s + 2]
                    if bitCount == 32 { alpha = d[s + 3] }
                } else {
                    let bit = x * bitCount
                    let packed = Int(d[srcRow + (bit >> 3)])
                    let index = (packed >> (8 - bitCount - (bit & 7))) & ((1 << bitCount) - 1)
                    let p = headerSize + index * 4
                    guard p + 3 <= d.count else { return nil }
                    b = d[p]; g = d[p + 1]; r = d[p + 2]
                }
                if bitCount != 32, hasMask, (d[maskRow + (x >> 3)] >> (7 - (x & 7))) & 1 == 1 {
                    alpha = 0
                }
                rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = alpha
                if alpha != 0 { anyOpaque = true }
            }
        }

        // Some 32bpp icons ship an all-zero alpha channel; treat those as opaque
        if !anyOpaque {
            for i in stride(from: 3, to: rgba.count, by: 4) { rgba[i] = 255 }
        }
        // CGImage wants premultiplied alpha
        for i in stride(from: 0, to: rgba.count, by: 4) where rgba[i + 3] != 255 {
            let a = UInt16(rgba[i + 3])
            rgba[i] = UInt8(UInt16(rgba[i]) * a / 255)
            rgba[i + 1] = UInt8(UInt16(rgba[i + 1]) * a / 255)
            rgba[i + 2] = UInt8(UInt16(rgba[i + 2]) * a / 255)
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    static func u16(_ d: [UInt8], _ o: Int) -> Int {
        guard o + 2 <= d.count else { return 0 }
        return Int(d[o]) | Int(d[o + 1]) << 8
    }

    static func u32(_ d: [UInt8], _ o: Int) -> Int {
        guard o + 4 <= d.count else { return 0 }
        return Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24
    }

    static func i32(_ d: [UInt8], _ o: Int) -> Int {
        Int(Int32(truncatingIfNeeded: u32(d, o)))
    }
}
