import XCTest
@testable import AutomationCore

/// Zero-result TMDB searches caused by a parasitic token in the release name (sequel number).
final class MetadataSearchVariantsTests: XCTestCase {
    private let oss = "OSS 117 2 Rio ne repond plus 2009 VFF 1080p HDLight x264.mkv"

    private func candidate(_ title: String, _ year: Int, index: Int = 1, terms: String? = nil) -> MetadataCandidate {
        MetadataCandidate(index: index, title: title, year: year, raw: "Movie: \(title) (\(year))", searchTerms: terms)
    }

    func testRealReleaseFirstVariantDropsSequelNumberAndYear() {
        let variants = MetadataSearchVariants.variants(sourceName: oss)
        XCTAssertEqual(variants.first, "OSS 117 Rio ne repond plus")
        XCTAssertEqual(variants[1], "OSS 117 2 Rio ne repond plus")
        XCTAssertLessThanOrEqual(variants.count, MetadataSearchVariants.maximumCount)
        XCTAssertFalse(variants.contains { $0.contains("2009") || $0.lowercased().contains("vff") || $0.contains("1080p") })
        XCTAssertEqual(Set(variants.map { $0.lowercased() }).count, variants.count, "no duplicate query")
        // Trailing words dropped one at a time, never below two words.
        XCTAssertTrue(variants.contains("OSS 117 Rio ne repond"))
        XCTAssertFalse(variants.contains("OSS"))
        // Dotted release spelling gives the same queries.
        XCTAssertEqual(MetadataSearchVariants.variants(sourceName: "OSS.117.2.Rio.ne.repond.plus.2009.VFF.1080p.HDLight.x264.mkv"), variants)
    }

    func testRealReleaseAutoSelectsLocalizedFrenchTitle() {
        let rio = candidate("OSS 117 : Rio ne répond plus", 2009, terms: "OSS 117 Rio ne repond plus")
        XCTAssertEqual(MetadataMatching.best(sourceName: oss, candidates: [rio]), rio)
        XCTAssertEqual(MetadataMatching.best(sourceName: oss, candidates: [rio])?.searchTerms, "OSS 117 Rio ne repond plus")
        // Title/alias match wins even among other candidates of other or the same year.
        let caire = candidate("OSS 117 : Le Caire, nid d'espions", 2006, index: 2)
        let other = candidate("Rio", 2009, index: 3)
        XCTAssertEqual(MetadataMatching.best(sourceName: oss, candidates: [caire, rio, other]), rio)
        // Without the French tag the alias still matches by title + year.
        XCTAssertEqual(MetadataMatching.best(sourceName: "OSS.117.2.Rio.ne.repond.plus.2009.1080p.mkv", candidates: [rio]), rio)
    }

    func testWrongYearIsNotSelected() {
        XCTAssertNil(MetadataMatching.best(sourceName: oss, candidates: [candidate("OSS 117 : Rio ne répond plus", 2010)]))
        XCTAssertNil(MetadataMatching.best(sourceName: oss, candidates: [candidate("OSS 117 : Le Caire, nid d'espions", 2006)]))
    }

    func testSeveralSameYearCandidatesNeedIntervention() {
        let rio = candidate("OSS 117 : Rio ne répond plus", 2009)
        XCTAssertNil(MetadataMatching.best(sourceName: oss, candidates: [rio, candidate(rio.title, 2009, index: 2)]))
        XCTAssertNil(MetadataMatching.best(sourceName: oss, candidates: [candidate("Rio", 2009), candidate("Plus", 2009, index: 2)]))
    }

