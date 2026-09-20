import Foundation

public enum Base32Error: Error, Equatable {
    case invalidCharacter(Character)
    case empty
}

public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Decodes RFC 4648 base32. Case-insensitive; whitespace and `=` padding are
    /// ignored. Bits left over that don't fill a whole byte are dropped, which is what
    /// every TOTP implementation does with secrets whose length isn't a multiple of 8.
    ///
    /// Unlike the Electron app's hand-rolled decoder (which silently produced garbage
    /// for an unknown character), anything outside the alphabet throws, so a bad
    /// secret fails loudly instead of copying a wrong code.
    public static func decode(_ string: String) throws -> [UInt8] {
        var buffer: UInt32 = 0
        var bits = 0
        var out: [UInt8] = []
        for ch in string.uppercased() where !ch.isWhitespace && ch != "=" {
            guard let value = alphabet.firstIndex(of: ch) else {
                throw Base32Error.invalidCharacter(ch)
            }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
                buffer &= (1 << UInt32(bits)) - 1
            }
        }
        if out.isEmpty { throw Base32Error.empty }
        return out
    }
}
