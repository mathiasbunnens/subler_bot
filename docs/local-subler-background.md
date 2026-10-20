# Local-only windowless Subler route

Status: native route implemented and exercised locally; build 5 now selects it from signed bundle configuration on Finder/LaunchServices launch, without a shell variable. PRIVATE LOCAL ONLY, not installed or published. The new caller's end-to-end launch test is awaiting a macOS Automation consent (see below); it is not claimed complete. This supersedes the implementation limitations in `hevc-packaging-investigation.md`, not its historical diagnostic results. No existing user MP4 was replaced or whole film processed.

## Cause and correction

Installed Subler 1.9.5's document-to-queue AppleScript handler omits `MP42ForceHvc1`, unlike the GUI save-options path. Its script dictionary cannot pass that option. Standard scripted save returned -1708; custom save-as retained `hev1` and failed AVFoundation decoder creation (-11833/-12906). Merely renaming the sample entry is insufficient: tested inputs carry VPS/SPS/PPS in-band, and the earlier FFmpeg experiment lost `fall` associations.

The separate local build sends the native queue both force-hvc1 and strict-normalization options. MP42Foundation validates hvcC and each complete length-prefixed sample before editing; it removes only byte-identical copies of configured VPS/SPS/PPS, leaving VCL, SEI, RPU and other retained NAL bytes untouched. Native hvc1 writing supplies complete parameter arrays. Changing/ambiguous/malformed parameter sets, nonzero NAL layers, parameter-only samples, enhancement-layer configurations, and Dolby Vision configurations other than supported single-layer 8.1 are refused. There is no encode, SDR conversion, audio conversion or FFmpeg repackager fallback. Native write failures propagate as failed queue items; a failed partial scratch output is not a publishable conversion.

Import uses MP42's importer directly, rejects conversion-requiring/nonmuxable tracks and multiple sample descriptions, imports all supported tracks/metadata, and returns a native owned UUID token without constructing a document window. Metadata candidate lookup/application and the existing owned queue workflow use that token instead of a window ID. Enqueue closes only that document. Protocol v2 tokens are generated independently of the native document counter and never intentionally reused after restart. Native targeting rejects stale/malformed explicit tokens without falling back to another document. Presence/close uses the same UUID; stale close is harmless. Swift ownership keys include the UUID and allocate separate service-local IDs, so preparing a replacement cannot overwrite an old ownership record. Conversion checks native presence before queue recovery and native enqueue rechecks the exact UUID.

A second bug was reproduced deterministically: after the last item completed, a new append/start could fall between the empty scan and the transition to idle. The only start was dropped. The queue now commits its empty/idle transition under the same array lock; a barrier-based regression failed before the change and passes after it. No polling/repeated-start workaround was added to the Swift service.

## Isolation and opt-in

- Bundle ID: `local.sublerautomation.Subler`; protocol marker: `SublerAutomationBackgroundProtocol = 2`. The Swift target rejects the old integer-token v1 build.
- `LSBackgroundOnly`, prohibited activation policy; no document, queue or activity-window construction during the tested route. Automatic updater controller/feed disabled.
- Preferences use the distinct bundle ID; queue/logs/presets/OCR files use `~/Library/Application Support/SublerAutomationLocal`, never the installed app's `Subler` directory.
- Ordinary `dist` builds and unbundled CLI default to `org.galad.Subler`; the distinct local build selects the co-local background sibling through `SublerAutomationEngine=background` and `SublerAutomationBackgroundRelativePath=../Subler Background.app` in its signed Info.plist. This configuration wins over inherited environment variables. `SUBLER_AUTOMATION_LOCAL_SUBLER_APP` remains a development compatibility opt-in only when no bundle selection is present. Missing/malformed local config or missing/wrong sibling fails closed. A running different local build is rejected rather than silently reused or terminated.
- Permission preparation targets the same selected bundle ID. macOS may require a separate Automation grant for this build/caller and may prompt again after signing/identity changes; no permission bypass or blanket no-prompts promise is made. No Accessibility grant is used by this route.
- Production instance, watched folders, normal Subler app/queue and TV playback were not launched/restarted/mutated to enable this route. Existing ready/working-foreign-item, destination/no-overwrite and stable queue-item-ID checks remain in place.

