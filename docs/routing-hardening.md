# Routing hardening handoff — t_51f9706b

Baseline: `7fd4c0a` (contract) on top of the existing routing/build fix `48024b6`.
The embedded two-key selection, environment compatibility, distinct caller IDs,
shared settings/lock and diagnostic/UI API were already implemented; they were
preserved, not reimplemented. No AGENTS.md exists at repo root or its ancestors.

## Closed gaps

- A local app with correct metadata but no executable, a non-executable file,
  or a directory as its executable used to pass validation. A scratch test with
  an injected empty running-app lookup reproduced all three failures. Runtime
  now requires a regular executable file before checking running-app paths.
- Packaging preflight now rejects these same three unusable engine states
  before compiling or modifying the caller bundle. Its negative tests failed
  against the old script, then passed after the fix.
- Installed-mode diagnostic previously returned `valid=true` even when the
  LaunchServices lookup returned nil. A deterministic lookup seam reproduced
  that false success; it now returns an explicit missing-target error.
- Internal injection seams isolate tests from the user's running background
  engine and installed-app lookup. Public initializers/methods, Encodable keys,
  labels/status and the UI seam remain unchanged. The production resolver still
  performs the actual running-path safety check.

## Verification

All commands executed from the repository; Swift commands used
`TMPDIR=/Users/mathiasbunnens/.hermes/cache/scratch`.

- `swift test --filter 'SublerBundleTargetTests|EngineDiagnosticTests|AppVersionTests|SublerBackgroundTests.testInstalledDefaultIsUnchanged|SublerBackgroundTests.testInvalidLocalOptInNeverFallsBack|SublerBackgroundTests.testBackgroundTargetsTokenNotWindow|SublerBackgroundTests.testDifferentRunningLocalBuildIsRejected'`
  passed 19 tests, zero failures/skips. This compiled the core and debug app.
  Covers normal/local defaults, signed-key precedence even if malformed,
  environment presence (including empty), missing sibling, current-bundle
  initializer, executable validity, installed lookup, diagnostic local path
  retention, provenance, UUID targeting and different-running-build refusal.
- `python3 scripts/test-bundle-packaging.py`: 3 tests passed. Tests execute the
  real packaging script against scratch bundles; ps/codesign are inert test
  doubles, so these tests establish metadata/preflight behavior, NOT signatures.
- `python3 scripts/configure-app-bundle.py --app "$PWD/dist-local/Subler Automation Local.app" --local-engine --check-only`
  passed against the real co-local engine, including real strict/deep codesign.
  This does not write, build or sign either bundle.
- `python3 scripts/test-local-subler-contract.py`: 4 native source contracts passed.
- `python3 scripts/permission-running-target-contract.py`: 2 source contracts passed.
- `git diff --check`: passed.

No redundant full-suite run; media/native patch files are unchanged from the
previous validated baseline. No HEVC/HDR/DV/audio behavior was changed or newly
claimed verified by these routing tests. The existing bundle-5 signature and
end-to-end evidence remain separately documented in routing-build-contract.md
and the parent card.

## Integration boundary

No bundle rebuild/resign, version bump, launch, Apple Event, permission request,
conversion, production settings/queue change or process termination occurred.
User PIDs 10111 and 74216 were observed still running at their original start
times. Pre-existing .vscode/ and .worktrees/ stay outside this change.

The existing signed build 5 still contains `48024b6`, not this new hardening.
The integration lane t_f5d083e5 owns the final incremented build/signature and
Finder/LaunchServices acceptance; it must compile the final combined core/UI
revision and verify its signed provenance. Packaged end-to-end/TCC, generated
media decoding/seek, visual checks, TV and user validation are not completed by
this routing-only card. Do not release the duplicate/server dependency early.
