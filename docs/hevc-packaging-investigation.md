# QuickTime audio-only HEVC: investigation and remux decision

Status: **a lossless packaging repair now produces Apple images on the authorized DV8.1 excerpt; no production correction installed**. Full-file preservation is still blocked by native track associations, not by a demonstrated need to transcode. A blanket `hev1` → `hvc1` rewrite remains rejected. The original was never modified/replaced. No Subler application/queue, watched folder, live cache, TV or LAN operation was performed.

The sections below through “Sources” record the earlier metadata-only/HDR10 investigation. The authorized DV8.1 follow-up at the end supersedes its pending-permission statements; do not read earlier scope limitations as the current test result.

## Proven versus suspected

- `SublerService.swift:142` sends the owned imported document to Subler's queue. `:175` and `MediaValidationService.swift:40-51` validate duration/counts/identity but do not prove that Apple produces video images.
- Upstream `SBSendToQueueScriptCommand` supplies the 64-bit data/time options, not `MP42ForceHvc1`. `QueueItem.init(mp4:destURL:attributes:)` retains these attributes. The fileURL initializer has a force-hvc1 preference path, whereas the document initializer does not. PR 165 specifically adds the missing preference to the document initializers. Upstream is evidence of the implementation path, not proof of the installed app's exact source revision.
- Installed Subler's scripting dictionary exposes no write attribute/force-hvc1 argument on `send to queue` or `save as`. Switching to scripted `save as` is not a demonstrated fix: its upstream handler also builds only the 64-bit options. Do not change global Subler preferences or touch its queue/cache to work around this.
- Fresh generated HDR10 Main 10 input, muxed by the **installed MP42Foundation** with empty options: `hev1`, VPS/SPS/PPS completeness false; Apple AVAssetReader rejects decoder startup with AVFoundation -11833 / OSStatus -12906.
- Same generated input and library, adding only `MP42ForceHvc1: true`: `hvc1`, completeness true; Apple produces three 10-bit image buffers. All compressed video/audio packet hashes, PTS, DTS and durations compare equal between these two outputs.
- Direct file reads at FFprobe packet offsets find in-band VPS/SPS/PPS in **both** outputs. This is not merely AVAssetReader inserting parameter sets. Native hvc1 playback success therefore does **not** establish strict hvc1 conformance. The proposed metadata-only strict repair refuses the actual generated fixture; it is not suitable as a production fix and was removed before integration.
- Metadata-only inspection of the two authorized real MP4s reconfirms the same hev1/hvc1 and completeness differences. VPS/SPS/PPS and SEI payload hashes, dvvC (DV8.1), colr, clli and mdcv agree. This makes the option/packaging path a strong explanation, **not proven causality for the real film**: its compressed samples, timing, in-band sets and actual Apple decoding were not compared here.
- No conclusion about Apple TV inability, required video transcoding or Dolby Vision 8.4 compatibility follows from this HDR10 experiment. No Dolby Vision RPU preservation claim has been tested by this reproduction.

## Reproduce without touching user media

Prerequisites: macOS, Xcode command line tools, installed Subler with MP42Foundation, FFmpeg/FFprobe at `/opt/homebrew/bin` with libx265. Run from the repository:

    python3 scripts/hevc-packaging-repro.py --scratch /absolute/existing/scratch

The script accepts no media input. It creates a new unique child directory, builds/signs its own native probe, generates a one-second PQ/BT.2020 Main 10 mire plus AAC tone, creates two MP4s, then asserts six conditions:

1. hev1 Apple decoder rejection is reproduced.
2. Native force-hvc1 output produces three Apple image buffers.
3. Video packet payload hashes and timing agree.
4. Audio packet payload hashes and timing agree.
5. Both outputs contain VPS/SPS/PPS in-band.
6. The generated MKV is unchanged.

