# Routing evidence and downstream contract — t_85faf96f

## Scope and baseline

Investigation only: no conversion, Apple Events, permission request, activation, installed-app replacement, preferences/queue read or write, or user-process termination. No process environment was read. No AGENTS.md was found at repository root or its ancestor directories. Required safety/debugging/TDD skills and local-subler-background.md were read.

The task's expected baseline is stale: main already contains `48024b604acb14a92d6471ce40a7499f0a0b748c` after `1da55a9`. Do NOT reimplement or discard this existing correction. The downstream routing/UI tasks should audit and close remaining contract gaps, not replay the original fix. Do not rebuild/resign build 5 merely because these diagnostic documents change HEAD: its signed provenance must continue to identify the code actually compiled.

## Observed evidence

Raw allowlisted evidence: `docs/routing-selection-evidence.json`; reproduction: `TMPDIR=<owned absolute scratch> python3 scripts/diagnose-routing-contract.py`.

- PID 10111 remains the co-local Background binary, started 19 October 2026 15:48:25; PID 74216 remains the OLD `dist-local/Subler Automation.app`, started 19 October 17:18:24. These are not the new Local caller. Neither was restarted or modified.
- `dist/Subler Automation.app` and old `dist-local/Subler Automation.app` both identify as `com.mathiasbunnens.SublerAutomation`, version 1.1.0/build 4, without embedded engine selection. All four inspected bundles pass `codesign --verify --deep --strict`; signatures are ad hoc, not Developer ID/notarization.
- The new `dist-local/Subler Automation Local.app` is 1.1.0/build 5, ID `com.mathiasbunnens.SublerAutomation.Local`, signed commit `48024b6…`, sourceDirty=false. It contains the two explicit background selection keys.
- Engine ID is `local.sublerautomation.Subler`, version/build 1.9.5, protocol string `2`, LSBackgroundOnly=true. Binary mtimes are captured as epoch values in evidence; process start times and on-disk mtimes do NOT prove the source loaded by an old running process.
- The EXACT historical `SublerTarget.swift` from 1da55a9 was compiled in scratch with inert stand-ins for unrelated collaborator types. Calling only its initializer/selection properties with the named opt-in absent yields `org.galad.Subler`; explicit opt-in yields `local.sublerautomation.Subler`. No validation/Apple Events were invoked in the historical probe.
- The actual signed build-5 executable's `--diagnose-target`, with the named shell override removed, yields background=true, valid=true, correct sibling absolute path and local engine ID. Existing bundle test also copies it into scratch without its sibling and confirms background=true, valid=false, no fallback.
- Five `SublerBundleTargetTests` pass: normal default/environment compatibility, bundle precedence, malformed/missing fail-closed, actual default initializer, sibling selection without environment.

Conclusion: the old bundle's default-launch routing defect is proved, as is the correction in build 5. The exact effective target selected INSIDE PID 74216 is not proved: its environment was deliberately not inspected, and its historical binary has no safe selection-only entry point. Do not execute the old binary with an unknown diagnostic flag; it could initialize the live queue. These selection results do not prove the reported MP4 failure's full causal chain. Existing parent-card evidence identifies a separate new-caller TCC prompt blocking packaged end-to-end tests; no such test was repeated here.

## Normative selection/build contract

1. Use signed embedded configuration, NOT a new persistent setting. Preserve all existing user settings and the existing queue/support paths unchanged. No migration, default reset or new engine preference is needed.
2. Local package embeds BOTH exact strings before signing:
   - `SublerAutomationEngine = background`
   - `SublerAutomationBackgroundRelativePath = ../Subler Background.app`
   Resolve only the named co-local sibling from the caller bundle's parent; never CWD or LaunchServices name lookup. Moving both apps together remains supported.
