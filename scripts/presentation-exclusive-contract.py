#!/usr/bin/env python3
"""Entrypoint contract: the status item is derived from saved mode, never writes it."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/SublerAutomation/App/SublerAutomationApp.swift').read_text()
assert re.search(r'MenuBarExtra\s*\(\s*isInserted:\s*Binding\s*\(', source), 'MenuBarExtra must explicitly bind insertion to presentation mode'
assert re.search(r'get:\s*\{\s*queue.settings.presentationMode\s*==\s*\.menuBar\s*\}', source), 'Only menu-bar mode inserts a status item'
assert re.search(r'set:\s*\{\s*_\s+in\s*(?://[^\n]*\n\s*)?\}', source), 'SwiftUI insertion callbacks must not mutate saved settings'
print('PRESENTATION_EXCLUSIVE_CONTRACT_PASS')
