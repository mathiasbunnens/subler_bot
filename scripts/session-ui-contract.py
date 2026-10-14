from pathlib import Path
import unittest
root = Path(__file__).resolve().parents[1]
class SessionUIContracts(unittest.TestCase):
    def test_footer_only_for_changes_and_bottom_animation(self):
        text = (root/'Sources/SublerAutomation/Views/SettingsView.swift').read_text()
        self.assertIn('if hasChanges {', text)
        self.assertIn('.move(edge: .bottom)', text)
        self.assertIn('value: hasChanges', text)
    def test_badge_requires_a_durable_completion_this_session(self):
        label = (root/'Sources/SublerAutomation/Views/MenuBarStatusLabel.swift').read_text()
        queue = (root/'Sources/SublerAutomation/Services/JobQueueService.swift').read_text()
        self.assertIn('hasCompletedThisSession &&', label)
        self.assertIn('hasCompletedThisSession = false', queue)
        completion = queue.index('try update(id) { $0.status = .completed')
        self.assertGreater(queue.index('hasCompletedThisSession = true'), completion)
if __name__ == '__main__': unittest.main(verbosity=2)
