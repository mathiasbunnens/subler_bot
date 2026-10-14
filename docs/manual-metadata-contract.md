# Manual metadata integration contract

The minimum identity required by this pipeline is a nonempty title and a four-digit release year (1000–9999). Artwork, synopsis and cast are optional; manual input does not invent provider data.

## Shared model

- `MovieJob.manualMetadata: ManualMovieMetadata?` (Codable/Sendable). Missing field decodes as nil for old jobs; invalid manual title/year fails decoding rather than silently validating malformed state.
- `ManualMovieMetadata.title: String`, `year: Int`; validated construction/parse, trim outer whitespace, reject control characters, require four ASCII input digits.
- `MovieJob.title/year` remain effective identity for naming. Manual submission clears candidateIndex/candidateRaw, not a fake provider selection.
- `canEditMetadata`: inactive intervention (needsSelection, failed or paused), before any generated output and before validation. Active jobs are rejected separately. Existing converted jobs are deliberately not editable: inspect their conversion before changing identity. Form drafts are kept in MenuBarView keyed by job UUID, above the short/scroll container switch, so changing layout cannot discard an expanded form or typed values.
- `metadataWarning` remains non-nil for manual provenance, including after validation/completion; needsSelection without manual identity reports missing/unconfirmed required metadata. Menu shows it on active/intervention cards and the latest three other manual jobs.
- `applyManualMetadata(_:isActive:)` changes only identity/intervention fields and returns to pending, never marks validated. The queue checks source availability and persists before scheduling tick. Global pause remains respected. On persistence failure it returns a form error and locks processing via existing fatal persistence gate.
- No posterPath is defined by this feature. Poster worker must preserve manualMetadata/warning. Manual input makes no promise of poster extraction; use the existing placeholder contract when none exists. Counter uses ordinary pending/converting/validating/waiting/completed transitions, with no special manual completion path.

## Conversion and actual tags

Provider candidate matching remains unchanged. Manual jobs skip provider search/application only: native Subler prepare/import/prettify, exact owned queue item, foreign-active-item guards, and MP4 conversion are mandatory. Recovery of a completed owned queue item still goes through writing and full validation.

Installed Subler scripting terminology has no manual tag setter. A native AVAssetExportSession passthrough experiment wrote title but silently dropped the iTunes release-date atom, and the real readback test correctly failed. The shipped implementation therefore requires ffmpeg at `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg` or `/usr/bin/ffmpeg` for manual tags; missing writer produces a clear blocking error (`brew install ffmpeg`). The existing MKV inspector also requires ffprobe where AVFoundation cannot read the source. Nothing installs tools automatically.

`ManualMetadataWriter.apply` only accepts an owned UUID-named generated MP4, not the source, a hard link, symlink or arbitrary output. It checks the MP4 ftyp header before invoking ffmpeg, rejecting a renamed raw MKV. It stream-copies all tracks and maps existing metadata/chapters into a unique staged MP4, overriding only title and date. It validates actual persisted tags, duration and playable video/audio preservation against the source before atomic replacement, compares the previous output digest again, and validates the final file again. An unsupported stream/remux failure retains the initial output and blocks transfer. Large output needs additional staging space; disk-full errors retain the original. Cancellation terminates only the owned process and removes its staged file.

The queue subsequently checks source fingerprint, generated-output ownership and computes a new validatedDigest. Only then can it set validated=true and wait for SMB. Existing digest checks, transfer readback and cleanup checks are unchanged. Merely submitting a form or completing Subler conversion cannot authorize transfer.

## Targeted verification

Run commands from the isolated metadata copy, under `HANDOFF_ROOT/native-lock.py` for native tests/builds:

- `swift build --target SublerAutomation --scratch-path "$PWD/.build"`
- `MANUAL_METADATA_FFMPEG="$(command -v ffmpeg)" swift test --scratch-path "$PWD/.build" --filter ManualMetadataTests`
- `python3 scripts/manual-metadata-queue-smoke.py`

Only new tests are selected. Fixtures use unique directories under ~/.hermes/cache/scratch; the queue smoke is a separately signed app with a unique bundle ID, explicit scratch root, watcher/notifications disabled and global pause enabled. Native smoke uses the real queue and a real SwiftUI hosting view, validates invalid input, active-job rejection, durable identity, no conversion while paused, missing source and persistence failure. XCTest generates H.264 all-keyframe/AAC MKV and a stream-copy MP4, writes/reads title/year through the production writer/validator, independently inspects ffprobe tags/tracks/duration, tests repeat application, wrong identity, raw-MKV rejection, output ownership and failed-validation retention.

The native smoke also hosts the real expanded ManualMetadataForm, verifies two editable NSTextFields and one transparent apply button, performs an invalid native button action, changes both native fields through their editing delegates and performs the valid button action through to persisted queue identity. This is native control/action wiring evidence, not physical keyboard/mouse automation or a visual appearance comparison.

Limits: no actual Subler Apple Events, provider query, native conversion queue, SMB publication, physical keyboard/mouse automation, light/dark visual comparison or packaged final production application tested here. This is tag-writing/readback and queue/form-action evidence, not end-to-end Subler/SMB evidence. The integrator owns final combined UI and bundle verification. Source repository, live films, production queue and shared build are untouched; this delta is against snapshot 4b1236c2bb253852c4c844d37dc8ac597433cd7f only.
