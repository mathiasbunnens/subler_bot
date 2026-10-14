#!/usr/bin/env python3
"""Static UI regression contracts; no app launch or user-state access.

These checks intentionally do not claim rendered layout or interaction coverage.
Run the parent app build separately to verify SwiftUI type checking.
"""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parent.parent /
          "Sources/SublerAutomation/Views/MenuBarView.swift").read_text()


class MenuUIContracts(unittest.TestCase):
    def test_transfer_details_keep_a_compact_numeric_hierarchy(self):
        transfer = SOURCE.split('struct TransferProgressView', 1)[1].split('struct MenuBarView', 1)[0]
        self.assertIn('HStack', transfer)
        self.assertIn('.monospacedDigit()', transfer)
        self.assertIn('SwiftUI.ProgressView(value: fraction)', transfer)
        for field in ['verificationBytes', 'bytesCopied', 'totalBytes', 'bytesPerSecond', 'secondsRemaining']:
            self.assertIn('sample.' + field, transfer)
        self.assertIn('Vérification SHA-256', transfer)
        self.assertIn('Synchronisation du fichier serveur', transfer)

    def test_compact_native_dashboard_has_bounded_content_and_pinned_footer(self):
        self.assertIn('private var header', SOURCE)
        self.assertIn('private var summary', SOURCE)
        self.assertIn('private var footer', SOURCE)
        self.assertIn('private func activeCard', SOURCE)
        self.assertIn('private func stageGrid', SOURCE)
        self.assertIn('private func card', SOURCE)
        self.assertIn('Color(nsColor: .controlBackgroundColor)', SOURCE)
        self.assertIn('.background(.regularMaterial)', SOURCE)
        body = SOURCE.split('struct MenuBarView', 1)[1].split('private var header', 1)[0]
        self.assertRegex(body, r'if contentHeight > contentHeightLimit[\s\S]+ScrollView[\s\S]+\.frame\(height: contentHeightLimit\)[\s\S]+else[\s\S]+menuContent[\s\S]+Divider\(\)[\s\S]+footer')
        self.assertIn('@State private var contentHeight: CGFloat = 0', SOURCE)
        self.assertNotIn('.frame(height: min(contentHeight, contentHeightLimit))', SOURCE)
        self.assertNotIn('.frame(maxHeight: 460).fixedSize', body)
        self.assertIn('GeometryReader', body)
        self.assertIn('.onPreferenceChange(MenuContentHeightKey.self)', body)
        self.assertIn('NSScreen.main?.visibleFrame.height', SOURCE)
        self.assertIn('min(460,', SOURCE)
        self.assertIn('.frame(width: 380)', body)
        self.assertIn('.monospacedDigit()', SOURCE)
        self.assertIn('RemainingTimeFormatter.string(seconds: remaining)', SOURCE)

    def test_metadata_candidates_are_visible_and_bounded(self):
        self.assertNotRegex(SOURCE, r'Menu\("Choisir les métadonnées')
        self.assertIn('private func candidateRows', SOURCE)
        rows = SOURCE.split('private func candidateRows', 1)[1].split('private ', 1)[0]
        self.assertNotIn('ScrollView', rows, 'Candidates share the main bounded scroll, not a tiny nested viewport')
        self.assertIn('ForEach(choices)', rows)
        self.assertIn('queue.select(choice, for: job.id)', rows)
        self.assertIn('Text(choice.title)', rows)
        self.assertIn('Text(String(choice.year))', rows)

        self.assertIn('job.needsSelection', SOURCE)

    def test_buttons_use_transparent_native_macos_chrome(self):
        footer = SOURCE.split('private var footer', 1)[1].split('// System colours', 1)[0]
        self.assertIn('.controlSize(.regular)', footer)
        self.assertIn('.buttonStyle(.borderless)', footer)
        self.assertNotIn('.buttonStyle(.bordered)', SOURCE)
        self.assertNotIn('.buttonStyle(.borderedProminent)', SOURCE)
        rows = SOURCE.split('private func candidateRows', 1)[1].split('private ', 1)[0]
        self.assertIn('.buttonStyle(.borderless)', rows)
        self.assertNotIn('.buttonStyle(.plain)', rows)

    def test_existing_safe_actions_remain(self):
        self.assertIn('queue.connectServer(for: job.id)', SOURCE)
        self.assertIn('job.status == .waitingForServer, job.validated', SOURCE)
        self.assertIn('queue.removeIntervention(job.id)', SOURCE)
        for action in ['cancelTransfer()', 'retry(job.id)', 'ignore(job.id)',
                       'confirmReplacement(job.id)', 'addMovies()', 'togglePause()',
                       'openSource()', 'openLogs()', 'quit()', 'preparePermissions()']:
            with self.subTest(action=action):
                self.assertIn('queue.' + action, SOURCE)
        self.assertIn('if job.conflict', SOURCE)
        self.assertIn('@Environment(\.openSettings)', SOURCE)
        self.assertIn('openSettings()\n                    SettingsWindowFocus.request()', SOURCE)
        self.assertNotIn('.simultaneousGesture(TapGesture()', SOURCE)
        self.assertIn('SettingsWindowFocus.request()', SOURCE)
        self.assertIn('.keyboardShortcut("q")', SOURCE)
        self.assertNotRegex(SOURCE, r'queue\.(?:select|retry|ignore|confirmReplacement)\([^\n]+\)\s*\}\s*\.task')


if __name__ == '__main__':
    unittest.main(verbosity=2)