It exits nonzero if any assertion fails. Native probe logs by themselves are **not** pass/fail: its inspection command logs decoder failures but returns zero. Use the asserting Python runner. Generated `results.json` contains metadata, per-packet hashes/timing, NAL counts and explicit limitations; logs and media remain in the unique scratch directory.

`hevc-container-metadata.py INPUT...` is a separate bounded-atom metadata-only diagnostic, skipping mdat. `hevc-sample-probe.py INPUT...` reads video samples; use only generated fixtures unless the user authorizes personal sample access. Neither is a production validator for hostile MP4 inputs.

## Actual verification in this run

- Fresh runner exit 0: all six assertions pass. Evidence directory: `hevc-packaging-o764p5de` under the task scratch root.
- Earlier unfinished normalizer regression: six tests, one failure; the native generated MP4 did not normalize successfully. Standalone native smoke explicitly refused in-band parameters. This is failed experimental evidence, not a passing fix. The untracked normalizer, its integration test and obsolete smoke/probe drafts were removed; none had been wired into production.
- Production build via `build.sh`: exit 0, ad-hoc code signing and `codesign --verify --deep --strict` pass. Bundle written to task scratch only; not launched or installed.
- Unchanged Swift suites deliberately not rerun. No product Swift file changed. No live visual QuickTime test, DV8.1 round-trip or TV playback was performed.

## Minimal next implementation plan (not implemented)

Prefer a conforming, lossless container normalization on an exclusively owned generated output **after queue completion and before validation/digest/publication**, rather than replacing the import/metadata/queue workflow or adding an encoder. Apply it also to resumed unvalidated jobs, before the first candidate validation in SublerService. Persisted already-validated jobs require an explicit revalidation/version policy; do not silently change their digest or remove their source.

1. Inspect each actual playable HEVC track, parameter-set changes and DV configuration. Do not infer safe `hvc1` from a filename, codec tag or profile alone. Unsupported EL/FEL/DV profiles and changing/ambiguous parameter sets must stop with a faithful explanation.
2. If parameter sets occur in-band, perform a real remux into a new owned staged output: consolidate the verified VPS/SPS/PPS in hvcC, remove only their equivalent in-band copies, use hvc1 and complete arrays. A simple four-byte retag/completeness patch is not this operation. FFmpeg copy with a selective parameter-set filter is a candidate experiment, **not an approved general command**; its DV record, side-data and atom handling need independent verification first. Alternatively fix the upstream queue option, but verify conformity/preservation instead of assuming the option suffices.
3. Compare video VCL, SEI (HDR10/HDR10+), RPU and other retained NALs byte-for-byte and in original sample order; explicitly account for the intended parameter-set relocation. Require unchanged DV configuration, mastering/color/light metadata, rational timestamps/durations/edit lists, every audio packet (including Atmos), subtitles, chapters, artwork, language/alternate/fallback associations and global identity metadata. Track counts alone are insufficient. Block on anything lost or not verifiable, without SDR/audio/video conversion fallback.
4. Require actual Apple images from the staged relevant tracks, alongside structural preservation checks. A single successful first image is not complete-stream/DV/TV certification; exercise seek and later samples with representative fixtures. Do not generalize one AVAssetReader refusal to all Apple playback paths.
5. Verify the source fingerprint and the owned original output digest again; only then atomically replace the generated output and compute a fresh publication digest. Cancellation/failure must retain the original generated MP4 and source, never publish the staged file. Preserve current no-overwrite SMB and source-cleanup protections. No requeue of foreign Subler items.

## Existing server output / permission needed

Do not patch or rename the existing server MP4 in place. Keep the original and the manual known-good reference. First obtain an authorized short **DV8.1/PQ** fixture or explicit permission to extract a bounded excerpt from the failing output into a specified scratch destination. Compare its samples/parameter sets and Apple decoding against the reference, test the conforming remux above, and provide a new distinct MP4 for user QuickTime comparison. Approve replacing/publishing only after preservation and playback verification; this task does not authorize replacement of the server file. No transcode to HDR10/SDR and no Atmos conversion are part of this plan.

