# Standalone build 9 — packaging verified, native acceptance blocked

Task: `t_9b9db00c`. Private local candidate, no installation, publication or push.

## Candidate

`/Users/mathiasbunnens/Downloads/SublerAutomation/dist-standalone/Subler Automation.app`

One app contains the existing reviewed native engine at `Contents/Helpers/Subler Background.app`. No sibling is needed. Both display and bundle names are `Subler Automation`, version 1.1.0/build 9. Caller identity remains `com.mathiasbunnens.SublerAutomation.Local`; engine identity remains `local.sublerautomation.Subler`, background protocol 2. The engine copy retains its existing ad-hoc signatures, frameworks, resources and notices unchanged; the outer bundle is signed last. No Developer ID or notarization is claimed.

Build from the repository:

```sh
SUBLER_BUILD_SCRATCH="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" \
SUBLER_BUILD_EMBEDDED_ENGINE=1 ./build.sh
```

`SUBLER_BUILD_ENGINE_SOURCE` optionally selects the reviewed source bundle at build time (default `dist-local/Subler Background.app`). It is not needed at runtime. `SUBLER_BUILD_APP` selects another output path. Packaging rejects outputs with any running executable inside, including the nested engine, before mutation. Existing normal and legacy sibling build modes remain supported. The single shared resolver accepts only the two reviewed relative layouts and signed selection overrides any inherited engine environment variable. About distinguishes the standalone/embedded variant without another resolver. Settings, queue, locks, permission persistence and replacement/backup logic are unchanged.

## Executed evidence

- Release compilation succeeded; actual outer bundle and nested engine passed `codesign --verify --deep --strict`.
- RED first: new embedded resolution and packaging tests failed before implementation.
- Swift `SublerBundleTargetTests|EngineDiagnosticTests`: 11 tests passed. Coverage includes embedded layout at an accented/spaced path, environment precedence, usable executable, missing/non-executable/directory refusal, and conflicting running engine rejection. The positive nested validation uses an injected empty running-process list in the unit test only, never the delivered app.
- Swift `SublerBackgroundTests`: 8 discovered, 4 passed and 4 explicit native integration tests skipped for lack of fixture opt-in. No claim those skipped tests passed.
- Packaging Python suite: 5 tests passed, including clean name/local identity, embedded content, legacy/normal mode compatibility, unusable engine and running-nested-output preflight refusal.
- About presenter contract passed, including embedded label/variant; permission running-target contract: 2 tests passed. `bash -n build.sh` and `git diff --check` passed.
- Actual packaged executable diagnostic was run, then a copy of the entire app was made under a fresh scratch `Applications simulées` directory in an accented/spaced path with no engine sibling. The copied signature passed strict/deep verification. Foundation's decomposed Unicode spelling was compared using filesystem identity: both reported caller and nested engine refer to the copy, not the original. Inherited engine environment override was ignored. Removing the copied engine or removing execute permission correctly failed closed before considering running-engine state.
- Inventory comparison: all 376 native files/symlinks match the reviewed source byte-for-byte, including native Credits.rtf notices and frameworks. No native media repair or dependency code changed.
- The actual candidate was also launched through LaunchServices with `--diagnose-target`. Its JSON reported build 9, embedded=true, exact nested URL, and the same explicit running-engine conflict. `open -W` printed an immediate-exit GetProcessPID warning but returned 0 and produced the diagnostic JSON. This is diagnostic launch only, not a successful conversion.

Evidence logs live in `dist-standalone/evidence/` (ignored generated output). Runtime provenance is stamped from the local source commit into the signed Info.plist; `sourceDirty` must be false for the final candidate rebuild after committing.

## Genuine blocker — do not bypass

Old engine PID 10111 remains running from `dist-local/Subler Background.app` (started October 19). The resolver correctly reports `valid=false`: a different local engine with the same identity is running. It was neither terminated, modified nor used. Do not weaken this guard, change engine identity, edit/reset TCC, or stop the old engine automatically to get a green test.

A human must finish any old work and explicitly quit that idle engine (and old Automation UI if active), or authorize that specific idle shutdown, then unblock the task. Only then rerun strict packaging diagnostic without `--allow-running-conflict` and native acceptance against a scratch relocated copy. If macOS actually asks for renewed Automation consent, obtain human consent; do not bypass it.

Remaining acceptance:

1. Real relocated copy reports `valid=true` with its nested target, no sibling and no environment selection override.
2. LaunchServices scratch-only synthetic MKV conversion through the real nested engine, independent hvc1/image/seek inspection, exact running engine bundle URL, and external zero-window/zero-focus observation.
3. Recheck signatures and final provenance. Reuse unchanged build 8 replacement/backup and native media evidence; do not write SMB or touch user films merely to retest packaging.

The existing harness is `scripts/test-bundle-engine-launch.py`, run under `scripts/local-subler-observe.swift`, with generated synthetic fixture/probe paths verified before use. Run against a new relocated scratch copy and stop only the scratch caller it owns. Permissions preflight is injected by TEST_ROOT, actual Apple Events/conversion are not. Keep exact engine-URL evidence and gracefully stop only an engine started/owned by that scratch test before testing a different copy; never target the original PID 10111.

TV playback, interactive About layout and real production migration are not certified. No user film, NAS transfer, production settings/queue mutation, application installation or source publication was performed.

Once remaining acceptance succeeds: move only `Subler Automation.app` into Applications, and open the outer app only; do not launch or separately move the internal engine. Until then this is a built and packaging-verified candidate, not a fully accepted release.
