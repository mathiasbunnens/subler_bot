#!/usr/bin/env python3
"""Bounded, scratch-only APFS transfer benchmark; never measures SMB throughput.

Builds only TransferService + SMBService in an isolated release Swift package.
Use --transfer-source with a saved pre-change source for baseline comparison.
No live mounts, credentials, application queue, or user media are accessed.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

SWIFT_TEST = r'''
import XCTest
import Foundation
import CryptoKit
@testable import AutomationCore

private actor Measurements {
    var copyStart: Double?
    var verificationStart: Double?
    var verificationEnd: Double?
    var verificationBytes: Int64 = 0
    var verificationPasses = 0
    var checks = 0
    func check() { checks += 1 }
    func progress(_ value: TransferProgress) {
        let now = ProcessInfo.processInfo.systemUptime
        if copyStart == nil { copyStart = now }
        if let bytes = value.verificationBytes {
            if bytes == 0 { verificationStart = now; verificationPasses += 1 }
            verificationBytes = bytes
            if bytes == value.totalBytes { verificationEnd = now }
        }
    }
    func result(start: Double, end: Double) -> [String: Any] {
        ["total_seconds": end - start,
         "precopy_seconds": (copyStart ?? end) - start,
         "copy_seconds": (verificationStart ?? end) - (copyStart ?? end),
         "verification_seconds": (verificationEnd ?? end) - (verificationStart ?? end),
         "verification_bytes": verificationBytes,
         "verification_passes": verificationPasses,
         "verify_callbacks": checks]
    }
}
final class TransferBenchmarkTests: XCTestCase {
    func testScratchBenchmark() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: env["TRANSFER_BENCH_ROOT"]!)
        let sizeMiB = Int(env["TRANSFER_BENCH_MIB"]!)!
        let iterations = Int(env["TRANSFER_BENCH_ITERATIONS"]!)!
        let source = root.appendingPathComponent("input.mp4")
        _ = FileManager.default.createFile(atPath: source.path, contents: nil)
        let writer = try FileHandle(forWritingTo: source)
        // Fixed, non-sparse bytes, produced incrementally outside timed regions.
        let block = Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 17) })
        var hash = SHA256()
        for _ in 0..<sizeMiB { try writer.write(contentsOf: block); hash.update(data: block) }
        try writer.synchronize(); try writer.close()
        let expected = hash.finalize().map { String(format: "%02x", $0) }.joined()
        for iteration in 0..<iterations {
            for scenario in ["fresh", "replace-different-size"] {
                let share = root.appendingPathComponent("share-\(iteration)-\(scenario)")
                try FileManager.default.createDirectory(at: share, withIntermediateDirectories: false)
                if scenario != "fresh" {
                    let old = share.appendingPathComponent("Movie")
                    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false)
                    try Data([0xAB]).write(to: old.appendingPathComponent("Movie.mp4"))
                }
                let service = TransferService(directoryPublication: true)
                let measurements = Measurements()
                let start = ProcessInfo.processInfo.systemUptime
                let result = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), replaceExisting: scenario != "fresh", expectedDigest: expected,
                    verify: { await measurements.check() }, progress: { await measurements.progress($0) })
                let end = ProcessInfo.processInfo.systemUptime
                var row = await measurements.result(start: start, end: end)
                row["scenario"] = scenario; row["iteration"] = iteration; row["size_mib"] = sizeMiB
                XCTAssertEqual(row["verification_bytes"] as? Int64, Int64(sizeMiB) * 1_048_576)
                XCTAssertEqual(row["verification_passes"] as? Int, 1)
                // Independent descriptor hash after timing verifies published content.
                let reader = try FileHandle(forReadingFrom: result)
                var actual = SHA256()
                while let data = try reader.read(upToCount: 8_388_608), !data.isEmpty { actual.update(data: data) }
                try reader.close()
                XCTAssertEqual(actual.finalize().map { String(format: "%02x", $0) }.joined(), expected)
                print("TRANSFER_BENCH_JSON " + String(data: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8)!)
                try FileManager.default.removeItem(at: share)
            }
        }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mib", type=int, default=128, choices=[128, 256])
    parser.add_argument("--iterations", type=int, default=5, choices=range(1, 11))
    parser.add_argument("--transfer-source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    scratch = Path.home() / ".hermes/cache/scratch"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="transfer-benchmark-", dir=scratch) as temp:
        root = Path(temp)
        sources = root / "Sources/AutomationCore"
        tests = root / "Tests/AutomationCoreTests"
        sources.mkdir(parents=True)
        tests.mkdir(parents=True)
        for name in ["TransferService.swift", "SMBService.swift"]:
            origin = args.transfer_source.resolve() if name == "TransferService.swift" and args.transfer_source else repo / "Sources/AutomationCore" / name
            (sources / name).symlink_to(origin)
        (root / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TransferBench", platforms: [.macOS(.v14)], targets: [
    .target(name: "AutomationCore"),
    .testTarget(name: "AutomationCoreTests", dependencies: ["AutomationCore"])
])
''')
        (tests / "TransferBenchmarkTests.swift").write_text(SWIFT_TEST)
        fixtures = root / "fixtures"
        fixtures.mkdir()
        env = dict(os.environ, TMPDIR=str(scratch), TRANSFER_BENCH_ROOT=str(fixtures), TRANSFER_BENCH_MIB=str(args.mib), TRANSFER_BENCH_ITERATIONS=str(args.iterations))
        env.pop("SUBLER_TEST_SMB", None)
        run = subprocess.run(["swift", "test", "-c", "release", "--package-path", str(root), "--filter", "TransferBenchmarkTests"], env=env, capture_output=True, text=True, timeout=300)
        rows = [json.loads(line.split("TRANSFER_BENCH_JSON ", 1)[1]) for line in run.stdout.splitlines() if line.startswith("TRANSFER_BENCH_JSON ")]
        if run.returncode or len(rows) != args.iterations * 2:
            raise RuntimeError(run.stdout + run.stderr)
        medians = {scenario: {key: statistics.median(row[key] for row in rows if row["scenario"] == scenario) for key in ["total_seconds", "precopy_seconds", "copy_seconds", "verification_seconds", "verify_callbacks"]} for scenario in ["fresh", "replace-different-size"]}
        report = {"filesystem_scope": "local scratch APFS, cache-warm; not SMB throughput or metadata latency", "mib": args.mib, "iterations": args.iterations, "transfer_source": str(args.transfer_source or repo / "Sources/AutomationCore/TransferService.swift"), "rows": rows, "medians": medians}
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"output": str(args.output), "medians": medians}, indent=2))


if __name__ == "__main__":
    main()
