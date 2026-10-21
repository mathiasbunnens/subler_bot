#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
queue = (root / 'Sources/SublerAutomation/Services/JobQueueService.swift').read_text()
delegate = (root / 'Sources/SublerAutomation/Services/AppPresentationController.swift').read_text()
target = (root / 'Sources/AutomationCore/SublerTarget.swift').read_text()
service = (root / 'Sources/AutomationCore/SublerService.swift').read_text()
assert 'func drainForTermination() async' in queue, 'Missing non-cancelling queue drain'
quit = queue[queue.index('func quit()'):queue.index('private func notify')]
assert 'worker?.cancel()' not in quit, 'Quit still cancels active import/conversion/transfer'
assert 'await worker?.value' in queue
assert '!isTerminating' in queue[queue.index('private func start('):queue.index('private func process(')]
assert 'queue.drainForTermination()' in delegate
assert 'queue.shutdownEmbeddedEngine()' in delegate
assert 'termination.request' in delegate and '.terminateLater' in delegate
assert 'AppleTVPreparationModel.shared.drainForTermination()' in delegate, 'Manual preparation must drain too'
assert 'EmbeddedEngineLifetime.ownership.recordLaunch' in target
assert 'ownedQueueIDs.insert(item.id)' in service
assert 'quitEmbeddedIfOwnedAndIdle' in service
print('PASS shutdown wiring contract: native/menu quit, drain, admission gate, launch ownership, native safe shutdown')
