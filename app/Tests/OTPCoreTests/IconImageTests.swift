import CoreGraphics
import Foundation
import Testing
@testable import OTPCore

private typealias F = ImageFixtures

@Test func detectsICOHeader() {
    #expect(ICO.isICO(F.ico([(16, F.dib(size: 16, bpp: 32, pixel: { _, _ in [0, 0, 0, 255] }))])))
    #expect(!ICO.isICO(F.png(size: 4, red: 1, green: 0, blue: 0)))
}

@Test func decodes24BitDIBWithANDMask() throws {
    // BGR red everywhere, left half masked out
    let data = F.ico([(32, F.dib(size: 32, bpp: 24, pixel: { _, _ in [0, 0, 255] }, masked: { x, _ in x < 16 }))])
    let image = try #require(ICO.decode(data))
    #expect(F.rgba(image, 0, 0)[3] == 0)
    #expect(F.rgba(image, 31, 0) == [255, 0, 0, 255])
}

@Test func decodes8BitPalettizedDIB() throws {
    let palette: [[UInt8]] = [[255, 0, 0, 0], [0, 255, 0, 0]] + Array(repeating: [0, 0, 0, 0], count: 254)
    let data = F.ico([(32, F.dib(size: 32, bpp: 8, palette: palette, pixel: { x, _ in [x < 16 ? 0 : 1] }))])
    let image = try #require(ICO.decode(data))
    #expect(F.rgba(image, 0, 5) == [0, 0, 255, 255])
    #expect(F.rgba(image, 31, 5) == [0, 255, 0, 255])
}

@Test func decodes4BitAnd1BitDIBs() throws {
    let palette4: [[UInt8]] = [[0, 0, 0, 0], [255, 255, 255, 0]] + Array(repeating: [0, 0, 0, 0], count: 14)
    let four = try #require(ICO.decode(F.ico([(32, F.dib(size: 32, bpp: 4, palette: palette4, pixel: { x, _ in [x % 2 == 0 ? 1 : 0] }))])))
    #expect(F.rgba(four, 0, 0) == [255, 255, 255, 255])
    #expect(F.rgba(four, 1, 0) == [0, 0, 0, 255])

    let palette1: [[UInt8]] = [[0, 0, 0, 0], [0, 0, 255, 0]]
    let one = try #require(ICO.decode(F.ico([(32, F.dib(size: 32, bpp: 1, palette: palette1, pixel: { _, y in [y < 16 ? 1 : 0] }))])))
    #expect(F.rgba(one, 3, 0) == [255, 0, 0, 255])
    #expect(F.rgba(one, 3, 31) == [0, 0, 0, 255])
}

@Test func dibRowsAreFlippedToTopDown() throws {
    // Visual top half blue, bottom half red, 32bpp opaque
    let data = F.ico([(32, F.dib(size: 32, bpp: 32, pixel: { _, y in y < 16 ? [255, 0, 0, 255] : [0, 0, 255, 255] }))])
    let image = try #require(ICO.decode(data))
    #expect(F.rgba(image, 0, 0) == [0, 0, 255, 255])
    #expect(F.rgba(image, 0, 31) == [255, 0, 0, 255])
}

@Test func thirtyTwoBitWithAllZeroAlphaIsTreatedAsOpaque() throws {
    let data = F.ico([(32, F.dib(size: 32, bpp: 32, pixel: { _, _ in [0, 255, 0, 0] }))])
    let image = try #require(ICO.decode(data))
    #expect(F.rgba(image, 10, 10) == [0, 255, 0, 255])
}

@Test func picksSmallestEntryAtLeast32Wide() throws {
    let red = F.dib(size: 16, bpp: 32, pixel: { _, _ in [0, 0, 255, 255] })
    let green = F.dib(size: 32, bpp: 32, pixel: { _, _ in [0, 255, 0, 255] })
    let blue = F.dib(size: 48, bpp: 32, pixel: { _, _ in [255, 0, 0, 255] })
    let image = try #require(ICO.decode(F.ico([(16, red), (48, blue), (32, green)])))
    #expect(image.width == 32)
    #expect(F.rgba(image, 0, 0) == [0, 255, 0, 255])
}

@Test func fallsBackToLargestEntryWhenAllAreSmall() throws {
    let a = F.dib(size: 8, bpp: 32, pixel: { _, _ in [0, 0, 255, 255] })
    let b = F.dib(size: 16, bpp: 32, pixel: { _, _ in [0, 255, 0, 255] })
    let image = try #require(ICO.decode(F.ico([(8, a), (16, b)])))
    #expect(image.width == 16)
}

@Test func decodesPNGEntryInsideICO() throws {
    let png = [UInt8](F.png(size: 32, red: 0, green: 0, blue: 1))
    let image = try #require(ICO.decode(F.ico([(32, png)])))
    #expect(F.rgba(image, 0, 0) == [0, 0, 255, 255])
}

@Test func rejectsTruncatedAndCompressedDIBs() {
    var truncated = F.dib(size: 32, bpp: 32, pixel: { _, _ in [0, 0, 0, 255] })
    truncated.removeLast(3000)
    #expect(ICO.decodeDIB(truncated) == nil)

    var compressed = F.dib(size: 32, bpp: 32, pixel: { _, _ in [0, 0, 0, 255] })
    compressed[16] = 1
    #expect(ICO.decodeDIB(compressed) == nil)
}

@Test func dataURLIs32x32PNG() throws {
    let url = try #require(IconImage.dataURL(fromImageData: F.png(size: 64, red: 1, green: 0, blue: 0)))
    #expect(url.hasPrefix("data:image/png;base64,"))
    let image = try #require(F.image(fromDataURL: url))
    #expect(image.width == 32 && image.height == 32)
    #expect(F.rgba(image, 16, 16) == [255, 0, 0, 255])
}

@Test func dataURLFromICOUsesTheCustomDecoder() throws {
    let data = F.ico([(32, F.dib(size: 32, bpp: 24, pixel: { _, _ in [0, 0, 255] }, masked: { x, _ in x < 16 }))])
    let url = try #require(IconImage.dataURL(fromImageData: data))
    let image = try #require(F.image(fromDataURL: url))
    #expect(F.rgba(image, 2, 2)[3] == 0)
}

@Test func dataURLRejectsNonImages() {
    #expect(IconImage.dataURL(fromImageData: Data("<html>nope</html>".utf8)) == nil)
    #expect(IconImage.dataURL(fromImageData: Data()) == nil)
}
