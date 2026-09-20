import AppKit
import OTPCore
import SwiftUI

/// Favicon/emoji picker shared by the edit panel and the manual Add form. All state
/// lives in IconEditorModel; this only draws it and forwards input.
struct IconEditorView: View {
    let editor: IconEditorModel
    let placeholderSeed: String

    @FocusState private var emojiFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Always drawn in the highlighted state, i.e. as the menu will show
                // it when the row is pointed at
                IconView(icon: editor.currentIcon, placeholderSeed: placeholderSeed)
                Picker("Icon", selection: Binding(get: { editor.mode }, set: setMode)) {
                    Text("Favicon").tag(IconEditorModel.Mode.favicon)
                    Text("Emoji").tag(IconEditorModel.Mode.emoji)
                }
                .labelsHidden()
                .fixedSize()

                switch editor.mode {
                case .favicon:
                    HStack(spacing: 2) {
                        Text("https://").foregroundStyle(.secondary)
                        TextField("example.com", text: Binding(get: { editor.urlText }, set: editor.setURLText))
                    }
                    Button {
                        Task { await editor.find() }
                    } label: {
                        if editor.isSearching {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .help("Find favicon")
                    .disabled(editor.isSearching)
                case .emoji:
                    TextField("🙂", text: Binding(get: { editor.emojiText }, set: editor.setEmoji))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .focused($emojiFocused)
                    Button(action: openEmojiPicker) {
                        Image(systemName: "face.smiling")
                    }
                    .help("Open the emoji picker")
                    Spacer(minLength: 0)
                }

                Button(action: editor.clear) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear icon")
            }
            if !editor.status.isEmpty {
                Text(editor.status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setMode(_ mode: IconEditorModel.Mode) {
        editor.setMode(mode)
        if mode == .emoji { openEmojiPicker() }
    }

    private func openEmojiPicker() {
        emojiFocused = true
        // The character palette types into the first responder: let focus land first
        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
    }
}
