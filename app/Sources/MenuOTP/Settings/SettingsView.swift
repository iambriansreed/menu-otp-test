import AppKit
import OTPCore
import ServiceManagement
import SwiftUI

/// Issuer/account/secret text for an edit panel or the manual Add form. A class so
/// an IconEditorModel's `label` closure can read the live values.
@Observable
final class AccountFields {
    var issuer = ""
    var account = ""
    var secret = ""

    func clear() {
        issuer = ""
        account = ""
        secret = ""
    }

    /// Letter-placeholder seed: issuer, else account.
    var placeholderSeed: String { issuer.trimmed.isEmpty ? account : issuer }
}

struct SettingsView: View {
    struct InitialState {
        var editing: AccountIdentity?
        var addTab: AddAccountView.Tab = .url
        var reordering = false
        /// Test hook: open Import's file picker as soon as the window appears.
        var openFilePicker = false
    }

    let model: AccountsModel
    let loginItem: LoginItem
    let initial: InitialState
    @State private var reordering: Bool

    init(model: AccountsModel, loginItem: LoginItem, initial: InitialState = InitialState()) {
        self.model = model
        self.loginItem = loginItem
        self.initial = initial
        _reordering = State(initialValue: initial.reordering)
    }

    var body: some View {
        Group {
            if reordering {
                reorderView
            } else {
                mainView
            }
        }
        .frame(minWidth: 380, minHeight: 400)
    }

    /// Not a List: on macOS a List holds every click on a text field in one of its
    /// rows for the double-click interval (0.5 s by default) before the field gets
    /// focus, which made the edit panel and the Add Account form feel sluggish.
    private var mainView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection("Accounts") {
                    if model.accounts.count > 1 {
                        Button("Reorder") { reordering = true }
                            .controlSize(.small)
                            .help("Drag accounts into the order the menu shows them")
                    }
                } content: {
                    VStack(spacing: 0) {
                        if model.accounts.isEmpty {
                            Text("No accounts added yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        ForEach(Array(model.accounts.enumerated()), id: \.element.identity) { index, account in
                            if index > 0 { Divider().padding(.leading, 10) }
                            AccountRowView(account: account, model: model, startEditing: initial.editing == account.identity)
                                .padding(.horizontal, 10)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                    BulkIconsRow(model: model)
                }

                SettingsSection("Add Account") {
                    AddAccountView(model: model, initialTab: initial.addTab, openFilePicker: initial.openFilePicker)
                }

                SettingsSection("General") {
                    LoginItemRow(loginItem: loginItem)
                }

                // The same version and build the About panel shows, where someone
                // reporting a problem will actually look for it
                if let version = AppEnvironment.versionText {
                    Text("\(AppEnvironment.appName) \(version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    /// Reorder mode uses a real List for its native drag and drop: the dragged row
    /// lifts and follows the pointer, an insertion line shows where it will land, and
    /// the list scrolls at its edges. A List is safe here and only here, because this
    /// mode shows no text fields for its click delay to affect.
    private var reorderView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Drag accounts into the order the menu shows them.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { reordering = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
            List {
                ForEach(model.accounts, id: \.identity) { account in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        IconView(icon: account.icon, placeholderSeed: account.issuer.isEmpty ? account.account : account.issuer)
                        Text(account.label)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(account.hidden ? 0.55 : 1)
                        Spacer(minLength: 4)
                        if account.hidden {
                            Text("HIDDEN")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onMove { source, destination in
                    report { try model.move(fromOffsets: source, toOffset: destination) }
                }
            }
            .listStyle(.inset)
        }
    }
}

/// A titled group, styled like the inset List sections this window used to use,
/// with an optional control at the right of the title.
struct SettingsSection<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            content
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// Runs a model mutation from a button, showing any failure (a disk or Keychain
/// error while saving) instead of swallowing it.
@MainActor
func report(_ action: () throws -> Void) {
    do {
        try action()
    } catch {
        NSApp.presentError(error)
    }
}

struct BulkIconsRow: View {
    let model: AccountsModel
    @State private var status = ""
    @State private var success = false
    @State private var running = false

    private var anyMissing: Bool { model.accounts.contains(where: \.hasNoIcon) }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(success ? Color.green : Color.secondary)
            }
            // Nothing to find once every account has an icon; the status stays so a
            // "Found N of M." is still readable after the button disappears
            if anyMissing {
                Button("Find Missing Icons", action: run).disabled(running)
            }
        }
        .onChange(of: anyMissing) { _, nowMissing in
            // New work appeared: the old result no longer describes the list
            if nowMissing, !running {
                status = ""
                success = false
            }
        }
    }

    private func run() {
        let targets = model.accounts.filter(\.hasNoIcon).map(\.identity)
        running = true
        success = false
        status = "Looking up icons 0/\(targets.count)…"
        Task {
            let found = await model.fillMissingIcons(targets) { done, total in
                status = "Looking up icons \(done)/\(total)…"
            }
            running = false
            success = !anyMissing
            status = found > 0 ? "Found \(found) of \(targets.count)." : "No favicons found."
        }
    }
}

struct LoginItemRow: View {
    let loginItem: LoginItem
    @State private var isOn = false
    @State private var needsApproval = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at login", isOn: Binding(get: { isOn }, set: { set($0) }))
            if needsApproval {
                HStack(spacing: 4) {
                    Text("Allow it in System Settings → General → Login Items.")
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        needsApproval = loginItem.needsApproval
        isOn = loginItem.isEnabled || needsApproval
    }

    private func set(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}
