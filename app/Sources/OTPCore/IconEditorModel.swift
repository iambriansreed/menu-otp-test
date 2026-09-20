import Foundation
import Observation

/// State behind one icon editor (an account's edit panel, or the manual Add form):
/// favicon/emoji mode, the URL field with its debounced lookup, the staged icon,
/// and the status line.
@Observable
@MainActor
public final class IconEditorModel {
    public enum Mode: Hashable, Sendable {
        case favicon
        case emoji
    }

    public private(set) var mode: Mode
    public private(set) var urlText: String
    public private(set) var emojiText: String
    public private(set) var pendingImage: String?
    public private(set) var status = ""
    public private(set) var isSearching = false
    /// False until the user does anything icon-related. See AccountsModel.saveEdit.
    public private(set) var isDirty = false

    @ObservationIgnored public var debounce: Duration = .milliseconds(600)
    @ObservationIgnored private let lookup: @Sendable (String) async -> FaviconOutcome
    @ObservationIgnored private let label: @MainActor () -> (issuer: String, account: String)
    /// Bumped by every search, clear and reset; a lookup whose number is stale when
    /// it finishes was superseded and must not touch any state.
    @ObservationIgnored private var searchSeq = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    public init(
        icon: String?,
        url: String?,
        lookup: @escaping @Sendable (String) async -> FaviconOutcome,
        label: @escaping @MainActor () -> (issuer: String, account: String)
    ) {
        let isImage = AccountIcon.isImage(icon)
        self.lookup = lookup
        self.label = label
        pendingImage = isImage ? icon : nil
        mode = isImage || (icon ?? "").isEmpty ? .favicon : .emoji
        emojiText = isImage ? "" : (icon ?? "")
        urlText = Self.stripScheme(url ?? "")

        // A favicon found before URLs were stored: show the domain the original
        // lookup would have used.
        if isImage, urlText.isEmpty {
            let l = label()
            let seed = [l.issuer, l.account].map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
            urlText = IssuerDomains.domains(for: seed).first ?? ""
        }
    }

    public var currentIcon: String {
        mode == .emoji ? emojiText.trimmingCharacters(in: .whitespaces) : (pendingImage ?? "")
    }

    public var currentURL: String {
        let raw = Self.stripScheme(urlText.trimmingCharacters(in: .whitespaces))
        return raw.isEmpty ? "" : "https://\(raw)"
    }

    public func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        isDirty = true
    }

    /// Keeps a single grapheme (an emoji with modifiers is one Character): the
    /// *last* one, i.e. the newest pick. (The Electron app kept the first, so picking
    /// a second emoji silently did nothing until the field was cleared.)
    public func setEmoji(_ text: String) {
        let newest = text.last.map { String($0) } ?? ""
        // SwiftUI can write a binding back unchanged; that isn't an edit
        guard newest != emojiText else { return }
        emojiText = newest
        isDirty = true
    }

    /// Typing in the URL field: debounce a lookup. Clearing the field clears the
    /// status and does *not* search (that would fall back to the issuer and refill
    /// the field the user just emptied).
    public func setURLText(_ text: String) {
        // An unchanged write-back must not restart the debounce or mark the editor dirty
        guard text != urlText else { return }
        urlText = text
        isDirty = true
        debounceTask?.cancel()
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            // Cancelling the debounce doesn't stop a lookup already in flight, and
            // that one would stage an icon (and refill this field with its domain)
            // for a URL the user has just emptied
            searchSeq += 1
            isSearching = false
            status = ""
            return
        }
        let delay = debounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.find()
        }
    }

    /// The magnifier button. The URL field wins over guessing from the name.
    public func find() async {
        let explicit = urlText.trimmingCharacters(in: .whitespaces)
        let l = label()
        let source = [explicit, l.issuer, l.account]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !source.isEmpty else {
            status = "Enter a website URL or issuer first."
            return
        }
        searchSeq += 1
        let seq = searchSeq
        isSearching = true
        status = "Searching…"
        let outcome = await lookup(source)
        guard seq == searchSeq else { return }
        isSearching = false
        switch outcome {
        case .found(let result):
            pendingImage = result.icon
            if explicit.isEmpty { urlText = result.domain }
            status = "Found — save to keep it."
            isDirty = true
        case .notFound:
            status = "No favicon found."
        case .unreachable:
            status = "Couldn't reach the icon service. Check your connection."
        }
    }

    public func clear() {
        searchSeq += 1
        // Bumping the sequence only invalidates a lookup that has already started;
        // a debounced one hasn't, so it would start *after* the clear and re-stage
        // the icon the user just removed
        debounceTask?.cancel()
        isSearching = false
        pendingImage = nil
        emojiText = ""
        status = ""
        isDirty = true
    }

    /// After the manual Add form submits. Invalidates any in-flight lookup so a stale
    /// favicon can't attach to the next account typed in.
    public func reset() {
        searchSeq += 1
        debounceTask?.cancel()
        pendingImage = nil
        mode = .favicon
        emojiText = ""
        urlText = ""
        status = ""
        isSearching = false
        isDirty = false
    }

    static func stripScheme(_ url: String) -> String {
        url.replacingOccurrences(of: "^https?://", with: "", options: [.regularExpression, .caseInsensitive])
    }
}
