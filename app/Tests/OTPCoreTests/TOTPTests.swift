import Foundation
import Testing
@testable import OTPCore

/// base32 of the ASCII key "12345678901234567890" from RFC 6238 Appendix B.
private let rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

@Test func base32DecodesRFCKey() throws {
    #expect(try Base32.decode(rfcSecret) == Array("12345678901234567890".utf8))
}

@Test func base32IgnoresCaseSpacesAndPadding() throws {
    #expect(try Base32.decode("gezd gnbv gy3t qojq gezd gnbv gy3t qojq==") == Array("12345678901234567890".utf8))
}

@Test func base32RejectsCharactersOutsideTheAlphabet() {
    #expect(throws: Base32Error.invalidCharacter("1")) { try Base32.decode("ABC1") }
}

@Test func base32RejectsSecretsTooShortForOneByte() {
    #expect(throws: Base32Error.empty) { try Base32.decode("A") }
}

@Test(arguments: [
    (59.0, "287082"),
    (1_111_111_109.0, "081804"),
    (1_111_111_111.0, "050471"),
    (1_234_567_890.0, "005924"),
    (2_000_000_000.0, "279037"),
    (20_000_000_000.0, "353130"),
])
func totpMatchesRFC6238Vectors(seconds: Double, expected: String) throws {
    #expect(try TOTP.code(secret: rfcSecret, at: Date(timeIntervalSince1970: seconds)) == expected)
}

@Test func totpIsStableWithinAStepAndChangesAcrossIt() throws {
    let start = Date(timeIntervalSince1970: 1_234_567_890 - 1_234_567_890.truncatingRemainder(dividingBy: 30))
    let a = try TOTP.code(secret: rfcSecret, at: start)
    let b = try TOTP.code(secret: rfcSecret, at: start.addingTimeInterval(29.9))
    let c = try TOTP.code(secret: rfcSecret, at: start.addingTimeInterval(30))
    #expect(a == b)
    #expect(a != c)
}
