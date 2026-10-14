#!/usr/bin/env python3
from pathlib import Path
import unittest
TEXT = (Path(__file__).resolve().parents[1] / 'Sources/SublerAutomation/Services/PermissionPreparationService.swift').read_text()
class RunningTargetContract(unittest.TestCase):
    def test_target_is_running_before_request(self):
        self.assertIn('launchSublerIfNeeded()', TEXT)
        self.assertIn('runningApplications(withBundleIdentifier: "org.galad.Subler")', TEXT)
        self.assertIn('configuration.activates = false', TEXT)
        self.assertIn('openApplication(at:', TEXT)
    def test_missing_target_is_not_reported_as_revoked_permission(self):
        self.assertIn('status == procNotFound', TEXT)
if __name__ == '__main__': unittest.main(verbosity=2)
