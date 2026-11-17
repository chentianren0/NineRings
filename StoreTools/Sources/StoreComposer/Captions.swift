import Foundation

/// The captions, read from a String Catalog (`Captions.xcstrings`), in any language it has.
///
/// The catalog is read as the file it is, not through a bundle, so the composer can make every language's pictures in
/// one run. A language without a caption falls back as the App Store's product page does: to the language without its
/// region (`fr-CA` to `fr`), then to the catalog's source language.
public struct CaptionCatalog: Sendable {
    public let sourceLanguage: String
    private let values: [String: [String: String]]

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        sourceLanguage = catalog.sourceLanguage
        var values: [String: [String: String]] = [:]
        for (key, entry) in catalog.strings {
            for (language, localization) in entry.localizations ?? [:] {
                if let value = localization.stringUnit?.value, !value.isEmpty {
                    values[key, default: [:]][language] = value
                }
            }
        }
        self.values = values
    }

    public var keys: [String] { values.keys.sorted() }

    /// The caption `key` in `language`, or its fallback.
    public func text(_ key: String, language: String) -> String? {
        guard let entry = values[key] else { return nil }
        return Self.fallbacks(for: language, source: sourceLanguage).lazy.compactMap { entry[$0] }.first
    }

    /// Whether `key` has its own text in `language`, rather than a fallback's.
    public func isTranslated(_ key: String, into language: String) -> Bool {
        values[key]?[language] != nil
    }

    static func fallbacks(for language: String, source: String) -> [String] {
        var languages = [language]
        // Chinese keeps its script: zh-Hant must not fall back to zh-Hans.
        let parts = language.split(separator: "-")
        if parts.count > 1, !(parts[0] == "zh") {
            languages.append(String(parts[0]))
        }
        languages.append(source)
        return languages
    }

    private struct Catalog: Decodable {
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    private struct Entry: Decodable {
        var localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        var stringUnit: StringUnit?
    }

    private struct StringUnit: Decodable {
        var value: String?
    }
}
