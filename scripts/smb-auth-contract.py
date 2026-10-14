#!/usr/bin/env python3
"""Source wiring contracts complement the executable SMB authentication policy tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / 'Sources/SublerAutomation/Services/JobQueueService.swift').read_text()
SERVICE = (ROOT / 'Sources/AutomationCore/SMBService.swift').read_text()

class SMBWiringContracts(unittest.TestCase):
    def test_interactive_auth_is_gated_after_silent_reconnect_failure(self):
        processing = QUEUE.split('private func process', 1)[1].split('func select', 1)[0]
        self.assertIn('smb.reconnect(configuration: configuration)', processing)
        self.assertIn('authenticationGate.begin(job:', processing)
        self.assertIn('allowAuthenticationUI: true', processing)
        tick = QUEUE.split('func tick()', 1)[1].split('private func start', 1)[0]
        self.assertNotIn('allowAuthenticationUI: true', tick)
        self.assertIn('catch is CancellationError', processing)

    def test_manual_connection_rearms_only_a_waiting_validated_film(self):
        method = QUEUE.split('func connectServer', 1)[1].split('func retry', 1)[0]
        self.assertIn('value.validated', method)
        self.assertIn('value.status == .waitingForServer', method)
        self.assertIn('worker == nil', method)
        self.assertIn('authenticationGate.allowRetry(configuration:', method)

    def test_password_is_left_to_native_netauth(self):
        self.assertIn('allowAuthenticationUI: Bool = false', SERVICE)
        self.assertIn('configuration.username as CFString, nil, options', SERVICE)
        self.assertNotIn('SecureField', QUEUE)
        self.assertIn('return try mountedShare(configuration: configuration)', SERVICE)

if __name__ == '__main__':
    unittest.main(verbosity=2)
