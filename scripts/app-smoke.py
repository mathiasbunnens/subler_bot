#!/usr/bin/env python3
"""Real packaged-app watcher/persistence smoke; isolated and paused, no conversion."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parent.parent
executable = Path(os.environ.get("SUBLER_BUILD_APP", str(project / "dist/Subler Automation.app"))) / "Contents/MacOS/SublerAutomation"
scratch = Path(os.environ.get("SUBLER_BUILD_SCRATCH", str(Path.home() / ".hermes/cache/scratch"))).resolve()
scratch.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix="subler-app-smoke-", dir=scratch))
source = root / "Source"
source.mkdir()
fixture = source / "Synthetic.2001.mkv"
original = b"Paused watcher fixture only, not a playable movie"
fixture.write_bytes(original)
settings = {
    "sourcePath": str(source), "temporaryPath": str(root / "Temp"),
    "smb": {"serverURL": "smb://192.168.1.100/Movies", "username": "adminMat", "expectedMountPath": "/Volumes/Movies"},
    "watchFolder": True, "notifications": False, "cleanupTemporary": False, "paused": True,
}
(root / "settings.json").write_text(json.dumps(settings))
env = dict(os.environ, SUBLER_AUTOMATION_TEST_ROOT=str(root))
process = None
log = (root / "process.log").open("w")

def launch():
    return subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)

def read_state():
    state = json.loads((root / "jobs.json").read_text())
    assert isinstance(state, dict) and state["version"] == 1
    assert isinstance(state["dismissedFingerprints"], list)
    return state

def wait_queue(predicate):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"App exited: {process.returncode}; see {root}/process.log")
        try:
            jobs = read_state()["jobs"]
            if predicate(jobs):
                return jobs
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.2)
    raise AssertionError("Watcher/persistence deadline exceeded")

try:
    process = launch()
    jobs = wait_queue(lambda j: len(j) == 1)
    assert jobs[0]["sourcePath"] == str(fixture), f"Expected {str(fixture)!r}, got {jobs[0]['sourcePath']!r}; evidence: {root}"
    assert jobs[0]["status"] == "pending"
    second = launch()
    assert second.wait(timeout=10) == 0, "Second instance did not refuse the lock"
    assert process.poll() is None, "Second instance stopped the original app"
    time.sleep(6)
    assert len(read_state()["jobs"]) == 1, "Watcher duplicated its input"
    process.terminate()
    process.wait(timeout=10)
    jobs[0]["status"] = "converting"
    state = read_state()
    state["jobs"] = jobs
    (root / "jobs.json").write_text(json.dumps(state))
    process = launch()
    reopened = wait_queue(lambda j: len(j) == 1 and j[0]["status"] == "pending")
    assert reopened[0]["id"] == jobs[0]["id"]
    assert fixture.read_bytes() == original, "Original fixture was modified"
    print("APP_SMOKE_PASS: watcher, persistent queue, deduplication, single instance, restart recovery, source preservation")
    print(f"Isolated evidence: {root}")
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    log.close()
