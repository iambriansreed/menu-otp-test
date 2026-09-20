import Foundation

/// Issuer + account is an account's identity everywhere: dedupe on add/import,
/// resolving a popover click, re-finding an account after an async icon lookup.
/// Two stored accounts must never share one.
public struct AccountIdentity: Hashable, Sendable {
    public var issuer: String
    public var account: String

    public init(issuer: String, account: String) {
        self.issuer = issuer
        self.account = account
    }
}

/// One TOTP account. The JSON shape matches the Electron app's `Account` type
/// field for field (`hidden` omitted when false, optionals omitted when nil,
/// `iconCheckedAt` in epoch milliseconds), so a future import/export between the two
/// apps is a straight copy.
public struct Account: Codable, Equatable, Sendable {
    public var account: String
    public var secret: String
    public var issuer: String
    /// A short emoji, or a `data:image/png;base64,...` 32x32 favicon.
    public var icon: String?
    /// Preferred favicon-lookup source, e.g. `https://example.com`.
    public var url: String?
    /// Kept out of the menu without being removed from Settings.
    public var hidden: Bool
    /// Epoch milliseconds of the last favicon lookup that came back empty, so the
    /// launch-time backfill doesn't re-ask on every launch. Only meaningful while
    /// `icon` is nil; cleared whenever an icon is set.
    public var iconCheckedAt: Double?

    public init(
        account: String,
        secret: String,
        issuer: String,
        icon: String? = nil,
        url: String? = nil,
        hidden: Bool = false,
        iconCheckedAt: Double? = nil
    ) {
        self.account = account
        self.secret = secret
        self.issuer = issuer
        self.icon = icon
        self.url = url
        self.hidden = hidden
        self.iconCheckedAt = iconCheckedAt
    }

    private enum CodingKeys: String, CodingKey {
        case account, secret, issuer, icon, url, hidden, iconCheckedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(String.self, forKey: .account)
        secret = try c.decode(String.self, forKey: .secret)
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        iconCheckedAt = try c.decodeIfPresent(Double.self, forKey: .iconCheckedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(secret, forKey: .secret)
        try c.encode(issuer, forKey: .issuer)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(url, forKey: .url)
        if hidden { try c.encode(true, forKey: .hidden) }
        try c.encodeIfPresent(iconCheckedAt, forKey: .iconCheckedAt)
    }

    public var identity: AccountIdentity {
        AccountIdentity(issuer: issuer, account: account)
    }

    /// "Issuer: account", or just the account when there is no issuer. (The Electron
    /// popover printed ": account" for an empty issuer; Settings didn't. This uses
    /// the Settings form everywhere.)
    public var label: String {
        issuer.isEmpty ? account : "\(issuer): \(account)"
    }

    /// True when there is no icon at all (nil or empty string).
    public var hasNoIcon: Bool { (icon ?? "").isEmpty }

    /// Has no icon but has something to search for one with.
    public var canLookUpIcon: Bool { hasNoIcon && !faviconSource.isEmpty }

    /// What a favicon lookup should search for: the explicit URL first, then the
    /// issuer, then the account name.
    public var faviconSource: String {
        [url, issuer, account]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    /// True if `secret` decodes as base32 (so TOTP.code can't throw on it). Checked
    /// wherever a secret enters the app; Electron checked nowhere, so a bad secret
    /// only surfaced later as a copy that silently failed.
    public static func isValidSecret(_ secret: String) -> Bool {
        (try? Base32.decode(secret)) != nil
    }

    /// Providers commonly display secrets in space-separated, mixed-case groups;
    /// base32 is case-insensitive, so normalize before storing.
    public static func normalizeSecret(_ secret: String) -> String {
        String(secret.filter { !$0.isWhitespace }).uppercased()
    }
}

public enum AccountIcon: Equatable, Sendable {
    case none
    case emoji(String)
    /// PNG bytes decoded from a `data:image/...;base64,` icon.
    case image(Data)

    public init(_ icon: String?) {
        guard let icon, !icon.isEmpty else {
            self = .none
            return
        }
        guard AccountIcon.isImage(icon) else {
            self = .emoji(icon)
            return
        }
        if let comma = icon.firstIndex(of: ","),
           let data = Data(base64Encoded: String(icon[icon.index(after: comma)...])) {
            self = .image(data)
        } else {
            self = .none
        }
    }

    public static func isImage(_ icon: String?) -> Bool {
        icon?.hasPrefix("data:image/") == true
    }
}
