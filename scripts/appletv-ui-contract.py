#!/usr/bin/env python3
"""Small source wiring contract; native behavior is checked separately."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
settings = (root / "Sources/SublerAutomation/Views/SettingsView.swift").read_text()
delegate = (root / "Sources/SublerAutomation/Services/AppPresentationController.swift").read_text()
assert "AppleTVPreparationView()" in settings, "Missing Apple TV preparation entry point"
assert "applicationShouldTerminate(" in delegate and "cancelAndWait" in delegate, "Quit must wait for the owned encoder"
print("Apple TV settings/termination wiring: PASS")
