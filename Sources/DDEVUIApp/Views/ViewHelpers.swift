import AppKit
import SwiftUI

/// Shared UI helpers that de-duplicate boilerplate repeated across the views (audit L11).
enum Pasteboard {
    /// Replaces the pasteboard contents with `string`.
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension Binding {
    /// A `Bool` binding that is `true` while `optional` is non-nil and clears it when set to
    /// `false`. Replaces the repeated `Binding(get: { x != nil }, set: { if !$0 { x = nil } })`
    /// used to drive confirmation dialogs / sheets from an optional item.
    static func isPresent<Wrapped: Sendable>(_ optional: Binding<Wrapped?>) -> Binding<Bool> where Value == Bool {
        Binding<Bool>(
            get: { optional.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { optional.wrappedValue = nil }
            }
        )
    }
}

extension View {
    /// The uppercase, secondary, kerned section-header treatment used throughout the inspector
    /// panels. Previously copy-pasted at ~13 sites.
    func sectionHeaderStyle() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}
