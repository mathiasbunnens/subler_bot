# Integrated local build 6: LaunchServices acceptance

Measured 2026-10-20, after the user confirmed granting Automation access.
Task: `t_f5d083e5`. Private local use only; no push, publication or production rollout.

## Deliverable and opening

- Caller: `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Automation Local.app`
- Version 1.1.0, build 6; embedded source commit `aa830eae0165b9a96e67362e7635e5588a0da986`, sourceDirty=false.
- Caller ID: `com.mathiasbunnens.SublerAutomation.Local`.
- Keep sibling `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Background.app` in place.
- Engine ID `local.sublerautomation.Subler`, background protocol 2; native Subler source `bf8dc30bb47d615ce6646e87f2dad3165731c141`, MP42Foundation `9c89c9a0c9d9b07b801e72c7055212633d1ef569`.
- Both signatures are ad hoc, not Developer ID or notarized. Both passed `codesign --verify --deep --strict` before and after the test.
- Caller executable timestamp: 2026-10-20 10:28:29; engine: 2026-10-19 15:47:11. No rebuild, re-sign or replacement during this acceptance run.

For normal use, explicitly quit the old Automation app only when its work is idle, then double-click `Subler Automation Local.app` in Finder. Do not open the old `Subler Automation.app`. No engine-selection shell variable is required. Existing settings and the shared instance lock are retained. Do not launch normally while the old production instance is processing. The test described below ran only against an isolated TEST_ROOT.

## Proven cause versus remaining limits

The historical default resolver selected installed `org.galad.Subler` when the shell opt-in was absent; the old delivered bundle lacked the signed engine-selection keys. That explains why an ordinary Finder launch did not select the repaired native route. The signed Local configuration now selects the exact co-local sibling and fails closed if absent; routing and native HEVC packaging are distinct fixes. Historical installed-native export omitted the safe force-hvc1/normalization options; see `local-subler-background.md` for that separate media investigation.

A separate blocker then affected the new caller: TCC logs explicitly identified Local → local Subler and requested consent. This run succeeded using the SAME signed build 6 after human consent, so no additional routing change or permission bypass was needed. This does not establish the exact effective target of the old long-running caller, whose environment was deliberately not inspected.

## Actual packaged end-to-end execution

Command, from the repository:

```sh
export TMPDIR=/Users/mathiasbunnens/.hermes/cache/scratch
swift scripts/local-subler-observe.swift python3 scripts/test-bundle-engine-launch.py \
  --app "$PWD/dist-local/Subler Automation Local.app" \
  --generated /Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/local-subler-nhk4f71p/generated.mkv \
  --probe /Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/local-subler-nhk4f71p/probe
```

Exit status 0. Evidence root: `/Users/mathiasbunnens/.hermes/cache/scratch/subler-bundle-launch-5eo_ctvf` (scratch evidence may expire).

- Actual signed caller launched through LaunchServices (`open`), not a substitute test binary. Only TEST_ROOT overrides storage/permission preflight; no engine-selection environment override.
- Diagnostic: build 6, embedded commit aa830ea, valid=true, background=true, exact caller and sibling paths/identities above.
- Real Apple Events imported/converter-queued a two-second generated MKV and produced a validated MP4 under the owned Temp root. Job `4422444D-55FC-4F15-9D37-19EA0ABEF535` reached waitingForServer intentionally: no server configured and no publication attempted.
- Manual fixture metadata `Generated Finder launch`, year 2026 verified; source SHA-256 unchanged.
- AVFoundation: 48 decoded image buffers, reader completed (`status=2 error=(null)`); seek probe returned three images (`status=1 error=(null)`, intentionally stops after those images).
- Output format description: hvc1, 320×180, 10-bit, BT.2020, mastering-display and content-light metadata visible.
- Independent ffprobe: source and output each contain one HEVC video and one mono AAC audio, output tags hvc1/mp4a. Durations 2.023 s MKV / 2.020 s MP4; no claim of exact rational MKV timestamp identity.
- External observation: 538 samples, zero engine windows, zero engine-frontmost samples; installed Subler queue digest unchanged.
- Harness stopped only its own scratch caller. Original engine PID 10111 (started Oct 19 15:48:25) and old caller PID 74216 (Oct 19 17:18:24) remained running unchanged afterward. No newly orphaned osascript was present; the unrelated gateway JavaScript osascript remains untouched.
- Production settings were not opened for editing, reset or migrated. The harness seeds and persists settings/jobs only in its scratch root; the diagnostic executes before production storage initialization.

The first invocation failed at the diagnostic-only `open -W` stage with exit 1 although its complete diagnostic JSON was valid (root `subler-bundle-launch-xvd1e6zb`). This immediate-exit LaunchServices race was already observed historically. A fresh invocation passed all stages above. No consent reset or rebuild was used to work around it.

## Reused verification and explicit non-claims

No source/binary change since the integration build; no justification to repeat the 169-test full suite. Parent handoffs retain the executed 19 targeted Swift tests, three packaging tests, four native contracts, permission contracts, Settings presenter/contracts and successful compilation. Previous release validation covered real-bundle version/Mach-O parity and a signed copy without its sibling failing closed; this acceptance run did not duplicate them.

The unchanged engine's earlier 35 generated native checks cover safe HEVC normalization, retained NALs, HDR metadata, rich six-audio/three-fallback mapping, chapters, subtitles and malformed/changing-parameter refusal. Those are reused native results, NOT a claim that this two-track LaunchServices fixture exercises every rich relationship. Historical bounded DV8.1 decode/preservation evidence is also reused; no private excerpt or whole user film was touched or regenerated.

Not tested here: TV playback, Dolby/HDR display certification, HDR10+ display certification, live SMB publication, real user films, production activation, interactive/pixel layout of the new About section and final user acceptance. Settings presenter/compilation and packaged diagnostic are verified separately; they do not prove visual layout. TEST_ROOT injects permission preparation, while actual Apple Events and their successful conversion are real. Sampling cannot prove every possible future engine path remains windowless. Re-signing or changed macOS grants can require renewed consent.

This report-only commit does not change the embedded executable provenance: the usable bundle remains aa830ea/build 6.
