import AppKit

/// Writes a code to the general pasteboard with the nspasteboard.org markers that
/// clipboard managers honour: Concealed (sensitive, don't show it) and Transient
/// (don't record it in history at all).
enum Clipboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func copy(_ string: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.declareTypes([.string, concealedType, transientType], owner: nil)
        pasteboard.setString(string, forType: .string)
        pasteboard.setString("", forType: concealedType)
        pasteboard.setString("", forType: transientType)
    }

    /// Every item and type on the pasteboard, so a demo test run can put back
    /// exactly what the user had (not a string-only copy marked concealed).
    static func snapshot(_ pasteboard: NSPasteboard = .general) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
