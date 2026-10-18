#!/usr/bin/env python3
"""Native SwiftUI/model fixture; never starts JobQueueService or sends Apple Events."""
import os
from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parents[1]
scratch = Path(os.environ.get("SUBLER_TEST_SCRATCH", str(Path.home() / ".hermes/cache/scratch"))).resolve()
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="subler-appletv-", dir=scratch) as temp:
    root = Path(temp)
    env = dict(os.environ, TMPDIR=str(scratch), SUBLER_AUTOMATION_TEST_ROOT=temp)

    def run(args):
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=180)
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout or f"Exit {result.returncode}")
        print(result.stdout, end="")
        return result.stdout

    run(["swiftc", "-emit-library", "-emit-module", "-module-name", "AutomationCore",
         *map(str, (project / "Sources/AutomationCore").glob("*.swift")),
         "-emit-module-path", str(root / "AutomationCore.swiftmodule"), "-o", str(root / "libAutomationCore.dylib")])
    binary = root / "AppleTVSmoke"
    run(["swiftc", "-parse-as-library", "-I", temp, "-L", temp, "-lAutomationCore",
         "-Xlinker", "-rpath", "-Xlinker", temp,
         str(project / "Sources/SublerAutomation/Views/AppleTVPreparationView.swift"),
         str(project / "scripts/appletv-smoke.swift"), "-o", str(binary)])
    output = run([str(binary)])
    assert "APPLETV_MODEL_SMOKE_PASS" in output, "Fixture exited without running its assertions"