Current local bundles (both ad-hoc signed and strictly verified):

    /Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Background.app
    /Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Automation Local.app

Finder launch, only after explicitly quitting the old Automation instance when idle and reviewing its configured watched folders:

    open "/absolute/path/dist-local/Subler Automation Local.app"

Do not open the old `dist-local/Subler Automation.app` (build 4, same identity as the normal dist build). Build 5 is `Subler Automation Local`, ID `com.mathiasbunnens.SublerAutomation.Local`; Settings → À propos displays the actual build, commit, executable and selected engine/path/error. No background-engine `activate` call was added. Settings/queue remain in the existing `Subler Automation` support directory; the shared lock prevents concurrent processing and now explains an already-running instance instead of silently exiting. The local app omits Finder Services registration to avoid competing with the ordinary build; add films through the app UI.

The old Automation PID 74216 and background PID 10111 were left running untouched. Their on-disk executable timestamps were 15:52:51 and 15:47:11 respectively on 19 October; timestamps alone do NOT establish which uncommitted source they contained. The regression was independently reproduced from bundle metadata and default-target code, not by dumping process environments.

Read-only diagnostic (also safe while the old Automation is running):

    "/absolute/path/dist-local/Subler Automation Local.app/Contents/MacOS/SublerAutomation" --diagnose-target

This runs before settings/queue/lock initialization, requests no permissions, and sends no Apple Events. It reports only allowlisted nonsecret build/selection fields. CLI and actual LaunchServices diagnostics selected the reviewed sibling successfully. Missing sibling is an error, not a switch to installed Subler.

The generated-only real release launch reached `importing`, then a new macOS consent was required. TCC logs identified caller `com.mathiasbunnens.SublerAutomation.Local` and target `local.sublerautomation.Subler`, then `Prompting for access ...`. No permission was clicked or bypassed. Only the owned scratch Automation PID was stopped at the test deadline. Human consent is needed before rerunning the packaged end-to-end test; the previous caller/Terminal grants do not authorize this new caller. Re-signing ad-hoc builds can require consent again. Do not claim this test passed based on the separate Terminal/native tests.

Test the app only with an explicit isolated `SUBLER_AUTOMATION_TEST_ROOT`; a normal app launch can process watched user media. Do not open the background bundle in the GUI to select films; its public test commands are for owned documents only.

## Reconstruct and build

Native sources remain separate Git repositories, ignored by the main repo. The main repo tracks reviewable source patches, not a giant binary checkout. Source pins:

