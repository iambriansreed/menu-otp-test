import Foundation
import Observation

/// The app's single source of truth for accounts, shared by the popover and the
/// Settings window. Every change goes through `mutate`, which validates, persists,
/// then publishes.
///
/// Because both windows read this one object, the Electron app's cross-process
/// machinery (pushing backfilled icons to Settings over IPC, re-applying pending
/// icons on save, capturing open edits before a re-render) has nothing to do here.
@Observable
@MainActor
public final class AccountsModel {
    public private(set) var accounts: [Account] = []
    public private(set) var lastClicked: Account?

    /// Called after every published change; the popover uses it to re-measure.
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public var lastClickedClearDelay: Duration = .seconds(60)
    /// How the "Last clicked" timer waits. Tests swap in a gate to fire it on cue
    /// instead of racing wall-clock sleeps.
    @ObservationIgnored public var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    @ObservationIgnored public let lookupFavicon: @Sendable (String) async -> FaviconOutcome

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let copyToClipboard: (String) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastClickedToken = 0

    public enum ModelError: LocalizedError, Equatable {
        case duplicateIdentity
        case missingFields
        case invalidSecret
        case collision
        case notFound

        public var errorDescription: String? {
            switch self {
            case .duplicateIdentity: "Two accounts can't have the same issuer and account."
            case .missingFields: "Account and Secret are required."
            case .invalidSecret: "The secret isn't valid base32 (letters A–Z and digits 2–7)."
            case .collision: "Another account already has this issuer and account."
            case .notFound: "That account no longer exists."
            }
        }
    }

    public init(
        store: AccountStore,
        lookupFavicon: @escaping @Sendable (String) async -> FaviconOutcome,
        copyToClipboard: @escaping (String) -> Void,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.lookupFavicon = lookupFavicon
        self.copyToClipboard = copyToClipboard
        self.now = now
    }

    /// Returns where an unreadable accounts file was moved, if that happened, so the
    /// app can tell the user rather than silently starting empty.
    @discardableResult
    public func load() throws -> URL? {
        let loaded = try store.load()
        accounts = loaded.accounts
        onChange?()
        return loaded.setAside
    }

    /// Demo mode: accounts come from a file of otpauth:// URLs and aren't saved
    /// until the user changes something (then they go to the demo data directory).
    public func loadDemo(fromText text: String) {
        var list: [Account] = []
        _ = list.importLines(text)
        accounts = list
        onChange?()
    }

    /// Applies `change` to a copy, refuses duplicate identities, saves, then publishes.
    /// On any throw nothing is published and the file is untouched. A change that
    /// changes nothing (say, a lookup for an account that got an icon meanwhile) is
    /// neither saved nor published, so it can't reset the open menu's highlight.
    public func mutate(_ change: (inout [Account]) throws -> Void) throws {
        var next = accounts
        try change(&next)
        guard next != accounts else { return }
        guard !next.hasDuplicateIdentities else { throw ModelError.duplicateIdentity }
        try store.save(next)
        accounts = next
        onChange?()
    }

    // MARK: Popover

    /// Generates the code and hands it to the clipboard. Computed before any state
    /// changes: a malformed secret throws in TOTP.code and returns nil here, with no
    /// "Last clicked" header for a copy that never happened.
    public func copyCode(for identity: AccountIdentity) -> (issuer: String, code: String)? {
        guard let account = accounts.account(for: identity),
              let code = try? TOTP.code(secret: account.secret, at: now())
        else { return nil }
        copyToClipboard(code)

        lastClicked = account
        lastClickedToken += 1
        let token = lastClickedToken
        let delay = lastClickedClearDelay
        let sleep = sleep
        Task { @MainActor [weak self] in
            await sleep(delay)
            // A later click owns the header now; leave it alone
            guard let self, self.lastClickedToken == token else { return }
            self.lastClicked = nil
            self.onChange?()
        }
        onChange?()
        return (account.issuer.isEmpty ? account.account : account.issuer, code)
    }

    // MARK: Settings

    public func toggleHidden(_ identity: AccountIdentity) throws {
        try mutate { list in
            guard let i = list.index(of: identity) else { throw ModelError.notFound }
            list[i].hidden.toggle()
        }
    }

    public func delete(_ identity: AccountIdentity) throws {
        try mutate { list in
            guard let i = list.index(of: identity) else { throw ModelError.notFound }
            list.remove(at: i)
        }
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        try mutate { $0.moveAccounts(fromOffsets: source, toOffset: destination) }
    }

