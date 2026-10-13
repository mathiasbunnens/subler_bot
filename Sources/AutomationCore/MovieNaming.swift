import Foundation

public enum MovieNaming {
    public static func name(title: String, year: Int) -> String {
        var cleaned = title.precomposedStringWithCanonicalMapping
        for character in ["/", ":", "\\"] { cleaned = cleaned.replacingOccurrences(of: character, with: "-") }
        cleaned = cleaned.components(separatedBy: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "?*\"<>|"))).joined()
        cleaned = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Leave room for year, extension and the transfer's UUID suffix.
        while cleaned.decomposedStringWithCanonicalMapping.utf8.count > 160 { cleaned.removeLast() }
        return "\(cleaned.isEmpty ? "Film" : cleaned) (\(year))"
    }
}
