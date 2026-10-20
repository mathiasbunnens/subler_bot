import Foundation
import AutomationCore

// Generated-only fixture seeding: native model/fingerprint, never production state.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let source = root.appendingPathComponent("Source/Generated.2026.mkv")
var job = MovieJob(sourcePath: source.path, fingerprint: try FileIdentity.fingerprint(source))
job.manualMetadata = try ManualMovieMetadata.parse(title: "Generated Finder launch", year: "2026")
try QueueStore(root: root).save([job])
