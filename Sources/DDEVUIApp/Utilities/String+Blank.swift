import Foundation

extension String {
    /// Trims whitespace/newlines and returns `nil` when the result is empty.
    /// Centralised because we want one rule for "what counts as blank" across
    /// parsing, persistence, and the view models.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