    /// Saves an account's edit panel. `icon`/`url` are the icon editor's staged
    /// values; when `iconUntouched` is true they're ignored in favour of whatever the
    /// account has *now*, so an icon the launch backfill found after the panel opened
    /// isn't wiped by a save that never touched the icon.
    public func saveEdit(
        original: AccountIdentity,
        issuer rawIssuer: String,
        account rawAccount: String,
        secret rawSecret: String,
        icon: String,
        url: String,
        iconUntouched: Bool
    ) throws {
        let issuer = rawIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountName = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = Account.normalizeSecret(rawSecret)
        guard !accountName.isEmpty, !secret.isEmpty else { throw ModelError.missingFields }
        guard Account.isValidSecret(secret) else { throw ModelError.invalidSecret }

        try mutate { list in
            guard let i = list.index(of: original) else { throw ModelError.notFound }
            let newIdentity = AccountIdentity(issuer: issuer, account: accountName)
            // Editing has no natural "merge" outcome: two rows claiming one identity
            // would make clicks, backfill and lookups all resolve to the first.
            if list.indices.contains(where: { $0 != i && list[$0].identity == newIdentity }) {
                throw ModelError.collision
            }
            let current = list[i]
            var edited = Account(
                account: accountName,
                secret: secret,
                issuer: issuer,
                icon: iconUntouched ? nonEmpty(current.icon) : nonEmpty(icon),
                url: iconUntouched ? nonEmpty(current.url) : nonEmpty(url),
                hidden: current.hidden
            )
            // A remembered miss only applies to what was searched for. With no icon
            // and the same search source it carries over; a new source gets a fresh
            // lookup at the next launch.
            if edited.hasNoIcon, edited.faviconSource == current.faviconSource {
                edited.iconCheckedAt = current.iconCheckedAt
            }
            list[i] = edited
        }
    }

    /// Add Account (URL or manual form): upsert, returning the account as stored.
    @discardableResult
    public func add(_ entry: Account) throws -> Account {
        guard !entry.account.isEmpty, !entry.secret.isEmpty else { throw ModelError.missingFields }
        guard Account.isValidSecret(entry.secret) else { throw ModelError.invalidSecret }
        var stored = entry
        try mutate { stored = $0.upsert(entry).account }
        return stored
    }

    public func importText(_ text: String) throws -> ImportSummary {
        var summary = ImportSummary()
        try mutate { summary = $0.importLines(text) }
        return summary
    }

    /// Settings' post-add lookup: fills the icon if the account still has none.
    /// A miss is not recorded (only the launch backfill stamps iconCheckedAt).
    @discardableResult
    public func autoFavicon(for identity: AccountIdentity) async -> Bool {
        guard let account = accounts.account(for: identity), account.canLookUpIcon else { return false }
        let outcome = await lookupFavicon(account.faviconSource)
        return apply(identity, outcome: outcome, recordMiss: false)
    }

    /// "Find Missing Icons" and the post-import pass: every listed account that still
    /// has no icon, 4 at a time. Returns how many were found.
    public func fillMissingIcons(
        _ identities: [AccountIdentity],
        progress: @escaping @MainActor (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async -> Int {
        let items = identities.compactMap { id -> (AccountIdentity, String)? in
            guard let a = accounts.account(for: id), a.canLookUpIcon else { return nil }
            return (id, a.faviconSource)
        }
        return await runLookups(items, recordMiss: false, progress: progress)
    }

    /// Launch-time backfill: icon-less accounts whose last miss is older than
    /// `IconBackfill.missTTL`. Only a real "no icon" answer is recorded as a miss; an
    /// unreachable service (offline at login, say) leaves the account to be retried
    /// at the next launch rather than skipped for a week.
    @discardableResult
    public func backfillIcons() async -> (found: Int, wanted: Int) {
        let items = accounts
            .filter { IconBackfill.needsLookup($0, now: now()) }
            .map { ($0.identity, $0.faviconSource) }
        let found = await runLookups(items, recordMiss: true, progress: { _, _ in })
        return (found, items.count)
    }

    private func runLookups(
        _ items: [(AccountIdentity, String)],
        recordMiss: Bool,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> Int {
        let total = items.count
        guard total > 0 else { return 0 }
        let counter = LookupCounter()
        await IconBackfill.run(items, lookup: lookupFavicon) { [weak self] identity, outcome in
            await MainActor.run {
                guard let self else { return }
                if self.apply(identity, outcome: outcome, recordMiss: recordMiss), outcome.result != nil {
                    counter.found += 1
                }
                counter.done += 1
                progress(counter.done, total)
            }
        }
        return counter.found
    }

    /// Re-finds the account by identity (the list may have changed during the await)
    /// and saves right away, so each hit survives a quit part-way through a batch.
    @discardableResult
    private func apply(_ identity: AccountIdentity, outcome: FaviconOutcome, recordMiss: Bool) -> Bool {
        var changed = false
        do {
            try mutate {
                changed = $0.applyIconLookup(
                    identity,
                    result: outcome.result,
                    recordMiss: recordMiss && outcome == .notFound,
                    now: now()
                )
            }
        } catch {
            return false
        }
        return changed
    }
}

/// Only touched on the main actor (inside MainActor.run above).
private final class LookupCounter: @unchecked Sendable {
    var done = 0
    var found = 0
}
