import Foundation

/// Turns a free-text issuer (or URL) into candidate domains for a favicon lookup,
/// best guess first. A line-for-line port of `issuerToDomains` in the Electron
/// app's src/favicon.ts.
public enum IssuerDomains {
    private static let authWords: Set<String> = [
        "id", "account", "accounts", "auth", "authenticator", "login",
        "otp", "totp", "2fa", "mfa", "sso",
    ]

    public static func looksLikeDomain(_ s: String) -> Bool {
        s.wholeMatch(of: /[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)*\.[a-z]{2,}/.ignoresCase()) != nil
    }

    public static func domains(for issuer: String) -> [String] {
        let raw = (issuer.removingPercentEncoding ?? issuer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return [] }

        var domains: [String] = []
        func add(_ d: String) {
            var clean = d.lowercased()
            if clean.hasPrefix("www.") { clean.removeFirst(4) }
            if looksLikeDomain(clean), !domains.contains(clean) { domains.append(clean) }
        }

        if raw.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil {
            guard let host = URL(string: raw)?.host, !host.isEmpty else { return [] }
            add(host)
            return domains
        }

        // "ID.me+Wallet" / "Google (Work)": only the part before the separator matters
        let primary = raw
            .split(omittingEmptySubsequences: false, whereSeparator: { "+|(/,".contains($0) })
            .first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""

        // An issuer that is already a domain is taken at its word. Running it through
        // the guesses below would strip the dot and invent a different site
        // ("render.com" -> rendercom.com).
        if looksLikeDomain(primary) {
            add(primary)
            return domains
        }

        func slug(_ s: String) -> String {
            String(s.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" })
        }
        let words = primary
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" })
            .map(String.init)

        // "T-Mobile ID" and "Google Authenticator" are really t-mobile.com and google.com
        let trimmed = words.enumerated()
            .filter { $0.offset == 0 || !authWords.contains($0.element.lowercased()) }
            .map(\.element)
        if trimmed.count < words.count { add(slug(trimmed.joined()) + ".com") }

        let joined = slug(words.joined())
        if !joined.isEmpty { add(joined + ".com") }
        if words.count > 1 {
            let first = slug(words[0])
            if !first.isEmpty { add(first + ".com") }
        }
        return domains
    }
}
