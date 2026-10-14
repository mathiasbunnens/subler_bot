#!/usr/bin/env python3
"""Structural safeguards complement compiled fixture and policy tests."""
import pathlib, plistlib
root = pathlib.Path(__file__).resolve().parents[1]
settings = (root/'Sources/SublerAutomation/Views/SettingsView.swift').read_text()
assert 'PermissionSettingsView(' in settings, 'Permissions must be visible in Settings'
assert 'if queue.settings.notifications { queue.requestNotifications() }' not in settings, 'Saving must not prompt independently'
view = (root/'Sources/SublerAutomation/Views/PermissionSettingsView.swift').read_text()
for value in ['Réessayer', '.requesting', '.blocked', 'macOS peut révoquer', 'Accessibilité', 'Accès complet']:
    assert value in view, value
info = plistlib.loads((root/'Sources/SublerAutomation/Resources/Info.plist').read_bytes())
for key in ['NSDownloadsFolderUsageDescription', 'NSDocumentsFolderUsageDescription', 'NSNetworkVolumesUsageDescription']:
    assert info.get(key), key
assert 'NSSystemAdministrationUsageDescription' not in info
print('PASS: French permissions UI, explicit retry, no save notification prompt, accurate plist scopes')
