import Foundation

/// Minimum identity required by conversion validation and destination naming.
/// Provider artwork, synopsis and cast are optional and are not invented here.
public struct ManualMovieMetadata: Codable, Equatable, Sendable {
    public let title: String
    public let year: Int

    public init(title: String, year: Int) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AutomationServiceError.message("Le titre est obligatoire et ne doit pas contenir de caractères de contrôle.")
        }
        guard (1000...9999).contains(year) else {
            throw AutomationServiceError.message("L’année de sortie doit comporter exactement quatre chiffres (1000–9999).")
        }
        self.title = title; self.year = year
    }

    public static func parse(title: String, year: String) throws -> Self {
        let digits = year.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 4, digits.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(digits) else {
            throw AutomationServiceError.message("Renseignez l’année de sortie avec quatre chiffres, par exemple 2024.")
        }
        return try Self(title: title, year: number)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(title: values.decode(String.self, forKey: .title), year: values.decode(Int.self, forKey: .year))
    }
}
