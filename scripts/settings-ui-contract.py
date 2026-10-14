#!/usr/bin/env python3
"""Static native-settings contracts; not a rendered UI test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parent.parent / "Sources/SublerAutomation/Views/SettingsView.swift").read_text()

class SettingsUIContracts(unittest.TestCase):
    def test_focus_targets_the_attached_settings_window_and_repeated_requests(self):
        self.assertIn('.background(SettingsWindowAccessor())', SOURCE)
        self.assertIn('NSViewRepresentable', SOURCE)
        self.assertIn('override func viewDidMoveToWindow()', SOURCE)
        self.assertIn('guard let window = self.window', SOURCE)
        self.assertIn('window.makeKeyAndOrderFront(nil)', SOURCE)
        self.assertIn('NSApplication.shared.activate(ignoringOtherApps: true)', SOURCE)
        self.assertIn('private static weak var settingsWindow: NSWindow?', SOURCE)
        self.assertIn('requestID == generation', SOURCE)
        self.assertIn('window.deminiaturize(nil)', SOURCE)
        self.assertIn('DispatchQueue.main.asyncAfter', SOURCE)
        self.assertNotIn('NSApplication.shared.windows', SOURCE)
        self.assertNotIn('orderFrontRegardless', SOURCE)

    def test_presentation_is_native_and_explicitly_selectable(self):
        self.assertIn('$draft.presentationMode', SOURCE)
        app = (Path(__file__).resolve().parent.parent / 'Sources/SublerAutomation/App/SublerAutomationApp.swift').read_text()
        self.assertIn('AppPresentationController.shared.bind(queue)', app)
        self.assertIn('MenuBarStatusLabel(queue: queue)', app)

    def test_completion_badge_uses_native_non_template_image(self):
        file = Path(__file__).resolve().parent.parent / 'Sources/SublerAutomation/Views/MenuBarStatusLabel.swift'
        self.assertTrue(file.exists(), 'Native completion badge label is missing')
        label = file.read_text()
        for text in ['isTemplate = false', 'checkmark.circle.fill', 'badgeRect', 'NSColor.systemGreen', '.completed']:
            self.assertIn(text, label)

    def test_native_tabs_and_fixed_save_footer(self):
        self.assertIn("TabView", SOURCE)
        for title in ['Général', 'Dossiers', 'Serveur']:
            self.assertIn(f'Label("{title}"', SOURCE)
        self.assertIn('.formStyle(.grouped)', SOURCE)
        self.assertIn('.buttonStyle(.borderless)', SOURCE)
        self.assertNotIn('.buttonStyle(.bordered)', SOURCE)
        self.assertNotIn('.buttonStyle(.borderedProminent)', SOURCE)
        self.assertIn('.keyboardShortcut("s", modifiers: .command)', SOURCE)
        self.assertIn('.textFieldStyle(.roundedBorder)', SOURCE)
        self.assertIn('private var saveFooter', SOURCE)

    def test_settings_validation_and_safety_are_preserved(self):
        for text in ['queue.applySettings(draft)', 'draft.paused = queue.settings.paused',
                     'SMAppService.mainApp.register()', 'SMAppService.mainApp.unregister()',
                     'queue.preparePermissions()', '$draft.cleanupTemporary', '$draft.watchFolder',
                     '$draft.smb.serverURL', '$draft.smb.username', '$draft.smb.expectedMountPath',
                     'panel.canChooseFiles = false', 'panel.canChooseDirectories = true',
                     'draft = queue.settings', 'queue.message', 'serviceError']:
            self.assertIn(text, SOURCE)

if __name__ == '__main__':
    unittest.main(verbosity=2)
