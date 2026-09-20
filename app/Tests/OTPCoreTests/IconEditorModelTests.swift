import Foundation
import Testing
@testable import OTPCore

private let found = FaviconResult(icon: "data:image/png;base64,AA==", domain: "github.com")

/// A lookup that can be held open and released per call, to test superseded searches.
@MainActor
final class ControlledLookup {
    var calls: [String] = []
    private var continuations: [CheckedContinuation<FaviconOutcome, Never>] = []

    var lookup: @Sendable (String) async -> FaviconOutcome {
        { [weak self] source in
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    self?.calls.append(source)
                    self?.continuations.append(continuation)
                }
            }
        }
    }

    func waitForCalls(_ n: Int) async {
        while calls.count < n { await Task.yield() }
    }

    func resolve(_ index: Int, _ result: FaviconOutcome) {
        continuations[index].resume(returning: result)
    }
}

@MainActor
private func editor(
    icon: String? = nil,
    url: String? = nil,
    issuer: String = "GitHub",
    lookup: @escaping @Sendable (String) async -> FaviconOutcome = { _ in .found(found) }
) -> IconEditorModel {
    IconEditorModel(icon: icon, url: url, lookup: lookup, label: { (issuer, "jane") })
}

@MainActor @Test func initialModeFollowsTheIcon() {
    #expect(editor().mode == .favicon)
    #expect(editor(icon: "🐙").mode == .emoji)
    #expect(editor(icon: "🐙").emojiText == "🐙")
    let image = editor(icon: found.icon, url: "https://github.com")
    #expect(image.mode == .favicon)
    #expect(image.currentIcon == found.icon)
    #expect(image.urlText == "github.com")
    #expect(!image.isDirty)
}

@MainActor @Test func imageIconWithoutURLGuessesTheDomain() {
    #expect(editor(icon: found.icon, issuer: "GitHub").urlText == "github.com")
}

@MainActor @Test func findWithoutURLFillsTheDomain() async {
    let e = editor()
    await e.find()
    #expect(e.currentIcon == found.icon)
    #expect(e.urlText == "github.com")
    #expect(e.currentURL == "https://github.com")
    #expect(e.status == "Found — save to keep it.")
    #expect(e.isDirty)
}

@MainActor @Test func findPrefersTheExplicitURLAndKeepsIt() async {
    let controlled = ControlledLookup()
    let e = editor(url: "https://example.org", lookup: controlled.lookup)
    #expect(e.urlText == "example.org")
    async let search: Void = e.find()
    await controlled.waitForCalls(1)
    #expect(controlled.calls == ["example.org"])
    controlled.resolve(0, .found(found))
    await search
    #expect(e.urlText == "example.org")
    #expect(e.currentIcon == found.icon)
}

@MainActor @Test func findWithNothingToSearchSaysSo() async {
    let e = IconEditorModel(icon: nil, url: nil, lookup: { _ in .found(found) }, label: { ("", " ") })
    await e.find()
    #expect(e.status == "Enter a website URL or issuer first.")
    #expect(e.currentIcon == "")
}

@MainActor @Test func missReportsNoFavicon() async {
    let e = editor(lookup: { _ in .notFound })
    await e.find()
    #expect(e.status == "No favicon found.")
    #expect(!e.isSearching)
}

@MainActor @Test func supersededSearchIsIgnored() async {
    let controlled = ControlledLookup()
    let e = editor(lookup: controlled.lookup)
    async let first: Void = e.find()
    await controlled.waitForCalls(1)
    e.clear()
    controlled.resolve(0, .found(found))
    await first
    #expect(e.currentIcon == "")
    #expect(e.status == "")
}

@MainActor @Test func resetInvalidatesAnInFlightSearch() async {
    let controlled = ControlledLookup()
    let e = editor(lookup: controlled.lookup)
    async let first: Void = e.find()
    await controlled.waitForCalls(1)
    e.reset()
    controlled.resolve(0, .found(found))
    await first
    #expect(e.currentIcon == "")
    #expect(e.urlText == "")
    #expect(!e.isDirty)
}

@MainActor @Test func typingAURLDebouncesALookup() async throws {
    let controlled = ControlledLookup()
    let e = editor(lookup: controlled.lookup)
    e.debounce = .milliseconds(30)
    e.setURLText("g")
    e.setURLText("github.com")
    // Only the last edit survives the debounce
    #expect(await eventually { !controlled.calls.isEmpty })
    try await Task.sleep(for: .milliseconds(60))
    #expect(controlled.calls == ["github.com"])
    controlled.resolve(0, .found(found))
}

@MainActor @Test func clearingTheURLClearsStatusWithoutSearching() async throws {
    let controlled = ControlledLookup()
    let e = editor(lookup: controlled.lookup)
    e.debounce = .milliseconds(20)
    e.setURLText("   ")
    try await Task.sleep(for: .milliseconds(80))
    #expect(controlled.calls.isEmpty)
    #expect(e.status == "")
}

@MainActor @Test func clearCancelsADebouncedLookup() async throws {
    let controlled = ControlledLookup()
    let e = editor(lookup: controlled.lookup)
    e.debounce = .milliseconds(30)
    e.setURLText("github.com")
    e.clear()
    // The debounced lookup must never start; if it did it would stage the very icon
    // Clear just removed
    try await Task.sleep(for: .milliseconds(90))
    #expect(controlled.calls.isEmpty)
    #expect(e.currentIcon == "")
}

@MainActor @Test func emptyingTheURLInvalidatesAnInFlightSearch() async {
    let controlled = ControlledLookup()
    let e = editor(url: "https://github.com", lookup: controlled.lookup)
    async let first: Void = e.find()
    await controlled.waitForCalls(1)
    e.setURLText("")
    controlled.resolve(0, .found(found))
    await first
    #expect(e.currentIcon == "")
    #expect(e.urlText == "")
    #expect(!e.isSearching)
}

@MainActor @Test func emojiKeepsOnlyTheNewestGrapheme() {
    let e = editor()
    e.setMode(.emoji)
    e.setEmoji("🙂👩‍👩‍👧")
    #expect(e.emojiText == "👩‍👩‍👧")
    #expect(e.currentIcon == "👩‍👩‍👧")
    #expect(e.isDirty)
}

@MainActor @Test func unreachableSaysSo() async {
    let e = editor(lookup: { _ in .unreachable })
    await e.find()
    #expect(e.status == "Couldn't reach the icon service. Check your connection.")
    #expect(!e.isDirty)
}

@MainActor @Test func unchangedWriteBacksAreNotEdits() async throws {
    let controlled = ControlledLookup()
    let e = editor(icon: "🐙", url: "https://github.com", lookup: controlled.lookup)
    e.debounce = .milliseconds(20)
    e.setURLText("github.com")
    e.setEmoji("🐙")
    try await Task.sleep(for: .milliseconds(80))
    #expect(!e.isDirty)
    #expect(controlled.calls.isEmpty)
}
