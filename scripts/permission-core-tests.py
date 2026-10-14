#!/usr/bin/env python3
"""Run owned policy XCTest tests without building the concurrently edited app."""
import pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path.home()/'.hermes/cache/scratch'
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='subler-permission-core-', dir=scratch) as directory:
    work = pathlib.Path(directory)
    (work/'Sources').mkdir()
    (work/'Sources/AutomationCore').symlink_to(root/'Sources/AutomationCore', target_is_directory=True)
    tests = work/'Tests/AutomationCoreTests'
    tests.mkdir(parents=True)
    (tests/'PermissionPreparationTests.swift').symlink_to(root/'Tests/AutomationCoreTests/PermissionPreparationTests.swift')
    (work/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PermissionFixture", platforms: [.macOS(.v14)], targets: [.target(name: "AutomationCore"), .testTarget(name: "AutomationCoreTests", dependencies: ["AutomationCore"])])
''')
    subprocess.run(['swift', 'test', '--package-path', str(work), '--scratch-path', str(work/'build')], check=True, cwd=root)
