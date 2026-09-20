import CryptoKit
import Foundation

/// RFC 6238 TOTP with the same fixed parameters as the Electron app: HMAC-SHA1,
/// 30-second step, 6 digits. `algorithm`, `digits` and `period` from an otpauth://
/// URL are ignored there too.
public enum TOTP {
    public static let period: TimeInterval = 30
    public static let digits = 6

    public static func code(secret: String, at date: Date = Date()) throws -> String {
        let key = try Base32.decode(secret)
        // floor(), not the Electron version's Math.round() of the seconds: that
        // round() made the old app switch to the next code up to 500 ms early.
        let counter = UInt64(floor(date.timeIntervalSince1970 / period))
        var bigEndian = counter.bigEndian
        let message = withUnsafeBytes(of: &bigEndian) { Data($0) }
        let mac = Array(
            HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key))
        )

        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let otp = binary % 1_000_000
        return String(format: "%06u", otp)
    }
}
