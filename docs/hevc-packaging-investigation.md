# QuickTime audio-only HEVC: investigation and remux decision

Status: diagnostic reproduced; **no production correction installed**. A blanket `hev1` → `hvc1` rewrite was rejected. The existing film was neither remuxed, extracted, decoded nor modified during this run; only its MP4 metadata boxes were read. No Subler application/queue, watched folder, live cache, TV or LAN operation was performed.

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