- SublerApp/Subler: `9077b6d149be621ff7d7b0d8eb46839a56610844`.
- SublerApp/MP42Foundation: `bfa477b799ce55716f744638e6dfe3f23d39c5d7` (explicit override of Subler's older submodule pin).
- SublerApp/contrib: `debd14253dba88addfd918d144fb7872a9e075f7`.
- Upstream Xcode project pins Sparkle 2.9.6 exactly.
- Local native commits: Subler `bf8dc30`, MP42Foundation `9c89c9a`; neither pushed.

On a fresh checkout with no `vendor-local/Subler` directory:

    bash scripts/prepare-local-subler.sh
    LOCAL_SUBLER_BUILD_ROOT="/absolute/scratch/local-subler-derived" bash scripts/build-local-subler.sh
    SUBLER_BUILD_LOCAL_ENGINE=1 SUBLER_BUILD_SCRATCH="/absolute/scratch" bash build.sh

`prepare-local-subler.sh` refuses to reset/overwrite an existing source checkout. It clones the public sources, checks out exact revisions, initializes the pinned contribution libraries and applies the two patches. Requires network for a new checkout and Xcode/SPM dependencies. The build script requires an absolute derived-data path, builds arm64 Release, patches only its newly built bundle identity/background flags, and ad-hoc signs/verifies it. It never installs to `/Applications`. Copy a completed bundle to a distinct owned `dist-local` path before opting in; do not replace a running app. These are source-reproducible builds, not a claim of byte-identical Xcode output or Developer ID/notarized distribution.

`python3 scripts/test-local-subler-patches.py` reconstructs every patched file offline from the pristine pinned Git objects and proves byte equality with the reviewed native checkout. Both Subler and Automation have been built and signature-verified repeatedly; native patches were replayed successfully (12 Subler files, 4 MP42Foundation files).

## Verification and limitations

Build-5 regression verification: the previous bundle fails `test-bundle-engine.py` at the exact missing-Finder-selection assertion. New source executes 18 targeted Swift tests with zero failures (one online-metadata test deliberately skipped), including live generated conversion, stale UUID rejection, bundle precedence/default/invalid-config tests and visible local build provenance. After adding the orphan-config negative case, the 10 version/bundle tests pass again. `settings-ui-contract.py` passes five contracts; `version-contract.py` passes all three against the actual release (including unsigned-Mach-O parity). The paused app smoke passes watcher, persistence, deduplication, shared-lock, restart recovery and source preservation. The new engine tab compiles; its live interactive layout has not been independently verified.

The 35 native generated-only checks were rerun successfully: MP4, MKV and rich inputs each decode 48 images and seek three images; fallback/chapter/subtitle/HDR identities and refusal tests remain green. External observations report zero background windows/frontmost samples and the installed Subler queue unchanged. Native token/patch reconstruction contracts pass. This does not turn the blocked new-caller packaged launch into a pass.

Repeat the new-caller test only with a human available for macOS consent. First run the native generated fixture command below, then use its reported scratch directory for `--generated` and `--probe`:

    python3 scripts/test-bundle-engine.py --app "$PWD/dist-local/Subler Automation Local.app"
    swift scripts/local-subler-observe.swift python3 scripts/test-bundle-engine-launch.py \
      --app "$PWD/dist-local/Subler Automation Local.app" \
      --generated "/reported/native/evidence/generated.mkv" --probe "/reported/native/evidence/probe"

The launch test invokes the unmodified release via LaunchServices; only the settings/queue root is overridden. It seeds a native `MovieJob` for a generated fixture with manual metadata, uses no SMB configuration, verifies AVFoundation images/seek and preserved source, and stops only its own scratch app PID. It never stops the old Automation or background engine. Test-root permission preflights are injected, but the real Apple Events still require macOS consent; no result is fabricated if that blocks. Keep `TMPDIR` at an owned absolute scratch path.

`docs/local-subler-evidence.json` records the measured results without private media names.

- Full Swift suite: 169 tests, 16 opt-in/integration skips, 0 failures. Explicit live background suite: 8 tests, 0 skips/failures, including online metadata selection, persisted title/year validation, manual conversion, closing one of two owned documents, and rejection of stale candidates/metadata/convert/close without affecting a replacement document or creating an output/queue entry.
- Ownership regression executes the unchanged native resolver with AppKit stand-ins and deterministic process/counter reuse (old and replacement native ID both 1). `python3 scripts/test-local-subler-token.py --baseline` fails against the old integer-token handler; the current handler passes, including explicit stale/malformed tokens with valid document/frontmost fallbacks supplied. No user process is restarted for this regression. Live Apple Events separately exercise the actual rebuilt handlers and retained Swift ownership records after an owned document is externally closed.
- Generated HDR10 MP4, MKV and rich MP4: each yields 48/48 AVAssetReader image buffers, successful reader completion, and three images after seek. All 35 native preservation/refusal checks pass, including rejection of a changed VPS rather than reporting completion.
- MP4/rich: retained NAL hashes and rational PTS/DTS/durations unchanged; every audio packet and timing unchanged. Rich fixture has six audios, three `fall` references, chapters, subtitles, artwork, track flags, alternate groups, languages and edit lists; tested identities preserved.
- MKV: retained payloads unchanged. Container time-base conversion is not rationally identical: timestamps remain within one source tick (1 ms), and agree with the unchanged native importer baseline. Do not claim bit-exact MKV timestamp identity.
- Authorized two-second DV8.1 evidence from the earlier run is deliberately reused: original excerpt failed Apple decoder startup; normalized output produced all 50 images plus seek, with retained NAL/VCL/SEI/RPU hashes, all audio packet timing and `dvvC/colr/mdcv/clli` preserved. The MP42 normalization code is unchanged from that run. Private excerpts/probes were deleted; the source stat was unchanged. The extracted fixture does not contain the film's original fallback/chapter/subtitle relations: those are covered separately by the generated rich test, not falsely claimed as tested on the whole film.
- Address/undefined sanitizer C vectors cover retained SEI/RPU/VCL, idempotence, every truncated configuration, malformed lengths, changing parameter sets, layers and forbidden/temporal bits. Four static headless/storage/source contracts pass. Deterministic queue-race regression passes.
- Independent NSWorkspace/CGWindow observations sampled the actual native fixture and Swift integration runs: zero local windows, zero local-frontmost observations; installed Subler queue digest unchanged. Native state observations also report `0|false|2|N`. Observations are sampled, not a proof about every future UI path or arbitrary unsupported commands.
- No whole-film conversion, live QuickTime UI, Apple TV playback, Dolby display certification, HDR10+ display certification, SMB publication or production rollout is claimed. The real QuickTime engine evidence is AVFoundation decoding/seek, not a claim that an audio-only 'playable' flag proves images.

Generated-only repeat commands (macOS/Xcode, FFmpeg/FFprobe at `/opt/homebrew/bin`):

    export TMPDIR="/absolute/owned/scratch"
    python3 scripts/test-local-subler-contract.py
    python3 scripts/test-local-subler-queue.py
    python3 scripts/test-local-subler-token.py
    python3 scripts/test-local-subler-patches.py
    clang -fsanitize=address,undefined -I vendor-local/Subler/MP42Foundation/MP42 \
      scripts/test-strict-hevc.c -o "$TMPDIR/strict-hevc-test"
    "$TMPDIR/strict-hevc-test"
    swift scripts/local-subler-observe.swift python3 scripts/local-subler-background-repro.py \
      --app "/absolute/path/dist-local/Subler Background.app" --scratch "$TMPDIR" --authorize-local-build

The fixture harness refuses pre-existing documents or any foreign ready/working item. It does not clear completed entries or kill an application. The live Swift suite additionally requires `SUBLER_TEST_BACKGROUND_APP`, `SUBLER_TEST_BACKGROUND_FIXTURE` (generated only), and `SUBLER_TEST_BACKGROUND_METADATA=1` for the explicit online test. No personal-media test should be repeated without its existing bounded-excerpt authorization and private-output safeguards.

## Third-party notices and distribution boundary

Subler's original `LICENSE` and GPLv2 `COPYING` remain intact in its source checkout. Its notice states that most files are GPLv2, some GPLv2+/LGPLv2.1+/BSD/MIT/X11, with GPLv2 applying to the combined application. All upstream copyright notices are preserved by the patches. The new strict-normalizer header is supplied under GPL-2.0-or-later for this separate native component; it is not silently folded into the Swift app.

The pinned MP42Foundation checkout has no top-level independent license file; its original source notices remain untouched. The contrib revision contains prebuilt FFmpeg, mp4v2, Tesseract/Leptonica/PNG/TIFF libraries, plus Sparkle resolved by Xcode. Their complete corresponding-source/build/configuration and redistribution notices have not been assembled or independently cleared here. Therefore this work is a PRIVATE LOCAL BUILD ONLY: no binary upload/public fork publication/distribution is authorized or claimed. Before sharing a native bundle externally, assemble the exact corresponding sources (including patched native code and linked dependencies), relevant licenses/notices and GPL obligations, and resolve the missing dependency notices. Keeping the native checkout separate is not a claim that it removes licensing obligations.