Until that DV8.1 preservation/playback evidence is available, the real-film correction remains unverified and the production pipeline remains unchanged. The task must not be marked fixed based on the HDR10 reproduction alone.

## Sources

- https://github.com/SublerApp/Subler/pull/165.diff
- https://raw.githubusercontent.com/SublerApp/Subler/main/Classes/ScriptCommand.swift (SBSendToQueueScriptCommand and SBSaveAsScriptCommand)
- https://raw.githubusercontent.com/SublerApp/Subler/main/Classes/QueueItem.swift (initializers and process)
- Installed `/Applications/Subler.app/Contents/Resources/Subler.sdef`
- Installed MP42Foundation used directly by the native synthetic harness, not a substituted muxer.

## Authorized DV8.1 follow-up

The user explicitly authorized a short private excerpt. `scripts/hevc-dv81-remux-repro.py` now performs a two-second video/all-audio experiment only when both an explicit `--source` and `--authorize-personal-excerpt` are supplied. It creates an exclusive 0700 scratch child, never prints/persists tool commands or raw native/FFmpeg errors, and removes its media/binaries even on failure. Only hashes, codec records, rational timestamps and sanitized diagnostics survive in `dv81-remux-results.json`. Do not run it on additional personal media without permission.

### What is now proven

- The actual original DV8.1/PQ HEVC track fails Apple decoder startup. Its first bounded video packets contain repeated VPS/SPS/PPS in-band, RPU NAL type 62 and SEI type 39. Thus the strict metadata-only normalizer really cannot repair this input.
- A two-second stream-copy excerpt reproduces that Apple failure. Its bounded video prefix has identical NAL hashes and rational PTS/DTS/durations to the original. Every original audio track is included: six tracks (AAC, AC-3 and E-AC-3).
- On this excerpt, a real remux using video stream copy, `filter_units=remove_types=32|33|34`, `-tag:v:0 hvc1` and `-strict unofficial` removes only repeated parameter sets. Every removed parameter set already exists byte-for-byte in hvcC. All retained VCL/SEI/RPU/AUD bytes, ordering and rational timestamps remain identical. Complete VPS/SPS/PPS arrays remain in hvcC.
- dvvC, colr, clli and mdcv remain byte-identical between excerpt and repaired excerpt. Every audio packet hash and rational timestamp agrees across all six excerpt tracks; there is no audio encode, including for E-AC-3.
- Apple AVAssetReader produces all **50/50 image buffers** and reaches completed status (2), with no reported error. A separate seek to one second produces three images. This is decoder evidence, not just isPlayable or a track count.
- An actual negative-control remux removing RPU NALs is rejected by the retained-NAL comparison, even though a Dolby configuration record alone could look plausible.
- The final asserting run passes **20 checks**. The earlier six-check synthetic MP42/HDR10 reproduction also passes with the extended native probe. Release build and strict ad-hoc signature verification pass; the app bundle was not launched or installed.
- Original identity, size and nanosecond mtime match the initial snapshot across the experiments. All personal excerpt MP4s, native test binaries and initial private tool logs were removed after validation. Synthetic generated fixtures are separate and contain no user media.

This establishes that packaging changes without a video/audio transcode suffice for the tested original prefix. It does **not** isolate one bit of the packaging as the sole cause, certify the rest of the movie, or prove a Dolby Vision display/AirPlay/TV result. No tone mapping or HDR10/SDR conversion was performed.

### Concrete limit: why this command is not installed in the pipeline

The original native container has three `tref/fall` audio fallback associations plus a `tref/chap` chapter association. Even the video/all-six-audio excerpt with `-map_metadata 0` loses all three audio fallback references. The chapter relationship is intentionally not mapped into this excerpt and is not counted as an accidental loss. The strict remux cannot restore associations already discarded by FFmpeg extraction.

