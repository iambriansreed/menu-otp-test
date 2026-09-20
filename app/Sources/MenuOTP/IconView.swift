import AppKit
import OTPCore
import SwiftUI

/// An account icon: a favicon on a white tile, an emoji, or (Settings only, when
/// `placeholderSeed` is given) a letter placeholder. With no icon and no seed it
/// draws nothing, so a menu row's label starts at the row's padding.
struct IconView: View {
    let icon: String?
    var placeholderSeed: String?
    var size: CGFloat = 18

    var body: some View {
        switch AccountIcon(icon) {
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(1)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.white))
            } else {
                placeholder
            }
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: size - 2))
                .frame(width: size, height: size)
        case .none:
            placeholder
        }
    }

    @ViewBuilder private var placeholder: some View {
        if let seed = placeholderSeed {
            // Character, not unicode scalar: an issuer starting with an emoji or other
            // multi-scalar grapheme takes the whole thing
            let letter = seed.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
            Text(letter)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    static func hasIcon(_ icon: String?) -> Bool {
        AccountIcon(icon) != .none
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
