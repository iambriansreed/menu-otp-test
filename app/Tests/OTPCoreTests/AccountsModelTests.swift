import Foundation
import Testing
@testable import OTPCore

/// Stands in for Task.sleep so timer tests decide exactly when each timer fires,
/// instead of racing wall-clock sleeps under a loaded test run.
@MainActor
final class SleepGate {
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    var sleep: @Sendable (Duration) async -> Void {
        { [weak self] _ in
            await withCheckedContinuation { continuation in
                Task { @MainActor in self?.sleepers.append(continuation) }
            }
        }
    }

    func waitForSleepers(_ n: Int) async {
        while sleepers.count < n { await Task.yield() }
    }

    func wake(_ index: Int) {
        sleepers[index].resume()
    }
}

/// Polls `condition` on the main actor for up to ~2 s.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
final class ModelHarness {
    let dir = temporaryDirectory()
    let key = InMemoryKeyProvider()
    var clipboard: [String] = []
    var lookups: [String] = []
    var answers: [String: FaviconResult] = [:]
    /// Lookups with no answer: unreachable when offline, otherwise a real "no icon".
    var offline = false
    var now = Date(timeIntervalSince1970: 1_234_567_890)
    lazy var model: AccountsModel = makeModel()

    var storeURL: URL { dir.appendingPathComponent("accounts.enc") }

    func makeModel() -> AccountsModel {
        AccountsModel(
            store: AccountStore(fileURL: storeURL, keyProvider: key),
            lookupFavicon: { [weak self] source in
                await MainActor.run {
                    guard let self else { return .notFound }
                    self.lookups.append(source)
                    if let found = self.answers[source] { return .found(found) }
                    return self.offline ? .unreachable : .notFound
                }
            },
            copyToClipboard: { [weak self] in self?.clipboard.append($0) },
            now: { [weak self] in self?.now ?? Date() }
        )
    }

    /// What a fresh launch would read back from disk.
    func reloaded() throws -> [Account] {
        try AccountStore(fileURL: storeURL, keyProvider: key).load().accounts
    }
}

private let rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
private let gh = Account(account: "jane", secret: rfcSecret, issuer: "GitHub")
private let aws = Account(account: "root", secret: rfcSecret, issuer: "AWS")
private let icon = FaviconResult(icon: "data:image/png;base64,AA==", domain: "github.com")

@Test func modelErrorsReadAsSentences() {
    #expect(AccountsModel.ModelError.invalidSecret.localizedDescription.contains("base32"))
    #expect(AccountsModel.ModelError.missingFields.localizedDescription == "Account and Secret are required.")
}

@MainActor @Test func copyCodeCopiesTheCurrentCodeAndSetsLastClicked() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    let copied = try #require(h.model.copyCode(for: gh.identity))
    #expect(copied.code == "005924")
    #expect(copied.issuer == "GitHub")
    #expect(h.clipboard == ["005924"])
    #expect(h.model.lastClicked == gh)
}

@MainActor @Test func copyCodeWithBadSecretChangesNothing() throws {
    let h = ModelHarness()
    let bad = Account(account: "x", secret: "NOT BASE32 !!", issuer: "Bad")
    try h.model.mutate { $0.append(bad) }
    #expect(h.model.copyCode(for: bad.identity) == nil)
    #expect(h.clipboard.isEmpty)
    #expect(h.model.lastClicked == nil)
    #expect(h.model.copyCode(for: AccountIdentity(issuer: "nope", account: "nope")) == nil)
}

@MainActor @Test func lastClickedClearsWhenItsOwnTimerFires() async throws {
    let h = ModelHarness()
    let gate = SleepGate()
    h.model.sleep = gate.sleep
    try h.model.add(gh)
    try h.model.add(aws)
    // Each timer registers with the gate from its own task; waiting for the first
    // before starting the second is what makes sleeper 0 gh's and sleeper 1 aws's
    _ = h.model.copyCode(for: gh.identity)
    await gate.waitForSleepers(1)
    _ = h.model.copyCode(for: aws.identity)
    await gate.waitForSleepers(2)

    // gh's timer fires first, but aws owns the header now
    gate.wake(0)
    for _ in 0..<20 { await Task.yield() }
    #expect(h.model.lastClicked == aws)

    gate.wake(1)
    #expect(await eventually { h.model.lastClicked == nil })
}

