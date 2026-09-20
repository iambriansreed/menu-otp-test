import Foundation

public enum IconBackfill {
    /// How long a failed lookup is trusted before an icon-less account is retried at
    /// launch. Long enough that a day of launches doesn't repeat the same requests
    /// for an issuer nothing has an icon for; short enough that the icon service
    /// catching up doesn't take forever to notice.
    public static let missTTL: TimeInterval = 7 * 24 * 60 * 60

    public static func needsLookup(_ account: Account, now: Date) -> Bool {
        guard account.canLookUpIcon else { return false }
        guard let checkedAt = account.iconCheckedAt else { return true }
        return now.timeIntervalSince1970 * 1000 - checkedAt > missTTL * 1000
    }

    /// Looks up `items` (identity, search source) at most `concurrency` at a time,
    /// handing each outcome to `onResult` as it arrives, so progress survives the
    /// app quitting part-way.
    public static func run(
        _ items: [(AccountIdentity, String)],
        concurrency: Int = 4,
        lookup: @escaping @Sendable (String) async -> FaviconOutcome,
        onResult: @escaping @Sendable (AccountIdentity, FaviconOutcome) async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var pending = items.makeIterator()
            func enqueue() -> Bool {
                guard let (identity, source) = pending.next() else { return false }
                group.addTask {
                    let result = await lookup(source)
                    await onResult(identity, result)
                }
                return true
            }
            for _ in 0..<max(1, concurrency) where !enqueue() { break }
            while await group.next() != nil { _ = enqueue() }
        }
    }
}