    func testNoYearNeverAutoSelectsButStillProducesQueries() {
        let name = "OSS 117 2 Rio ne repond plus VFF 1080p HDLight x264.mkv"
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [candidate("OSS 117 : Rio ne répond plus", 2009)]))
        XCTAssertEqual(MetadataSearchVariants.variants(sourceName: name).first, "OSS 117 Rio ne repond plus")
    }

    func testTitlesLegitimatelyContainingNumbers() {
        let odyssey = "2001 l'odyssée de l'espace 1968 VFF 1080p.mkv"
        XCTAssertEqual(MetadataSearchVariants.variants(sourceName: odyssey).first, "2001 l'odyssée de l'espace")
        let kubrick = candidate("2001 : l'odyssée de l'espace", 1968)
        XCTAssertEqual(MetadataMatching.best(sourceName: odyssey, candidates: [kubrick]), kubrick)

        XCTAssertEqual(MetadataSearchVariants.variants(sourceName: "300 2006 VFF 1080p.mkv"), ["300"])
        let spartans = candidate("300", 2006)
        XCTAssertEqual(MetadataMatching.best(sourceName: "300 2006 VFF 1080p.mkv", candidates: [spartans]), spartans)

        // A trailing number is part of the title: kept in the first query and in matching.
        let ocean = "Ocean's 11 2001 MULTI 1080p.mkv"
        XCTAssertEqual(MetadataSearchVariants.variants(sourceName: ocean).first, "Ocean's 11")
        let eleven = candidate("Ocean's 11", 2001)
        XCTAssertEqual(MetadataMatching.best(sourceName: ocean, candidates: [eleven]), eleven)
        XCTAssertNil(MetadataMatching.best(sourceName: ocean, candidates: [candidate("Ocean's", 2001)]),
                     "dropping a trailing number must not create a title alias")
        XCTAssertNil(MetadataMatching.best(sourceName: "Saw 3 2006 1080p.mkv", candidates: [candidate("Saw", 2006)]))
    }

    func testAliasesInBracketsBecomeQueries() {
        let variants = MetadataSearchVariants.variants(sourceName: "Le Prenom (What's in a Name) 2012 1080p.mkv")
        XCTAssertEqual(variants.prefix(2), ["Le Prenom", "What's in a Name"])
    }

    func testSearchTermsClauseIsOptionalAndEscaped() {
        XCTAssertEqual(SublerService.searchTermsClause(nil), "")
        XCTAssertEqual(SublerService.searchTermsClause("OSS 117 Rio"), " search terms \"OSS 117 Rio\"")
        XCTAssertEqual(SublerService.searchTermsClause("a\"b"), " search terms \"a\\\"b\"")
    }

    /// Candidates and fetch-and-set must use the same query, otherwise the index points elsewhere.
    func testFetchAndSetReusesTheCandidateQuery() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AutomationCore/SublerService.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let setLines = source.split(separator: "\n").filter { $0.contains("fetch and set metadata candidate") }
        XCTAssertEqual(setLines.count, 1)
        XCTAssertTrue(setLines[0].contains("searchTermsClause($0.searchTerms)"))
        let fetchLines = source.split(separator: "\n").filter { $0.contains("fetch metadata candidates") && $0.contains("set resultsList") }
        XCTAssertEqual(fetchLines.count, 1)
        XCTAssertTrue(fetchLines[0].contains("searchTermsClause(searchTerms)"))
        XCTAssertTrue(source.contains("guard found.isEmpty, target.isBackground else { return found }"),
                      "variants only after zero default results and only with the embedded engine")
    }

    func testEnginePatchAddsSearchTermsToBothCommandsAndIsWired() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let patch = try String(contentsOf: root.appendingPathComponent("patches/local-subler/background-metadata-search-terms.patch"), encoding: .utf8)
        let script = try String(contentsOf: root.appendingPathComponent("scripts/prepare-local-subler.sh"), encoding: .utf8)
        XCTAssertEqual(patch.components(separatedBy: "+            <parameter name=\"search terms\" code=\"sTrm\"").count - 1, 2)
        XCTAssertEqual(patch.components(separatedBy: "+        let searchTerms = customSearchTerms(self) ?? mp4File.extractSearchTerms").count - 1, 2)
        let subtitle = try XCTUnwrap(script.range(of: "apply \"$patch_root/background-subtitle-policy.patch\""))
        let terms = try XCTUnwrap(script.range(of: "apply \"$patch_root/background-metadata-search-terms.patch\""))
        XCTAssertLessThan(subtitle.lowerBound, terms.lowerBound)
    }

    func testCandidateDecodesLegacyJSONWithoutSearchTerms() throws {
        let legacy = #"{"index":2,"title":"Rio","year":2009,"raw":"Movie: Rio (2009)"}"#
        let decoded = try JSONDecoder().decode(MetadataCandidate.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.searchTerms)
        XCTAssertEqual(decoded.index, 2)
    }
}
