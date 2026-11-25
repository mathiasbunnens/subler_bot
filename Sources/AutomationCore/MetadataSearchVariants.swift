import Foundation

/// Fallback provider queries for a release whose engine-derived search returned nothing.
/// TheMovieDB requires every query word to match, so one parasitic token (a sequel number the
/// release added, a trailing word) yields zero results. Variants are deterministic, bounded,
/// and only widen the SEARCH: automatic selection keeps MetadataMatching's strict title/year rules.
public enum MetadataSearchVariants {
    public static let maximumCount = 6

    public static func variants(sourceName: String) -> [String] {
        let stem = ((sourceName as NSString).deletingPathExtension)
            .replacingOccurrences(of: "[._]", with: " ", options: .regularExpression)
        var prefix = stem
        if let (_, range) = MetadataMatching.explicitYear(in: stem) { prefix = String(stem[..<range.lowerBound]) }
        var aliases: [String] = []
        if let groups = try? NSRegularExpression(pattern: "\\(([^()]*)\\)|\\[([^\\[\\]]*)\\]") {
            for match in groups.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)).reversed() {
                for group in 1...2 where match.range(at: group).location != NSNotFound {
                    if let aliasRange = Range(match.range(at: group), in: prefix) { aliases.insert(String(prefix[aliasRange]), at: 0) }
                }
                if let fullRange = Range(match.range, in: prefix) { prefix.replaceSubrange(fullRange, with: " ") }
            }
        }
        var words = titleWords(prefix)
        // Without an explicit year the title ends at the first release descriptor.
        if MetadataMatching.explicitYear(in: stem) == nil,
           let cut = words.firstIndex(where: { !$0.allSatisfy(\.isNumber) && MetadataMatching.isReleaseDescriptor($0) }) {
            words = Array(words[..<cut])
        }
        while let last = words.last, MetadataMatching.isReleaseDescriptor(last) { words.removeLast() }
        let withoutSequel = words.indices.filter { !MetadataMatching.isInnerSequelNumber(words, at: $0) }.map { words[$0] }

        var result: [String] = []
        func add(_ tokens: [String]) {
            let query = tokens.joined(separator: " ")
            guard !query.isEmpty, result.count < maximumCount,
                  !result.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) else { return }
            result.append(query)
        }
        add(withoutSequel)
        add(words)
        for alias in aliases { add(titleWords(alias)) }
        // Drop trailing words one at a time, keeping at least two words of the title.
        var shortened = withoutSequel
        while shortened.count > 2 { shortened.removeLast(); add(shortened) }
        return result
    }

    private static func titleWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'’"))) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { !$0.isEmpty }
    }
}
