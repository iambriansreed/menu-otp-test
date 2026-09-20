import Foundation
import Testing
@testable import OTPCore

/// Serves canned bodies by exact URL string (anything else answers with no content)
/// and records every request. `offline` makes every request unreachable.
final class StubFetcher: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Data]
    private var log: [String] = []
    private var isOffline = false
    private let delay: Duration

    init(_ responses: [String: Data] = [:], delay: Duration = .zero) {
        self.responses = responses
        self.delay = delay
    }

    var requests: [String] { lock.withLock { log } }

    func set(_ url: String, _ data: Data?) { lock.withLock { responses[url] = data } }
    func setOffline(_ offline: Bool) { lock.withLock { isOffline = offline } }

    func get(_ url: URL) async -> HTTPOutcome {
        lock.withLock { log.append(url.absoluteString) }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return lock.withLock {
            if isOffline { return .unreachable }
            return responses[url.absoluteString].map(HTTPOutcome.body) ?? .noContent
        }
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

private let png = ImageFixtures.png(size: 64, red: 0, green: 1, blue: 0)
private func ddg(_ domain: String) -> String { "https://icons.duckduckgo.com/ip3/\(domain).ico" }
private func google(_ domain: String) -> String { "https://www.google.com/s2/favicons?domain=\(domain)&sz=64" }

@Test func duckDuckGoHitOnFirstDomain() async {
    let fetcher = StubFetcher([ddg("github.com"): png])
    let service = FaviconService(fetcher: fetcher)
    let result = await service.favicon(for: "GitHub").result
    #expect(result?.domain == "github.com")
    #expect(result?.icon.hasPrefix("data:image/png;base64,") == true)
    #expect(fetcher.requests == [ddg("github.com")])
}

@Test func retriesWithWWWBeforeMovingOn() async {
    let fetcher = StubFetcher([ddg("www.npmjs.com"): png])
    let result = await FaviconService(fetcher: fetcher).favicon(for: "npmjs.com").result
    #expect(result?.domain == "npmjs.com")
    #expect(fetcher.requests == [ddg("npmjs.com"), ddg("www.npmjs.com")])
}

@Test func googleIsOnlyAskedAfterDuckDuckGoMissesEveryDomain() async {
    let fetcher = StubFetcher([google("amazonwebservices.com"): png])
    let result = await FaviconService(fetcher: fetcher).favicon(for: "Amazon Web Services").result
    #expect(result?.domain == "amazonwebservices.com")
    #expect(fetcher.requests == [
        ddg("amazonwebservices.com"), ddg("www.amazonwebservices.com"),
        ddg("amazon.com"), ddg("www.amazon.com"),
        google("amazonwebservices.com"),
    ])
}

@Test func undecodableBodyCountsAsMiss() async {
    let fetcher = StubFetcher([ddg("x.com"): Data("<html>".utf8)])
    #expect(await FaviconService(fetcher: fetcher).favicon(for: "x.com") == .notFound)
}

@Test func hitsAreCached() async {
    let fetcher = StubFetcher([ddg("github.com"): png])
    let service = FaviconService(fetcher: fetcher)
    _ = await service.favicon(for: "GitHub")
    _ = await service.favicon(for: "github.com")
    #expect(fetcher.requests.count == 1)
}

@Test func concurrentLookupsShareOneRequest() async {
    let fetcher = StubFetcher([ddg("github.com"): png], delay: .milliseconds(100))
    let service = FaviconService(fetcher: fetcher)
    async let a = service.favicon(for: "GitHub")
    async let b = service.favicon(for: "GitHub")
    let results = await [a, b]
    #expect(results.allSatisfy { $0.result?.domain == "github.com" })
    #expect(fetcher.requests == [ddg("github.com")])
}

@Test func missesExpireAfterNegativeTTL() async {
    let fetcher = StubFetcher()
    let clock = TestClock()
    let service = FaviconService(fetcher: fetcher, now: { clock.now })
    #expect(await service.favicon(for: "x.com") == .notFound)
    let firstRound = fetcher.requests.count
    #expect(firstRound == 3) // ddg bare, ddg www, google

    _ = await service.favicon(for: "x.com")
    #expect(fetcher.requests.count == firstRound)

    fetcher.set(ddg("x.com"), png)
    clock.advance(FaviconService.negativeTTL + 1)
    #expect(await service.favicon(for: "x.com").result?.domain == "x.com")
}

@Test func offlineIsUnreachableAndNotCached() async {
    let fetcher = StubFetcher([ddg("github.com"): png])
    fetcher.setOffline(true)
    let service = FaviconService(fetcher: fetcher)
    #expect(await service.favicon(for: "GitHub") == .unreachable)
    // Back online: asked again straight away, not treated as a remembered miss
    fetcher.setOffline(false)
    #expect(await service.favicon(for: "GitHub").result?.domain == "github.com")
}

@Test func anUnreachableServiceMakesAnOtherwiseEmptyResultUnreachable() async {
    // DuckDuckGo answers "nothing" but Google can't be reached: not a real miss
    final class HalfOffline: HTTPFetching, @unchecked Sendable {
        func get(_ url: URL) async -> HTTPOutcome {
            url.host == "www.google.com" ? .unreachable : .noContent
        }
    }
    #expect(await FaviconService(fetcher: HalfOffline()).favicon(for: "x.com") == .unreachable)
}

/// Hits the real icon services. Off by default (network); run with
/// MENU_OTP_NETWORK_TESTS=1 (see the plan's Task 4).
@Test(.enabled(if: ProcessInfo.processInfo.environment["MENU_OTP_NETWORK_TESTS"] == "1"))
func liveLookupFindsGitHub() async throws {
    let result = try #require(await FaviconService().favicon(for: "GitHub").result)
    #expect(result.domain == "github.com")
    let image = try #require(ImageFixtures.image(fromDataURL: result.icon))
    #expect(image.width == 32 && image.height == 32)
}