Thus packet-perfect audio and equal audio counts do **not** establish native multitrack equivalence. Installing that FFmpeg command after every queue item would knowingly omit required preservation checks. Subtitles, chapters, artwork, alternate groups, edit lists, native metadata and full-stream parameter-set stability remain outside the certified experiment. The result must not be labelled a fixed production pipeline.

An initial attempt to map every original stream was killed at the 120-second subprocess limit and produced no accepted output. Sparse subtitle/chapter tracks can make an output `-t 2` insufficient to bound input demuxing. That attempt was removed from the replayable runner; do not repeat it against the personal original. Its scratch media/logs were deleted. Use generated rich-container fixtures to work on this instead.

### Required production repair, in order

1. Build a generated multitrack fixture containing native `fall`/alternate associations, a chapter reference, subtitles, artwork and identity metadata. Add failing preservation assertions before product code. Keep the real-film sample strictly bounded and delete it after each authorized run.
2. Implement an owned-output MP4 repackager (or verify a native-library path) that removes only byte-equivalent in-band parameter sets, retains hvcC/DV/HDR metadata, and preserves native metadata and track relationships. Rebuild sample sizes/chunk offsets as necessary; merely switching to the UI's force-hvc1 option still leaves parameter sets in-band in the demonstrated library fixture. Do not substitute a whole-file FFmpeg command that drops `fall` references.
3. Scan all applicable generated HEVC samples before repair. Reject changing/unmatched parameter sets, unsupported DV/EL/FEL, ambiguous sample descriptions or unsupported atoms without publishing. The DV8.1 result is not permission to normalize DV8.4/profile5/profile7 blindly.
4. Stage exclusively in the owned job directory, validate all retained NALs/audio/subtitles/timings and native atom associations, then require Apple image/seek evidence. Recheck source fingerprint and original generated-output digest before atomic replacement. On any failure/cancellation, keep the old generated MP4 and source. Never mutate an already-validated transfer-only job without an explicit version/revalidation policy.
5. Integrate after exact queue completion and before candidate validation, output digest and publication, including unvalidated recovery paths. Do not alter global Subler preferences, foreign queue entries, source cleanup or no-overwrite SMB behavior.

### Existing server output procedure

Keep the current server MP4 and known-good manual output unchanged. Do not run the diagnostic excerpt command over the entire movie or publish its deliberately incomplete stream mapping. Once the metadata-preserving repackager passes the generated native-container fixture, create a **new distinct local output** (never overwrite the server original), compare complete packet/atom/timing preservation and Apple decoding, then ask the user to verify QuickTime images/audio/seeking and HDR/DV indication. Server replacement/publication and a full personal-film conversion were not authorized here. Until those steps pass, using the existing manual Subler output is the known user-reported workaround, not an automated repair claim.

## Installed scripting API follow-up (t_38603758)

**Still not a production repair.** No production Swift code, installed app, Subler preferences, foreign queue item or personal media was changed in this follow-up. Only generated HDR10 fixtures and exclusively owned Subler documents were used. A new repeatable installed-API diagnostic is committed; the task remains blocked, not fixed.

### The missing option and the native manual path

Upstream Subler `main` was inspected at `9077b6d149be621ff7d7b0d8eb46839a56610844`:

- `Document.saveOptions(for:)` includes `MP42ForceHvc1` when `Prefs.forceHvc1` is true. GUI Save/Save As and the GUI Send To Queue save panel use this function. `Document.writeSafely` additionally applies alternate-group/language/media-characteristic preferences; those are further differences, not proven causes of this decoder failure.
- `Prefs.swift` declares `SBForceHvc1` with default **true**. Installed Subler is **1.9.5**; a read of that single stored preference found no explicit override. No preference was written.
- `SBSaveAsScriptCommand` and `SBSendToQueueScriptCommand` instead create their own dictionary containing only `MP4264BitData` and `MP4264BitTime`. Neither the installed SDEF nor those handlers offer a caller-supplied options dictionary. Opening/importing a document differently cannot add a missing export attribute to these commands.
- Standard Cocoa AppleScript `save ... in ...` was tried on an exclusively owned generated document: installed Subler returns **-1708** (does not understand `save`). It is not a hidden way to invoke the native GUI save options.
- The installed custom AppleScript `save as ... doc ...` actually creates **hev1**, and Apple's image decoder rejects it with **-11833 / -12906**, just as the native empty-options experiment predicts. Thus replacing `send to queue` with this custom command is not a repair either.
- Upstream PR **165** is still **open / not merged**. Latest official release queried is **1.9.5**. Do not silently build/install a patched third-party app to bypass this task's no-fork boundary. Subler's `LICENSE` identifies GPLv2 in combination; no upstream implementation was copied into product code.

