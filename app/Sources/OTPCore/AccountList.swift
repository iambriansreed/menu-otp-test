import Foundation

public enum UpsertResult: Equatable, Sendable {
    case added
    case updated
}

public struct ImportSummary: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var skipped = 0
    /// Identities of every account the import added or updated, in file order.
    public var imported: [AccountIdentity] = []

    public init() {}

    /// "2 added, 1 updated, 3 skipped", or "No valid URLs found." when nothing parsed.
    public var text: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.isEmpty ? "No valid URLs found." : parts.joined(separator: ", ")
    }
}

extension Array where Element == Account {
    public func index(of identity: AccountIdentity) -> Int? {
        firstIndex { $0.identity == identity }
    }

    public func account(for identity: AccountIdentity) -> Account? {
        index(of: identity).map { self[$0] }
    }

    /// True if two accounts share an identity. The model refuses to save such a list.
    public var hasDuplicateIdentities: Bool {
        Set(map(\.identity)).count != count
    }

    /// Adds `entry`, or merges it into the existing account with the same identity.
    ///
    /// A fresh otpauth:// URL or a re-typed account never carries icon/url/hidden, so
    /// a plain replace would silently drop what the user had set. `entry`'s own
    /// icon/url win when present (an explicit choice on the form beats what was
    /// there); `hidden` always carries over; `iconCheckedAt` carries over only while
    /// the merged account still has no icon.
    ///
    /// Returns the account as stored, which callers must use from here on (for
    /// instance to decide whether it still needs a favicon lookup).
    @discardableResult
    public mutating func upsert(_ entry: Account) -> (account: Account, result: UpsertResult) {
        guard let i = index(of: entry.identity) else {
            append(entry)
            return (entry, .added)
        }
        let existing = self[i]
        var merged = entry
        merged.icon = nonEmpty(entry.icon) ?? nonEmpty(existing.icon)
        merged.url = nonEmpty(entry.url) ?? nonEmpty(existing.url)
        merged.hidden = existing.hidden || entry.hidden
        merged.iconCheckedAt = merged.hasNoIcon ? existing.iconCheckedAt : nil
        self[i] = merged
        return (merged, .updated)
    }

    /// SwiftUI's `onMove` semantics (`destination` is an index in the list before the
    /// move). Named differently from SwiftUI's own `move(fromOffsets:toOffset:)` so
    /// the two never collide in a file that imports both.
    public mutating func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let insertAt = destination - source.count(in: 0..<destination)
        for i in source.reversed() { remove(at: i) }
        insert(contentsOf: moving, at: insertAt)
    }

    /// Parses one otpauth:// URL per line (blank lines ignored) and upserts each.
    public mutating func importLines(_ text: String) -> ImportSummary {
        var summary = ImportSummary()
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // An empty label parses, but issuer alone is an identity every other
            // unnamed account from the same issuer would share: the second such line
            // would upsert onto the first and replace its secret. AccountsModel.add
            // refuses these for the same reason, so import skips them too.
            guard let parsed = OTPAuthURL.parse(trimmed), !parsed.account.isEmpty else {
                summary.skipped += 1
                continue
            }
            let (stored, result) = upsert(parsed)
            if result == .added { summary.added += 1 } else { summary.updated += 1 }
            summary.imported.append(stored.identity)
        }
        return summary
    }

    /// Records a favicon lookup's outcome on the account with `identity`, if it still
    /// exists and still has no icon. A hit sets the icon (and the URL, if none was
    /// set) and clears any miss marker. A miss stamps `iconCheckedAt` only when
    /// `recordMiss` is true (the launch-time backfill does; explicit lookups from
    /// Settings don't). Returns whether anything changed.
    @discardableResult
    public mutating func applyIconLookup(
        _ identity: AccountIdentity,
        result: FaviconResult?,
        recordMiss: Bool,
        now: Date
    ) -> Bool {
        guard let i = index(of: identity), self[i].hasNoIcon else { return false }
        if let result {
            self[i].icon = result.icon
            if nonEmpty(self[i].url) == nil { self[i].url = result.domain }
            self[i].iconCheckedAt = nil
            return true
        }
        guard recordMiss else { return false }
        self[i].iconCheckedAt = now.timeIntervalSince1970 * 1000
        return true
    }
}

func nonEmpty(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}
