import Foundation

/// A 32x32 PNG data URL plus the domain that produced it.
public struct FaviconResult: Equatable, Sendable {
    public let icon: String
    public let domain: String

    public init(icon: String, domain: String) {
        self.icon = icon
        self.domain = domain
    }
}

/// What a favicon lookup concluded. `notFound` means the icon services answered and
/// had nothing. `unreachable` means at least one of them couldn't be asked at all
/// (offline, DNS, timeout), so the missing icon proves nothing and must not be
/// remembered as a miss.
public enum FaviconOutcome: Equatable, Sendable {
    case found(FaviconResult)
    case notFound
    case unreachable

    public var result: FaviconResult? {
        if case .found(let result) = self { return result }
        return nil
    }
}
