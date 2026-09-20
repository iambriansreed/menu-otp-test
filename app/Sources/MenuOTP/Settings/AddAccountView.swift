import AppKit
import OTPCore
import SwiftUI
import UniformTypeIdentifiers

struct AddAccountView: View {
    enum Tab: Hashable {
        case url
        case manual
        case importFile
    }

    let model: AccountsModel

    @State private var tab: Tab
    @State private var otpURL = ""
    @State private var fields: AccountFields
    @State private var manualIconEditor: IconEditorModel
    @State private var error = ""
    @State private var importResult = ""
    @State private var isDropTargeted = false
    @State private var choosingFile: Bool

    init(model: AccountsModel, initialTab: Tab = .url, openFilePicker: Bool = false) {
        self.model = model
        _tab = State(initialValue: initialTab)
        _choosingFile = State(initialValue: openFilePicker)
        // Built here rather than in onAppear: creating it mid-layout and inserting
        // the editor on the next pass sends SwiftUI round an AttributeGraph cycle
        let fields = AccountFields()
        _fields = State(initialValue: fields)
        _manualIconEditor = State(initialValue: IconEditorModel(
            icon: nil, url: nil, lookup: model.lookupFavicon,
            label: { (fields.issuer, fields.account) }
        ))
    }

    var body: some View {
        @Bindable var fields = fields
        VStack(alignment: .leading, spacing: 8) {
            Picker("Add from", selection: $tab) {
                Text("From URL").tag(Tab.url)
                Text("Manual").tag(Tab.manual)
                Text("Import File").tag(Tab.importFile)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: tab) {
                // Messages belong to the tab that produced them
                error = ""
                importResult = ""
            }

            switch tab {
            case .url:
                TextField("otpauth://totp/Issuer:Account?secret=...", text: $otpURL)
                    .onSubmit(add)
            case .manual:
                TextField("Issuer", text: $fields.issuer).onSubmit(add)
                TextField("Account", text: $fields.account).onSubmit(add)
                TextField("Secret", text: $fields.secret).onSubmit(add)
                IconEditorView(editor: manualIconEditor, placeholderSeed: fields.placeholderSeed)
            case .importFile:
                importDropZone
                if !importResult.isEmpty {
                    Text(importResult).font(.caption).foregroundStyle(.secondary)
                }
            }

            if tab != .importFile {
                HStack(spacing: 10) {
                    Spacer()
                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button("Add Account", action: add).buttonStyle(.borderedProminent)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 4)
        // A sheet on the Settings window (same window, same Space), not a free-floating
        // panel. Any file with data in it: the contents decide what imports.
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { importFile(url) }
        }
    }

    private var importDropZone: some View {
        let tint = isDropTargeted ? Color.accentColor : Color.secondary
        return Button { choosingFile = true } label: {
            Text("Click or drop a file — one otpauth:// URL per line")
                .frame(maxWidth: .infinity)
                .padding(20)
                .foregroundStyle(tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importFile(url) }
            }
            return true
        }
    }

    private func add() {
        let entry: Account
        switch tab {
        case .url:
            guard let parsed = OTPAuthURL.parse(otpURL) else {
                error = "Invalid otpauth:// URL."
                return
            }
            guard !parsed.account.isEmpty else {
                error = "That URL has no account name."
                return
            }
            entry = parsed
        case .manual:
            let account = fields.account.trimmed
            let secret = Account.normalizeSecret(fields.secret)
            guard !account.isEmpty, !secret.isEmpty else {
                error = "Account and Secret are required."
                return
            }
            entry = Account(
                account: account,
                secret: secret,
                issuer: fields.issuer.trimmed,
                icon: manualIconEditor.currentIcon.nilIfEmpty,
                url: manualIconEditor.currentURL.nilIfEmpty
            )
        case .importFile:
            return
        }

        do {
            let stored = try model.add(entry)
            error = ""
            if tab == .url {
                otpURL = ""
            } else {
                fields.clear()
                manualIconEditor.reset()
            }
            // No icon given: look one up from the URL/issuer
            Task { await model.autoFavicon(for: stored.identity) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// UTF-8, or UTF-16 with a byte-order mark; anything else is decoded lossily, so
    /// an unexpected file imports as skipped lines instead of failing outright.
    static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func importFile(_ url: URL) {
        // A file chosen in the picker comes with security-scoped access, which is only
        // good while held; read it up front
        let scoped = url.startAccessingSecurityScopedResource()
        let data = Result { try Data(contentsOf: url) }
        if scoped { url.stopAccessingSecurityScopedResource() }
        Task {
            do {
                let text = Self.decodeText(try data.get())
                let summary = try model.importText(text)
                importResult = summary.text
                _ = await model.fillMissingIcons(summary.imported) { done, total in
                    importResult = "\(summary.text) — looking up icons \(done)/\(total)…"
                }
                importResult = summary.text
            } catch {
                importResult = "Couldn't import: \(error.localizedDescription)"
            }
        }
    }
}