MP42Foundation `MP42Muxer.m`, HEVC and Dolby Vision HEVC setup branches, calls `force_HEVC_completeness` on the configuration cookie **before** `analyze_HEVC` and the native video-track creation. This identifies the step choosing hvc1 versus hev1. It does not remove parameter sets from the media samples. The existing direct installed-library experiment confirms identical packet payloads and in-band VPS/SPS/PPS with either option. Upstream source is explanatory evidence, not an asserted binary/source identity for the installed build.

### Repeatable installed-API diagnostic and an additional red gate

    python3 scripts/subler-scripted-save-repro.py \
      --scratch /absolute/existing/scratch \
      --authorize-owned-subler-documents

This command accepts **no media input**, generates its own fixture through the existing six-check runner, uses opaque owned window IDs, never starts/enqueues/clears the queue, and verifies exact queue-record snapshots without printing their identifiers/paths. It verifies document closure by dereferencing the document, not `exists window`: installed Subler retains stale window wrappers after a document closes. A custom-save document changes its name, so retaining its initial name-based object reference is also unsafe.

Final evidence: `/Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/hevc-packaging-_5c1xmce/scripted-save-results.json`.

Eight diagnostic checks succeeded: standard-save refusal, custom-save decoder refusal, positive native force-hvc1 image output with reader completion, equal custom/default-native video packets and timing, equal audio packets and timing, unchanged generated source, verified owned-document closure, and unchanged queue records. **The runner nevertheless exits 1**: the full-image gate remains red. The force-hvc1 synthetic output contains 24 compressed video packets but AVAssetReader emits only 13 images before completed status. Independent FFprobe decoding reports duplicate POC and only 5 decoded frames; packet timestamps also contain a discontinuity. This is additional evidence against treating the earlier three-image check as full-stream preservation. It does not establish the cause of the synthetic import/timing problem or contradict the earlier authorized DV8.1 excerpt's separate 50/50 result. Do not weaken this gate or infer that the option alone is a complete production solution. A proper generated rich-container fixture must also test presentation timing, not just equality between two native outputs.

A bounded GUI Save experiment on owned generated documents produced no accepted output/evidence and was abandoned; its documents were closed. No GUI-parity, seek, rich-container or DV-preservation success is claimed for this follow-up. No GUI keystroke automation was added to the unattended service.

### Decision required before changing the production route

The precise public AppleScript limitation is now exercised rather than assumed. A pure caller-side `prepare`/custom `save as` substitution cannot set this option. The preferred native option route needs a Subler release exposing/fixing it, or explicit authorization to build/install a separately reviewed third-party correction. Alternatively, choose a background-safe native-helper architecture with preservation gates; the existing probe is not such a helper. Shipping Accessibility-driven global menu/keystroke automation as a silent replacement would add a permission/focus failure mode and is not an approved unattended design.

Verification of the unchanged product: `./build.sh` succeeded, including strict ad-hoc signature verification; uninstalled bundle is at `/Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/t38603758-build/Subler Automation.app`. `swift test --filter SublerServiceTests` executed 16 tests, 5 opt-in tests skipped, 0 failures. The installed-API diagnostic remains intentionally **red (exit 1)** at the full-image gate. No personal original was opened, extracted, overwritten or published in this follow-up, and no product-fix claim is justified.
