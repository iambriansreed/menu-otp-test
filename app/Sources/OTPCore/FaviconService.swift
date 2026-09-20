import Foundation

public enum HTTPOutcome: Equatable, Sendable {
    /// A 2xx response with a usable body.
    case body(Data)
    /// The server answered, but with nothing usable (non-2xx, empty, oversized).
    case noContent
    /// No answer at all: offline, DNS failure, timeout, TLS error.
    case unreachable
}

public protocol HTTPFetching: Sendable {
    func get(_ url: URL) async -> HTTPOutcome
}

public struct URLSessionFetcher: HTTPFetching {
    static let maxBytes = 2_000_000

    /// `timeoutIntervalForResource` bounds the entire transfer, headers and body,
    /// like the Electron app's abort timer: a service that sends headers and then
    /// stalls must not hang a lookup (and every caller sharing its cache entry).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Accept": "image/png,image/*;q=0.8,*/*;q=0.5",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return URLSession(configuration: config)
    }()

    public init() {}

    public func get(_ url: URL) async -> HTTPOutcome {
        do {
            let (data, response) = try await Self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= Int64(Self.maxBytes),
                  !data.isEmpty, data.count <= Self.maxBytes
            else { return .noContent }
            return .body(data)
        } catch {
            return .unreachable
        }
    }
}

/// Favicon lookup through icon services only, never the issuer's own site (bot
/// protection answers 403; the rest serve inconsistent sizes and formats).
///
/// DuckDuckGo is asked about every candidate domain first; Google only if
/// DuckDuckGo had nothing for any of them (it rasterizes SVG-only sites like
/// render.com). DuckDuckGo therefore sees which issuers are looked up, and Google
/// sees the ones DuckDuckGo missed. Nothing else about an account leaves the Mac.
public actor FaviconService {
    public static let negativeTTL: TimeInterval = 10 * 60

    enum Source: String, CaseIterable {
        case duckDuckGo
        case google
    }

    /// One service's verdict on one domain.
    enum Lookup: Equatable, Sendable {
        case icon(String)
        case missing
        case unreachable
    }

    private struct Entry {
        let id: UUID
        let task: Task<Lookup, Never>
        let cachedAt: Date
        var resolved: Lookup?
    }

    private let fetcher: HTTPFetching
    private let now: @Sendable () -> Date
    /// "source:domain" -> the (possibly in-flight) lookup. Caching the task rather
    /// than its value lets concurrent callers for one domain share a single request.
    private var cache: [String: Entry] = [:]

    public init(fetcher: HTTPFetching = URLSessionFetcher(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.now = now
    }

    public func favicon(for source: String) async -> FaviconOutcome {
        let domains = IssuerDomains.domains(for: source)
        var anyUnreachable = false
        for service in Source.allCases {
            for domain in domains {
                switch await cached(service, domain) {
                case .icon(let icon):
                    return .found(FaviconResult(icon: icon, domain: domain))
                case .unreachable:
                    anyUnreachable = true
                case .missing:
                    break
                }
            }
        }
        return anyUnreachable ? .unreachable : .notFound
    }

    /// A hit is kept for the process lifetime. A miss (the service answered, no
    /// icon) is kept for `negativeTTL`, in case the service catches up. An
    /// unreachable result isn't kept at all: the next lookup simply asks again.
    private func cached(_ service: Source, _ domain: String) async -> Lookup {
        let key = "\(service.rawValue):\(domain)"
        if let entry = cache[key] {
            let staleMiss = entry.resolved == .missing
                && now().timeIntervalSince(entry.cachedAt) > Self.negativeTTL
            if !staleMiss { return await entry.task.value }
        }
        let id = UUID()
        let task = Task { await self.lookup(service, domain) }
        cache[key] = Entry(id: id, task: task, cachedAt: now(), resolved: nil)
        let result = await task.value
        // Only touch our own entry; a stale-miss refresh may have replaced it
        if cache[key]?.id == id {
            if result == .unreachable {
                cache[key] = nil
            } else {
                cache[key]?.resolved = result
            }
        }
        return result
    }

    private nonisolated func lookup(_ service: Source, _ domain: String) async -> Lookup {
        switch service {
        case .duckDuckGo:
            // The service often only has the www. variant of a site indexed
            let bare = await fetchIcon("https://icons.duckduckgo.com/ip3/\(domain).ico")
            if case .icon = bare { return bare }
            let www = await fetchIcon("https://icons.duckduckgo.com/ip3/www.\(domain).ico")
            if case .icon = www { return www }
            return bare == .unreachable || www == .unreachable ? .unreachable : .missing
        case .google:
            // sz=64 downscales cleanly to 32; Google 404s (with a globe) on a miss
            var components = URLComponents(string: "https://www.google.com/s2/favicons")!
            components.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "64")]
            return await fetchIcon(components.string ?? "")
        }
    }

    private nonisolated func fetchIcon(_ string: String) async -> Lookup {
        guard let url = URL(string: string) else { return .missing }
        switch await fetcher.get(url) {
        case .body(let data):
            return IconImage.dataURL(fromImageData: data).map(Lookup.icon) ?? .missing
        case .noContent:
            return .missing
        case .unreachable:
            return .unreachable
        }
    }
}