@MainActor @Test func mutatePersistsAndNotifies() throws {
    let h = ModelHarness()
    var notified = 0
    h.model.onChange = { notified += 1 }
    try h.model.add(gh)
    try h.model.toggleHidden(gh.identity)
    #expect(try h.reloaded() == [Account(account: "jane", secret: rfcSecret, issuer: "GitHub", hidden: true)])
    #expect(notified == 2)
}

@MainActor @Test func mutateThatChangesNothingNeitherSavesNorNotifies() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    var notified = 0
    h.model.onChange = { notified += 1 }
    try FileManager.default.removeItem(at: h.storeURL)
    try h.model.mutate { _ in }
    try h.model.mutate { $0[0].hidden = false }
    #expect(notified == 0)
    #expect(!FileManager.default.fileExists(atPath: h.storeURL.path))
}

@MainActor @Test func mutateRefusesDuplicatesAndLeavesStateAlone() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    #expect(throws: AccountsModel.ModelError.duplicateIdentity) { try h.model.mutate { $0.append(gh) } }
    #expect(h.model.accounts == [gh])
    #expect(try h.reloaded() == [gh])
}

@MainActor @Test func deleteAndMove() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    try h.model.add(aws)
    try h.model.move(fromOffsets: [1], toOffset: 0)
    #expect(h.model.accounts.map(\.issuer) == ["AWS", "GitHub"])
    try h.model.delete(aws.identity)
    #expect(try h.reloaded() == [gh])
}

@MainActor @Test func saveEditValidatesAndBlocksCollisions() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    try h.model.add(aws)
    #expect(throws: AccountsModel.ModelError.missingFields) {
        try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: " ", secret: "ABCD", icon: "", url: "", iconUntouched: true)
    }
    #expect(throws: AccountsModel.ModelError.collision) {
        try h.model.saveEdit(original: gh.identity, issuer: "AWS", account: "root", secret: "ABCD", icon: "", url: "", iconUntouched: true)
    }
    #expect(throws: AccountsModel.ModelError.invalidSecret) {
        try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: "jane", secret: "not base32!", icon: "", url: "", iconUntouched: true)
    }
    try h.model.saveEdit(original: gh.identity, issuer: " GitHub ", account: "jane2", secret: "ab cd", icon: "🐙", url: "https://github.com", iconUntouched: false)
    #expect(h.model.accounts[0] == Account(account: "jane2", secret: "ABCD", issuer: "GitHub", icon: "🐙", url: "https://github.com"))
}

@MainActor @Test func saveEditKeepsHiddenAndMissMarker() throws {
    let h = ModelHarness()
    try h.model.mutate { $0 = [Account(account: "jane", secret: "ABCD", issuer: "GitHub", hidden: true, iconCheckedAt: 7)] }
    try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: "jane", secret: "ABCD", icon: "", url: "", iconUntouched: false)
    #expect(h.model.accounts[0].hidden)
    #expect(h.model.accounts[0].iconCheckedAt == 7)
}

@MainActor @Test func saveEditDropsMissMarkerWhenTheSearchSourceChanges() throws {
    let h = ModelHarness()
    try h.model.mutate { $0 = [Account(account: "jane", secret: "ABCD", issuer: "GitHb", iconCheckedAt: 7)] }
    let typo = AccountIdentity(issuer: "GitHb", account: "jane")
    try h.model.saveEdit(original: typo, issuer: "GitHub", account: "jane", secret: "ABCD", icon: "", url: "", iconUntouched: false)
    #expect(h.model.accounts[0].iconCheckedAt == nil)
    try h.model.mutate { $0[0].iconCheckedAt = 9 }
    try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: "jane", secret: "ABCD", icon: "", url: "https://github.com", iconUntouched: false)
    #expect(h.model.accounts[0].iconCheckedAt == nil)
}

@MainActor @Test func untouchedIconEditorKeepsAnIconFoundAfterThePanelOpened() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    // Backfill lands while the edit panel (staged icon "") is open
    try h.model.mutate { _ = $0.applyIconLookup(gh.identity, result: icon, recordMiss: true, now: Date()) }
    try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: "jane", secret: rfcSecret, icon: "", url: "", iconUntouched: true)
    #expect(h.model.accounts[0].icon == icon.icon)
    // ...but an explicit clear is honoured
    try h.model.saveEdit(original: gh.identity, issuer: "GitHub", account: "jane", secret: rfcSecret, icon: "", url: "", iconUntouched: false)
    #expect(h.model.accounts[0].icon == nil)
}

