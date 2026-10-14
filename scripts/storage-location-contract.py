#!/usr/bin/env python3
"""Storage advice wiring contracts, not a live SMB conversion or rendered UI test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / "Sources" / path).read_text()


class StorageLocationContracts(unittest.TestCase):
    def test_settings_selects_network_folders_and_shows_nonblocking_advice(self):
        view = source("SublerAutomation/Views/SettingsView.swift")
        self.assertIn("path.wrappedValue = url.path", view)
        self.assertIn("LocalPathPolicy.performanceWarning(path.wrappedValue)", view)
        self.assertIn(".foregroundStyle(.orange)", view)
        self.assertNotIn("if LocalPathPolicy.isOnThisMac(url.path)", view)
        self.assertNotIn("doivent être sur ce Mac", view)

    def test_queue_and_permissions_do_not_reject_a_location_for_performance(self):
        queue = source("SublerAutomation/Services/JobQueueService.swift")
        self.assertNotIn("guard LocalPathPolicy.isOnThisMac", queue)
        self.assertNotIn("values.volumeIsLocal == true", queue)
        self.assertIn("LocalPathPolicy.directoryURL(path)", queue)
        self.assertIn("LocalPathPolicy.performanceWarning(url.path)", queue)
        native = source("SublerAutomation/Services/PermissionPreparationService.swift")
        self.assertNotIn("volumeIsLocal", native)
        self.assertIn("LocalPathPolicy.directoryURL(path)", native)
        for retained in ("O_EXCL", "O_NOFOLLOW", "current.st_ino == info.st_ino", "access(path, W_OK | X_OK)"):
            self.assertIn(retained, native)

    def test_generated_output_keeps_ownership_and_integrity_not_locality_gate(self):
        output = source("AutomationCore/GeneratedOutput.swift")
        self.assertNotIn("volumeIsLocal", output)
        for retained in ("jobID.uuidString", "root.standardizedFileURL", "resolvingSymlinksInPath()",
                         "O_NOFOLLOW", "S_IFREG", "before.st_nlink == 1", "expectedDigest", "SHA256()"):
            self.assertIn(retained, output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
