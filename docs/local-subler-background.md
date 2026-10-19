# Local-only windowless Subler route

Status: implemented and exercised locally; opt-in only, not installed or published. This supersedes the implementation limitations in `hevc-packaging-investigation.md`, not its historical diagnostic results. No existing user MP4 was replaced or whole film processed.

## Cause and correction

Installed Subler 1.9.5's document-to-queue AppleScript handler omits `MP42ForceHvc1`, unlike the GUI save-options path. Its script dictionary cannot pass that option. Standard scripted save returned -1708; custom save-as retained `hev1` and failed AVFoundation decoder creation (-11833/-12906). Merely renaming the sample entry is insufficient: tested inputs carry VPS/SPS/PPS in-band, and the earlier FFmpeg experiment lost `fall` associations.

The separate local build sends the native queue both force-hvc1 and strict-normalization options. MP42Foundation validates hvcC and each complete length-prefixed sample before editing; it removes only byte-identical copies of configured VPS/SPS/PPS, leaving VCL, SEI, RPU and other retained NAL bytes untouched. Native hvc1 writing supplies complete parameter arrays. Changing/ambiguous/malformed parameter sets, nonzero NAL layers, parameter-only samples, enhancement-layer configurations, and Dolby Vision configurations other than supported single-layer 8.1 are refused. There is no encode, SDR conversion, audio conversion or FFmpeg repackager fallback. Native write failures propagate as failed queue items; a failed partial scratch output is not a publishable conversion.

Import uses MP42's importer directly, rejects conversion-requiring/nonmuxable tracks and multiple sample descriptions, imports all supported tracks/metadata, and returns a native owned token without constructing a document window. Metadata candidate lookup/application and the existing owned queue workflow use that token instead of a window ID. Enqueue closes only that document. Tokens are live-process identifiers, not durable handles across a native-app restart.

A second bug was reproduced deterministically: after the last item completed, a new append/start could fall between the empty scan and the transition to idle. The only start was dropped. The queue now commits its empty/idle transition under the same array lock; a barrier-based regression failed before the change and passes after it. No polling/repeated-start workaround was added to the Swift service.

## Isolation and opt-in

- Bundle ID: `local.sublerautomation.Subler`; protocol marker: `SublerAutomationBackgroundProtocol = 1`.
- `LSBackgroundOnly`, prohibited activation policy; no document, queue or activity-window construction during the tested route. Automatic updater controller/feed disabled.
- Preferences use the distinct bundle ID; queue/logs/presets/OCR files use `~/Library/Application Support/SublerAutomationLocal`, never the installed app's `Subler` directory.
- The default Automation route remains `org.galad.Subler`. Set `SUBLER_AUTOMATION_LOCAL_SUBLER_APP` explicitly to the absolute local bundle path to opt in. Invalid configuration fails closed, never falls back to the installed app. A running different local build is rejected rather than silently reused or terminated.
- Permission preparation targets the same selected bundle ID. macOS may require a separate Automation grant for this build/caller and may prompt again after signing/identity changes; no permission bypass or blanket no-prompts promise is made. No Accessibility grant is used by this route.
- Production instance, watched folders, normal Subler app/queue and TV playback were not launched/restarted/mutated to enable this route. Existing ready/working-foreign-item, destination/no-overwrite and stable queue-item-ID checks remain in place.

Current local bundles (both ad-hoc signed and strictly verified):

    /Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Background.app
    /Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Automation.app

Explicit opt-in launch, only when the normal Automation instance is not running and after reviewing its configured watched folders:

    SUBLER_AUTOMATION_LOCAL_SUBLER_APP="/absolute/path/dist-local/Subler Background.app" \
      "/absolute/path/dist-local/Subler Automation.app/Contents/MacOS/SublerAutomation"

This document does not enable that environment variable for the user's production process. Test the app only with an explicit isolated `SUBLER_AUTOMATION_TEST_ROOT`; a normal app launch can process watched user media. Do not open the background bundle in the GUI to select films; its public test commands are for owned documents only.

## Reconstruct and build

Native sources remain separate Git repositories, ignored by the main repo. The main repo tracks reviewable source patches, not a giant binary checkout. Source pins:

- SublerApp/Subler: `9077b6d149be621ff7d7b0d8eb46839a56610844`.
- SublerApp/MP42Foundation: `bfa477b799ce55716f744638e6dfe3f23d39c5d7` (explicit override of Subler's older submodule pin).
- SublerApp/contrib: `debd14253dba88addfd918d144fb7872a9e075f7`.
- Upstream Xcode project pins Sparkle 2.9.6 exactly.
- Local native commits: Subler `5442a16`, MP42Foundation `9c89c9a`; neither pushed.

On a fresh checkout with no `vendor-local/Subler` directory:

    bash scripts/prepare-local-subler.sh
    LOCAL_SUBLER_BUILD_ROOT="/absolute/scratch/local-subler-derived" bash scripts/build-local-subler.sh
    SUBLER_BUILD_SCRATCH="/absolute/scratch" \
      SUBLER_BUILD_APP="/absolute/output/Subler Automation.app" bash build.sh

`prepare-local-subler.sh` refuses to reset/overwrite an existing source checkout. It clones the public sources, checks out exact revisions, initializes the pinned contribution libraries and applies the two patches. Requires network for a new checkout and Xcode/SPM dependencies. The build script requires an absolute derived-data path, builds arm64 Release, patches only its newly built bundle identity/background flags, and ad-hoc signs/verifies it. It never installs to `/Applications`. Copy a completed bundle to a distinct owned `dist-local` path before opting in; do not replace a running app. These are source-reproducible builds, not a claim of byte-identical Xcode output or Developer ID/notarized distribution.

`python3 scripts/test-local-subler-patches.py` reconstructs every patched file offline from the pristine pinned Git objects and proves byte equality with the reviewed native checkout. Both Subler and Automation have been built and signature-verified repeatedly; native patches were replayed successfully (12 Subler files, 4 MP42Foundation files).

## Verification and limitations

`docs/local-subler-evidence.json` records the measured results without private media names.

- Full Swift suite: 168 tests, 15 opt-in/integration skips, 0 failures. Explicit live background suite: 7 tests, 0 skips/failures, including online metadata selection, persisted title/year validation, manual conversion and closing one of two owned documents without affecting the other.
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