@MainActor @Test func addUpsertsAndRequiresFields() throws {
    let h = ModelHarness()
    #expect(throws: AccountsModel.ModelError.missingFields) { try h.model.add(Account(account: "", secret: "A", issuer: "")) }
    #expect(throws: AccountsModel.ModelError.invalidSecret) { try h.model.add(Account(account: "x", secret: "189", issuer: "")) }
    try h.model.add(Account(account: "jane", secret: "OLD", issuer: "GitHub", icon: "🐙"))
    let stored = try h.model.add(Account(account: "jane", secret: "NEW", issuer: "GitHub"))
    #expect(stored.icon == "🐙")
    #expect(h.model.accounts.count == 1)
}

@MainActor @Test func importTextPersists() throws {
    let h = ModelHarness()
    let summary = try h.model.importText("otpauth://totp/GitHub:jane?secret=ABCD\nnope")
    #expect(summary.text == "1 added, 1 skipped")
    #expect(try h.reloaded().count == 1)
}

@MainActor @Test func autoFaviconFillsIconWithoutRecordingMisses() async throws {
    let h = ModelHarness()
    h.answers["GitHub"] = icon
    try h.model.add(gh)
    try h.model.add(aws)
    #expect(await h.model.autoFavicon(for: gh.identity))
    #expect(h.model.accounts[0].icon == icon.icon)
    #expect(h.model.accounts[0].url == "github.com")
    #expect(!(await h.model.autoFavicon(for: aws.identity)))
    #expect(h.model.accounts[1].iconCheckedAt == nil)
}

@MainActor @Test func backfillRecordsMissesAndSkipsThemUntilTTL() async throws {
    let h = ModelHarness()
    h.answers["GitHub"] = icon
    try h.model.add(gh)
    try h.model.add(aws)
    let first = await h.model.backfillIcons()
    #expect(first.found == 1 && first.wanted == 2)
    #expect(try h.reloaded()[1].iconCheckedAt == h.now.timeIntervalSince1970 * 1000)

    h.lookups = []
    _ = await h.model.backfillIcons()
    #expect(h.lookups.isEmpty)

    h.now += IconBackfill.missTTL + 1
    _ = await h.model.backfillIcons()
    #expect(h.lookups == ["AWS"])
}

@MainActor @Test func offlineBackfillRecordsNoMiss() async throws {
    let h = ModelHarness()
    h.offline = true
    try h.model.add(aws)
    let result = await h.model.backfillIcons()
    #expect(result.found == 0 && result.wanted == 1)
    #expect(h.model.accounts[0].iconCheckedAt == nil)
    // So the next launch asks again
    h.lookups = []
    h.offline = false
    _ = await h.model.backfillIcons()
    #expect(h.lookups == ["AWS"])
    #expect(h.model.accounts[0].iconCheckedAt != nil)
}

@MainActor @Test func loadReportsASetAsideFile() throws {
    let h = ModelHarness()
    try h.model.add(gh)
    // Another key can't decrypt it, so the file is moved aside and reported
    let other = AccountsModel(
        store: AccountStore(fileURL: h.storeURL, keyProvider: InMemoryKeyProvider()),
        lookupFavicon: { _ in .notFound }, copyToClipboard: { _ in }
    )
    let aside = try #require(try other.load())
    #expect(aside.lastPathComponent.hasPrefix("accounts.enc.unreadable-"))
    #expect(other.accounts.isEmpty)
    #expect(try h.model.load() == nil)
}

@MainActor @Test func fillMissingIconsReportsProgress() async throws {
    let h = ModelHarness()
    h.answers["GitHub"] = icon
    try h.model.add(gh)
    try h.model.add(aws)
    var progress: [Int] = []
    let found = await h.model.fillMissingIcons(h.model.accounts.map(\.identity)) { done, total in
        #expect(total == 2)
        progress.append(done)
    }
    #expect(found == 1)
    #expect(progress == [1, 2])
    #expect(h.model.accounts[1].iconCheckedAt == nil)
}

@MainActor @Test func loadDemoReadsURLsWithoutSaving() throws {
    let h = ModelHarness()
    h.model.loadDemo(fromText: "otpauth://totp/GitHub:jane?secret=ABCD\n\notpauth://totp/AWS:root?secret=ABCD")
    #expect(h.model.accounts.count == 2)
    #expect(!FileManager.default.fileExists(atPath: h.storeURL.path))
}
