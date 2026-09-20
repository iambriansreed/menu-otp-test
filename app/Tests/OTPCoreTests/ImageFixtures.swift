import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OTPCore

/// Builds .ico/PNG bytes in memory so icon decoding is tested without network or
/// checked-in binaries. `pixel(x, y)` uses visual coordinates, y = 0 at the top.
enum ImageFixtures {
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

    /// One square BITMAPINFOHEADER DIB as stored inside an .ico entry.
    static func dib(
        size w: Int,
        bpp: Int,
        palette: [[UInt8]] = [],
        pixel: (Int, Int) -> [UInt8],
        masked: (Int, Int) -> Bool = { _, _ in false }
    ) -> [UInt8] {
        var out = le32(40) + le32(w) + le32(w * 2) + le16(1) + le16(bpp)
            + le32(0) + le32(0) + le32(0) + le32(0) + le32(palette.count) + le32(0)
        for entry in palette { out += entry }
        let rowSize = ((w * bpp + 31) / 32) * 4
        for y in (0..<w).reversed() {
            var row: [UInt8] = []
            if bpp >= 24 {
                for x in 0..<w { row += pixel(x, y) }
            } else {
                var bits: [UInt8] = []
                for x in 0..<w { bits.append(pixel(x, y)[0]) }
                var byte = 0, used = 0
                for index in bits {
                    byte = (byte << bpp) | Int(index)
                    used += bpp
                    if used == 8 { row.append(UInt8(byte)); byte = 0; used = 0 }
                }
                if used > 0 { row.append(UInt8(byte << (8 - used))) }
            }
            while row.count < rowSize { row.append(0) }
            out += row
        }
        let maskRow = ((w + 31) / 32) * 4
        for y in (0..<w).reversed() {
            var row = [UInt8](repeating: 0, count: maskRow)
            for x in 0..<w where masked(x, y) { row[x >> 3] |= UInt8(0x80 >> (x & 7)) }
            out += row
        }
        return out
    }

    /// Wraps entries (width, bytes) in an ICONDIR.
    static func ico(_ entries: [(Int, [UInt8])]) -> Data {
        var out = le16(0) + le16(1) + le16(entries.count)
        var offset = 6 + 16 * entries.count
        for (w, data) in entries {
            out += [UInt8(w % 256), UInt8(w % 256), 0, 0] + le16(1) + le16(0) + le32(data.count) + le32(offset)
            offset += data.count
        }
        for (_, data) in entries { out += data }
        return Data(out)
    }

    /// A solid-colour PNG.
    static func png(size: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return IconImage.pngData(ctx.makeImage()!)!
    }

    /// RGBA (premultiplied) of the pixel at visual (x, y), y = 0 at the top.
    static func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let o = (y * image.width + x) * 4
        return [p[o], p[o + 1], p[o + 2], p[o + 3]]
    }

    static func image(fromDataURL url: String) -> CGImage? {
        guard case let .image(data) = AccountIcon(url) else { return nil }
        return IconImage.imageIO(data)
    }
}
