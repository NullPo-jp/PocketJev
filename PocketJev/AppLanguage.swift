import Foundation

enum AppLanguage {
    /// PocketJev intentionally has two UI modes only: Japanese, or English for
    /// every non-Japanese locale. This also follows iOS per-app language when set.
    static var isJapanese: Bool {
        if let preferred = Bundle.main.preferredLocalizations.first {
            return preferred.lowercased().hasPrefix("ja")
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("ja") == true
    }

    static func text(_ japanese: String, _ english: String) -> String {
        isJapanese ? japanese : english
    }
}
