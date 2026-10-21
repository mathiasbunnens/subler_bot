# Graceful embedded-engine shutdown — build 11

Task `t_70410dab`. Local-only change; no push or installation.

Deliverable: `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-standalone/Subler Automation build 11.app`.
This is one portable outer app, version 1.1.0/build 11, with its engine under `Contents/Helpers/Subler Background.app`. The earlier build-10 path is retained rather than overwritten. The signed Info.plist and `dist-standalone/evidence/graceful-build11/release.json` identify the exact source commit and executable hashes.

## Termination contract

- The menu power button, native application termination/Cmd-Q, SIGTERM and SIGINT share the AppKit delegate's idempotent `terminateLater` lifecycle. Closing the last window still does not quit the menu-bar app.
- Stop admission and scanning immediately. Await startup/explicit permission operations already underway, the current queue worker (including import, conversion, validation, transfer, publication and cleanup), and the separate manual Apple TV preparation task. Do not cancel either worker on quit. Pending jobs remain persisted for the next launch, rather than draining the entire backlog or waiting for an unavailable server forever.
- Save queue and settings before attempting engine shutdown. A persistence failure leaves the engine alone. No periodic/idle or between-job shutdown is introduced.
- Only the exact nested helper, validated with the existing background identity/protocol, may be considered. Remember the PID, launch date and canonical URL only when this Automation process actually launches the engine, including launches performed by permission preparation. Never adopt a pre-existing instance. Reject multiple instances, another path/build, missing identity, a helper symlink escaping the outer bundle, and an engine lacking graceful-quit capability.
- The shutdown code never launches anything. Send a custom `Subl/BgQt` event directly to the owned PID, not a global quit event, bundle-ID AppleScript dispatch or process signal.
- The native handler checks and terminates in one main-thread Apple Event handler: no windows, no documents, no active app, no working queue, no duplicate queue IDs, and every queue record must be completed with an ID recorded by this caller's current `SublerService` session. Unknown/foreign/previous-session records, including completed records, conservatively preserve the engine. No queue is stopped or globally cleared; no foreign document is closed.
- Apple Event delivery is bounded to 10 seconds, followed by at most 5 seconds observing that exact process. A refusal/error/timeout leaves a diagnostic in `automation.log`/Console, without force-killing or repeatedly retrying. Existing legacy helpers simply remain running. SIGKILL, force-quit and power loss cannot be intercepted or promised a drain.

## Executed verification

- RED then GREEN for the shared drain coordinator, launch/process ownership policy, native queue/document guard and application wiring.
- Targeted Swift suites: 51 discovered, 4 explicitly skipped opt-in native/online cases, zero failures. Includes ownership, repeated requests, background routing, persistence, batch counting and manual Apple TV preparation regressions. No unrelated full-suite run.
- Native guard execution covers empty/owned-completed queue, foreign queue, documents/windows, active/working state, non-completed/unknown states and duplicate IDs.
- Eight signed, isolated AppKit cases pass: absent engine, newly launched empty helper, native termination, SIGTERM, repeated quit, foreign queue, foreign document and pre-existing engine. These exercise the real `SublerTarget`/PID event sender, actual native quit handler and actual Automation delegate/services. Only queue storage in the engine is replaced by generated in-memory records; copied caller sources widen private task visibility solely to inject delayed workers. Both the queue worker and manual preparation finish without cancellation; the UI's main actor remains responsive; late imports are rejected; pending jobs survive disk readback. Native PID/canonical-path identity and repeated no-focus-steal observations are checked. Foreign/pre-existing fixture engines remain alive after Automation exits, then clean themselves up on their own fixture-only timer.
- The integration caught a real `terminateLater` reentrancy deadlock when invoked inside a Swift Task or GCD block. Own quit and signal entry points now schedule the native terminate call through `RunLoop.main.perform`, outside those executors. Cmd-Q/native events use the same delegate. The earlier failed scratch-only fixture attempts are not counted as passes.
- The actual native Subler engine was rebuilt with Xcode, then its strict deep signature verified. Offline replay verifies pristine pinned upstream sources + original patches + the supplemental graceful-quit patch exactly reconstruct the reviewed checkout; remux/HEVC/DV implementations are unchanged.
- Packaging preflight: 5 tests pass. Existing running-target permission contracts: 2 pass. Shutdown and Apple TV wiring contracts and `git diff --check` pass.
- Final release checks: strict deep signature, source/bundle version and binary parity, embedded-engine byte-for-byte inventory including notices/framework links, relocation without sibling, ignored inherited target override, and missing/non-executable helper refusal. Readbacks are saved beneath `dist-standalone/evidence/graceful-build11`.

## Reproduce safely

Use an explicit scratch TMPDIR. The following integration launches generated fixtures only, not the production queue or real Subler:

```sh
TMPDIR="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" python3 scripts/test-background-shutdown.py
TMPDIR="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" python3 scripts/shutdown-appkit-smoke.py
python3 scripts/shutdown-contract.py
python3 scripts/appletv-ui-contract.py
```

Prepare/rebuild the native engine with `scripts/prepare-local-subler.sh` and `scripts/build-local-subler.sh` as documented in `local-subler-background.md`; preparation now also applies `patches/local-subler/graceful-quit.patch`. Build this outer app with `SUBLER_BUILD_EMBEDDED_ENGINE=1`, `SUBLER_BUILD_ENGINE_SOURCE=<new reviewed engine>` and `SUBLER_BUILD_APP=<new outer .app path>`. `scripts/graceful-release-evidence.py` aggregates signed-release readback and the printed AppKit evidence directory without launching media processing.

## Limits

No user engine/Automation instance was stopped or relaunched, no user movie was processed, and no SMB write occurred. The shutdown integration injects delayed workers; it does not claim to have repeated a real in-flight movie conversion or NAS publication. Those code paths and their earlier acceptance evidence are preserved, not re-certified here. The real upstream engine's production queue was deliberately not used as a shutdown test fixture. A future live-use quit can therefore leave an engine with old/unknown queue records running, by design, with an explanation in the log. macOS Automation consent remains revocable and may be required after moving/re-signing the app; no TCC database manipulation or consent-reset/rebuild loop was used. Ad-hoc signing is not Developer ID signing or notarization.
