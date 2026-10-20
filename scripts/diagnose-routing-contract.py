#!/usr/bin/env python3
"""Selection-only evidence; no Apple Events, settings, queues or process environments."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, **kwargs)
    return {"exit": result.returncode, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}

report: dict[str, Any] = {"head": run("git", "rev-parse", "HEAD"),
          "processes": run("ps", "-p", "10111,74216", "-o", "pid=,lstart=,comm=")}
keys = ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
        "SublerAutomationEngine", "SublerAutomationBackgroundRelativePath",
        "SublerAutomationBackgroundProtocol", "LSBackgroundOnly", "SublerAutomationCommit")
report["bundles"] = []
for relative in ("dist/Subler Automation.app", "dist-local/Subler Automation.app",
                 "dist-local/Subler Automation Local.app", "dist-local/Subler Background.app"):
    app = ROOT / relative
    if not app.exists():
        report["bundles"].append({"path": relative, "exists": False})
        continue
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    report["bundles"].append({"path": relative, "metadata": {k: info[k] for k in keys if k in info},
        "binaryMtimeEpoch": binary.stat().st_mtime,
        "signature": run("codesign", "-d", "--verbose=2", str(app)),
        "verification": run("codesign", "--verify", "--deep", "--strict", str(app))})

# Execute the exact historical resolver with only its unused collaborator types stubbed.
# No service/queue initialization and no validatedApplicationURL()/Apple Event invocation.
old = subprocess.check_output(["git", "show", "1da55a9:Sources/AutomationCore/SublerTarget.swift"], cwd=ROOT, text=True)
stubs = '''
enum AutomationServiceError: Error { case message(String) }
struct SublerDocument { let backgroundToken: String?; let id: Int }
struct AppleScriptService { static func literal(_ value: String) -> String { value } }
'''
main = '''
import Foundation
let defaultTarget = SublerTarget()
let optIn = SublerTarget(backgroundApplication: "/synthetic/Subler Background.app")
precondition(defaultTarget.bundleIdentifier == "org.galad.Subler" && !defaultTarget.isBackground)
precondition(optIn.bundleIdentifier == "local.sublerautomation.Subler" && optIn.isBackground)
print("PASS exact 1da55a9 resolver: absent opt-in selects org.galad.Subler; explicit opt-in selects local.sublerautomation.Subler")
'''
with tempfile.TemporaryDirectory(prefix="routing-selection-", dir=os.environ["TMPDIR"]) as temporary:
    scratch = Path(temporary)
    (scratch / "Historical.swift").write_text(old + stubs)
    (scratch / "main.swift").write_text(main)
    compiled = run("swiftc", str(scratch / "Historical.swift"), str(scratch / "main.swift"), "-o", str(scratch / "selection"))
    assert compiled["exit"] == 0, compiled
    clean = os.environ.copy()
    clean.pop("SUBLER_AUTOMATION_LOCAL_SUBLER_APP", None)
    report["historicalSelection"] = run(str(scratch / "selection"), env=clean)
    assert report["historicalSelection"]["exit"] == 0
    executable = ROOT / "dist-local/Subler Automation Local.app/Contents/MacOS/SublerAutomation"
    report["currentSelection"] = run(str(executable), "--diagnose-target", env=clean, timeout=15)
    selected = json.loads(report["currentSelection"]["stdout"])
    assert selected["background"] and selected["valid"] and selected["targetBundleIdentifier"] == "local.sublerautomation.Subler"
print(json.dumps(report, indent=2))