3. Precedence: presence of EITHER embedded key owns selection. Both must have the exact supported values above. Unknown engine, wrong type, missing counterpart or empty string is an explicit invalid local configuration. Ignore inherited environment even when that configuration is invalid; do not rescue it by environment or installed Subler.
4. Only when BOTH keys are absent, preserve `SUBLER_AUTOMATION_LOCAL_SUBLER_APP` as a development compatibility override. Absent key means installed Subler (`org.galad.Subler`); present value, including empty, means local selection requiring validation. Accept only absolute .app paths; empty/relative/missing/wrong local targets fail closed. Do not add a new environment variable or interpret an empty value as opt-out. Inject synthetic dictionaries for tests; never dump a process environment.
5. Local runtime validation requires existence and a usable executable, exact `local.sublerautomation.Subler` identity, protocol string `2`, LSBackgroundOnly=true, and no same-ID running instance at a different canonical path. Report errors without launching or terminating either candidate. Existing checks cover metadata and running-path mismatch; downstream routing owner must test/close the usable-executable gap if Foundation Bundle validation does not cover it. Validate signatures strictly during packaging/delivery; a valid ad-hoc signature is integrity evidence, not trusted publisher authentication.
6. Any local configuration/validation failure blocks permission preparation and media work before Apple Events. Never silently use `org.galad.Subler`, never report local configured as local operational on error. Permission preparation and all service instances must consume this SAME resolver, not their own defaults.
7. Normal packaging keeps `dist/Subler Automation.app` and `com.mathiasbunnens.SublerAutomation`; it contains neither background key. Local packaging uses `dist-local/Subler Automation Local.app`, `com.mathiasbunnens.SublerAutomation.Local`, distinguishable display name, and build >=5 (increment only for changed executable/packaging). Never overwrite a running bundle. Keep Background ID/protocol unchanged; no media normalization/native patch changes in this routing task.
8. Distinct caller IDs require distinct macOS Automation consent; old caller/Terminal consent is not proof. Keep existing shared settings and single-instance lock so two callers cannot process the same live queue. Local Finder Services remain omitted to avoid competing service registration. Do not run the new caller normally while the old caller owns the live lock.

## Frozen diagnostic/UI seam

Keep the existing `EngineDiagnostic` initializer, Encodable keys and presentation accessors as the shared seam. The UI owner must not implement a second resolver or parse raw Info.plist selection keys.

- `bundleIdentifier`, `build`, `commit`, `sourceDirty`, `executablePath`: caller provenance, never substitute current Git HEAD for signed build commit.
- `background`: configured selection mode, NOT proof of a running/working engine.
- `targetBundleIdentifier`: selected target identity, including on failure.
- `applicationPath`: configured local absolute path or installed app lookup result. Keep configured local path on failure; do not substitute installed app path.
- `valid`, `error`: current read-only resolution/validation result, not TCC grant, process health, media compatibility or completed conversion. A configured local missing engine must be background=true/valid=false with explicit error. Installed mode must not claim a verified usable target when installed lookup is absent; current EngineDiagnostic sets valid=true after a nil local URL, so routing owner must close/test this diagnostic gap.
- `label`, `status`: shared presentational descriptions; retain availability for UI. Distinguish 'selected/configured' from 'verified target' and from 'running engine'; no claim of active running version from bundle metadata alone.
- `AppVersion.current.label/details`: existing sole UI version source (short version, build and signed commit). Combine this with `EngineDiagnostic` for explicit Local/normal name, full commit, dirty indicator, caller identity/executable and selected target/path/error. No mandatory JSON schema expansion is required; if adding keys later, make additions backward-compatible and coordinate first.

`--diagnose-target` must remain before settings/queue/lock initialization, request no permissions, launch no engine and send no Apple Events. Allowlist only the above data; no filenames from jobs, settings dumps, credentials or raw environments. UI may refresh validation on explicit presentation; do not create idle process polling or prompt loops.

## Ownership and next checks

Routing owner t_51f9706b: `Sources/AutomationCore/SublerTarget.swift`, `EngineDiagnostic.swift`, `AppVersion.swift` if provenance formatting needs shared support; bundle Info.plist, `build.sh`, `scripts/configure-app-bundle.py`, bundle/core/version tests. Audit existing 48024b6, add targeted failing tests for remaining executable/installed-diagnostic gaps before code changes. Keep this contract's priority and fail-closed matrix.

UI owner t_a7655067: `Sources/SublerAutomation/Views/SettingsView.swift` and UI/presentation contracts only. Existing build 5 already has engine/about UI; verify labels and configured-vs-validated errors rather than rebuilding another implementation. Consume existing shared APIs so parallel work does not depend on unmerged new symbols. Coordinate AppVersion formatting changes with routing owner; do not edit packaging/core files independently.

Integrator/release: serialize builds, read parent-card TCC evidence, and run only authorized generated/scratch isolated launch checks when consent can actually be supplied. This investigation is complete even though packaged end-to-end acceptance remains blocked/unfinished in the parent. Do not launch the duplicate/server project or release its dependency prematurely.
