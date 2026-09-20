import OTPCore
import SwiftUI

/// One account in Settings: a summary row, or its edit panel.
///
/// The row's identity in the List is the account's identity, so SwiftUI keeps this
/// view's @State (an open panel, typed-but-unsaved fields, a staged icon) across
/// every unrelated change to the list. That is what the Electron version's
/// captureOpenEdits() machinery had to do by hand.
struct AccountRowView: View {
    let account: Account
    let model: AccountsModel
    var startEditing = false

    @State private var isEditing = false
    @State private var isHovering = false
    @State private var confirmingDelete = false
    @State private var fields = AccountFields()
    @State private var iconEditor: IconEditorModel?
    @State private var error = ""
    @FocusState private var issuerFocused: Bool

    var body: some View {
        Group {
            if isEditing, let iconEditor {
                editPanel(iconEditor)
            } else {
                summary
            }
        }
        .onAppear {
            if startEditing, !isEditing { beginEditing() }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            IconView(icon: account.icon, placeholderSeed: account.issuer.isEmpty ? account.account : account.issuer)
                .modifier(HiddenIconStyle(isHidden: account.hidden, isHovering: isHovering, hasIcon: IconView.hasIcon(account.icon)))
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
            Button {
                report { try model.toggleHidden(account.identity) }
            } label: {
                Image(systemName: account.hidden ? "eye.slash" : "eye").modifier(RowActionPadding())
            }
            .help(account.hidden ? "Show in menu" : "Hide from menu")
            Button(action: beginEditing) {
                Text("Edit").modifier(RowActionPadding())
            }
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "xmark").modifier(RowActionPadding())
            }
            .foregroundStyle(.red)
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .alert("Delete “\(account.label)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                report { try model.delete(account.identity) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its secret is removed from \(AppEnvironment.appName). This can't be undone.")
        }
    }

    private func editPanel(_ iconEditor: IconEditorModel) -> some View {
        @Bindable var fields = fields
        return VStack(alignment: .leading, spacing: 6) {
            TextField("Issuer", text: $fields.issuer)
                .focused($issuerFocused)
            TextField("Account", text: $fields.account)
            TextField("Secret", text: $fields.secret)
            IconEditorView(editor: iconEditor, placeholderSeed: fields.placeholderSeed)
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isEditing = false }
                Button("Save", action: save).buttonStyle(.borderedProminent)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 10)
    }

    private func beginEditing() {
        fields.issuer = account.issuer
        fields.account = account.account
        fields.secret = account.secret
        error = ""
        let fields = fields
        iconEditor = IconEditorModel(
            icon: account.icon,
            url: account.url,
            lookup: model.lookupFavicon,
            label: { (fields.issuer, fields.account) }
        )
        isEditing = true
        // Ready to type, as in Easy OTP. The field exists only after this update.
        DispatchQueue.main.async { issuerFocused = true }
    }

    private func save() {
        guard let iconEditor else { return }
        do {
            try model.saveEdit(
                original: account.identity,
                issuer: fields.issuer,
                account: fields.account,
                secret: fields.secret,
                icon: iconEditor.currentIcon,
                url: iconEditor.currentURL,
                iconUntouched: !iconEditor.isDirty
            )
            isEditing = false
        } catch {
            // ModelError reads as a sentence ("Account and Secret are required.", …)
            self.error = error.localizedDescription
        }
    }
}

/// Breathing room around a row's small borderless buttons (hide, Edit, delete), with a
/// click target that covers it.
struct RowActionPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

/// Settings mirrors the menu for hidden accounts only: their (real) icons are
/// greyed and inverted until the row is hovered, and dimmed either way. A visible
/// account never looks grey in Settings, since it never does in the menu.
struct HiddenIconStyle: ViewModifier {
    let isHidden: Bool
    let isHovering: Bool
    let hasIcon: Bool

    func body(content: Content) -> some View {
        if !isHidden {
            content
        } else if isHovering || !hasIcon {
            content.opacity(0.55)
        } else {
            content.grayscale(1).colorInvert().opacity(0.55)
        }
    }
}
