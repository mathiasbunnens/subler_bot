#!/usr/bin/env python3
"""Static RED/GREEN safeguards for the isolated experimental native build."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'vendor-local/Subler'

class LocalSublerContract(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_script_exports_use_hevc_option(self):
        source = self.text('Classes/ScriptCommand.swift')
        self.assertIn('options[MP42ForceHvc1] = true', source)
        self.assertIn('options["MP42StrictHvc1"] = true', source)

    def test_nonwindowed_import_is_explicit(self):
        self.assertIn('import background file', self.text('Subler.sdef'))
        source = self.text('Classes/ScriptCommand.swift')
        self.assertIn('class SBImportBackgroundFileScriptCommand', source)
        self.assertIn('isTrackMuxable', source)
        self.assertIn('return String(doc.uniqueID)', source)

    def test_local_storage_is_separate(self):
        for name in ['Logger', 'QueuePreferences', 'PresetManager', 'Preset', 'OCRManager']:
            source = self.text('Classes/' + name + '.swift')
            self.assertNotIn('appendingPathComponent("Subler"', source, name)

    def test_launch_does_not_construct_windows(self):
        source = self.text('Classes/AppDelegate.swift')
        self.assertIn('NSApp.setActivationPolicy(.prohibited)', source)
        self.assertNotIn('_ = activityWindowController', source)
        self.assertNotIn('QueueController.shared.showWindow(self)\n        }', source)
        self.assertNotIn('documentController.openDocument(self)\n        }', source)
        self.assertIn('@objc dynamic let uniqueID', self.text('Classes/Document.swift'))

if __name__ == '__main__':
    unittest.main()
