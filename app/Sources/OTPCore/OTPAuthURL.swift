import Foundation

/// Parses `otpauth://totp/...` URLs the way the Electron app's `parseOtpUrl` did:
/// only `secret` and `issuer` are read, only `totp` is accepted.
public enum OTPAuthURL {
    public static func parse(_ raw: String) -> Account? {
        // WHATWG URL (what Electron used) quietly percent-encodes a raw space in the
        // label; URLComponents rejects it instead, so do the encoding here.
        let escaped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "%20")
        // decodeURIComponent threw on a malformed escape in the label, failing the
        // whole parse. URLComponents instead silently re-escapes a stray "%", so
        // reject it up front. (The query is exempt: URLSearchParams never threw.)
        let beforeQuery = escaped.split(separator: "?", maxSplits: 1).first ?? ""
        if beforeQuery.range(of: "%(?![0-9A-Fa-f]{2})", options: .regularExpression) != nil {
            return nil
        }
        guard let components = URLComponents(string: escaped),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp"
        else { return nil }

        let params = queryParameters(components.percentEncodedQuery)
        let secret = Account.normalizeSecret(params["secret"] ?? "")
        // Rejecting a secret that isn't base32 here makes import count it as skipped
        guard !secret.isEmpty, Account.isValidSecret(secret) else { return nil }

        var encodedLabel = components.percentEncodedPath
        if encodedLabel.hasPrefix("/") { encodedLabel.removeFirst() }
        // Well-formed escapes that aren't valid UTF-8 ("%E0%A4") also made
        // decodeURIComponent throw; removingPercentEncoding returns nil for them.
        guard let label = encodedLabel.removingPercentEncoding else { return nil }

        var issuer = ""
        var account = label.trimmingCharacters(in: .whitespaces)
        if let colon = label.firstIndex(of: ":") {
            issuer = label[..<colon].trimmingCharacters(in: .whitespaces)
            account = label[label.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if let issuerParam = params["issuer"], !issuerParam.isEmpty {
            issuer = issuerParam
        }
        return Account(account: account, secret: secret, issuer: issuer)
    }

    /// URLSearchParams semantics: `+` means space, and the first occurrence of a
    /// key wins.
    private static func queryParameters(_ query: String?) -> [String: String] {
        var result: [String: String] = [:]
        for pair in (query ?? "").split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { continue }
            let key = decodeFormComponent(rawKey)
            let value = parts.count > 1 ? decodeFormComponent(parts[1]) : ""
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    private static func decodeFormComponent(_ s: Substring) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
