import XCTest
@testable import AutomationCore

final class MetadataReleaseMatchingTests: XCTestCase {
    private func candidate(_ title: String, _ year: Int, index: Int = 1) -> MetadataCandidate {
        MetadataCandidate(index: index, title: title, year: year, raw: "Movie: \(title) (\(year))")
    }

    func testExactReportedMarioReleaseIgnores2160p() {
        let movie = candidate("The Super Mario Galaxy Movie", 2026)
        let name = "The.Super.Mario.Galaxy.Movie.2026.MULTI.VF2.2160p.WEBRip.iT.DV.HDR10+.x265.EAC3.5.1.Atmos-Amen.mkv"
        XCTAssertEqual(MetadataMatching.best(sourceName: name, candidates: [movie]), movie)
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [movie, movie]))
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [candidate(movie.title, 2025)]))
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [candidate("Super Mario Bros", 2026)]))
    }

    func testExactReportedJackRyanReleaseAndPossessiveSpellings() {
        let movie = candidate("Tom Clancy's Jack Ryan: Ghost War", 2026)
        let name = "Tom.Clancys.Jack.Ryan.Ghost.War.2026.MULTi.VF2.1080p.WEB.x265-FW-Zone-Telechargement.OrG.mkv"
        XCTAssertEqual(MetadataMatching.best(sourceName: name, candidates: [movie]), movie)
        for possessive in ["Clancy's", "Clancy’s", "Clancy s", "Clancys"] {
            XCTAssertEqual(MetadataMatching.best(sourceName: "Tom.\(possessive).Jack.Ryan-Ghost.War.2026.mkv", candidates: [movie]), movie)
        }
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [movie, candidate(movie.title, 2026, index: 2)]))
    }

    func testBilingualAliasAndExistingStrictMatchingContracts() {
        let movie = candidate("Spider-Man: Brand New Day", 2026, index: 3)
        let name = "Spider-Man  Un jour nouveau (Spider-Man Brand.New Day).CORE.2026.Multi.VFF.4Klight.HDR10+.DV.WEBRip.x265.⚡XRS-LazerTeam⚡.mkv"
        XCTAssertEqual(MetadataMatching.best(sourceName: name, candidates: [movie]), movie)
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [movie, movie]))
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [candidate(movie.title, 2025)]))
        let amelie = candidate("Amélie", 2001)
        XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [movie, candidate("Spider-Man Un jour nouveau", 2026, index: 4)]))
        XCTAssertEqual(MetadataMatching.best(sourceName: "Amelie.2001.1080p.mkv", candidates: [amelie]), amelie)
        for name in ["Amelie.2002.mkv", "Amelie.mkv", "Not.Amelie.2001.mkv", "Ameliex.2001.mkv"] {
            XCTAssertNil(MetadataMatching.best(sourceName: name, candidates: [amelie]))
        }
        let core = candidate("The Core", 2003)
        XCTAssertEqual(MetadataMatching.best(sourceName: "The.Core.2003.1080p.mkv", candidates: [core]), core)
    }

    func testLastTitleYearBeforeTechnicalSuffixAndNoProviderOrderFallback() {
        let movie = candidate("Blade Runner 2049", 2017)
        XCTAssertEqual(MetadataMatching.best(sourceName: "Blade.Runner.2049.2017.MULTI.2160p.WEB.2026.mkv", candidates: [candidate("Blade Runner", 2049), movie]), movie)
        XCTAssertNil(MetadataMatching.best(sourceName: "Blade.Runner.2049.2017.MULTI.2160p.WEB.2026.mkv", candidates: [candidate("Blade Runner", 2049)]))
        let space = candidate("2001: A Space Odyssey", 1968)
        XCTAssertEqual(MetadataMatching.best(sourceName: "2001.A.Space.Odyssey.1968.2160p.mkv", candidates: [space]), space)
    }

    func testResolutionTokensAreNeverExplicitYears() {
        let movie = candidate("Example", 2160)
        for resolution in ["2160p", "2160P", "2160i", "2160I", "1080p", "720p", "4320p"] {
            XCTAssertNil(MetadataMatching.best(sourceName: "Example.\(resolution).mkv", candidates: [movie]))
            let actual = candidate("Example", 2026)
            XCTAssertEqual(MetadataMatching.best(sourceName: "Example.2026.\(resolution).mkv", candidates: [actual]), actual)
        }
    }

    func testKnownTrailingDescriptorsAndAmpersandNormalization() {
        let movie = candidate("Tom & Jerry", 2026)
        XCTAssertEqual(MetadataMatching.best(sourceName: "Tom.and.Jerry.MULTI.VFQ.WEB.EAC3.Atmos.DV.HDR10+.10.bits.2026.mkv", candidates: [movie]), movie)
        XCTAssertEqual(MetadataMatching.best(sourceName: "Tom.&.Jerry.2026.mkv", candidates: [candidate("Tom and Jerry", 2026)]), candidate("Tom and Jerry", 2026))
    }

    func testExpandedDescriptorsPreserveUnstrippedTitlesAndAmbiguity() {
        let movie = candidate("The Web", 2026)
        XCTAssertEqual(MetadataMatching.best(sourceName: "The.Web.2026.mkv", candidates: [movie]), movie)
        XCTAssertNil(MetadataMatching.best(sourceName: "The.Web.2026.mkv", candidates: [movie, candidate("The", 2026, index: 2)]))
        XCTAssertNil(MetadataMatching.best(sourceName: "Example.2026.MULTI.WEB.2049.mkv", candidates: [candidate("Example", 2049)]))
    }
}
