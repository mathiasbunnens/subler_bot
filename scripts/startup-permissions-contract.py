#!/usr/bin/env python3
"""Queue wiring gates; native behavior is checked by permission/UI fixtures."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / 'Sources/SublerAutomation/Services/JobQueueService.swift').read_text()
MENU = (ROOT / 'Sources/SublerAutomation/Views/MenuBarView.swift').read_text()

class StartupPermissionsContracts(unittest.TestCase):
    def test_startup_prepares_before_first_tick(self):
        self.assertIn('await prepareStartupPermissions()', QUEUE)
        self.assertIn('func preparePermissions()', QUEUE)
        self.assertIn('self.permissions = permissions ?? .shared', QUEUE)
    def test_tick_rechecks_before_scanning(self):
        tick = QUEUE.split('func tick() async {', 1)[1].split('private func start(', 1)[0]
        self.assertLess(tick.index('permissions.recheck'), tick.index('scan()'))
        self.assertLess(tick.index('permissions.isReady'), tick.index('scan()'))
    def test_job_and_mounted_transfer_are_gated(self):
        process = QUEUE.split('private func process(', 1)[1].split('func select(', 1)[0]
        self.assertIn('PermissionScope(settings: runSettings, job: value)', process)
        self.assertGreaterEqual(process.count('permissions.isReady'), 2)
    def test_notifications_not_requested_when_menu_opens(self):
        self.assertNotIn('queue.requestNotifications()', MENU)

if __name__ == '__main__':
    unittest.main(verbosity=2)
