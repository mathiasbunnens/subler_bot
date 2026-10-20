# Reimport and server replacement review — build 7

Task `t_85727eef`. Local code commit `e72722ef1d222c6ef2b9f1f24567ca7dacc82202`, version 1.1.0 build 7. No push or production activation.

## Reproduced cause and corrected behavior

The real explicit-enqueue guard refused every fingerprint already present in the queue, including `completed` history. Removing an intervention could therefore still leave an older completed record preventing reimport. The unchanged guard was extracted into `QueueImportPolicy` and its completed-history regression failed natively before the policy was changed. The ordinary removal/store path already supported explicit addition after dismissal; it was not an unconditional permanent-ignore bug.

Explicit enqueue now ignores completed history only. Any unfinished job matching the existing path or fingerprint still blocks a duplicate; the UI explains whether to consult an active/pending task or resume/remove an intervention. Completed jobs and their generated output/history remain untouched. Removing an inactive intervention still atomically suppresses the unchanged watched source across restarts; explicit addition clears that suppression. No source/output file is deleted by removal.

The reported identifier is preserved exactly in unit and native queue fixtures:
`The.Super.Mario.Galaxy.Movie.2026.MULTI.VF2.2160p.WEBRip.iT.DV.HDR10+.x265.EAC3.5.1.Atmos2`

Only the scratch fixture appends `.mkv`; the real user's extension/path were not inferred, searched or processed. The identity policy remains path/inode/size/mtime based (not a content hash). Same basename at a different path is a separate import unless its existing fingerprint matches. Same path with a changed fingerprint remains blocked while an unfinished task owns it.

## Existing destination and explicit limitation

A film at the exact final server layout `share/Movie (year)/Movie (year).mp4` now produces a paused conflict with “Existe déjà sur serveur”, full target path, size and modification date. No local staging file is mistaken for server presence. Metadata selection/title/year are retained, and the conflict does not show a redundant metadata form or a bypassing Retry action.

Detection still requires resolved metadata and a verified already-mounted share before conversion. It does not connect/authenticate just to probe for duplicates. If the share was absent then, another check after reconnect catches a conflict before transfer, preserving any already validated local MP4. This is exact-name/layout detection, not a whole-library semantic duplicate search.

Persisted target snapshots bind root, directory and regular-file identity, nanosecond mtime/ctime and size. Descriptor-relative checks reject symlinks, hardlinked targets, traversal, changed roots and changed entries. No target bytes are hashed merely to show the review card. Before/after the confirmation dialog the target is re-read; a changed/legacy target refreshes the review and requires a new action. Cancel leaves state/files unchanged. Retry is not replacement consent, and restarting does not persist authorization.

IMPORTANT: actual SMB replacement is deliberately unavailable in this build, even after confirmation. The existing backend only provided backup-move followed by publication, not a conditional atomic exchange. Disconnect between those renames could leave the public target absent; checking inode/mtime before a rename cannot make it conditional. Therefore production `VerifiedMount` denies replacement before conversion/transfer or any original move, and the UI reports the limitation rather than performing the old fallback. Legacy backup/rollback algorithms remain exercisable ONLY on internal local fixtures. This is the task's requested fail-closed fallback, NOT a claim of successful SMB overwrite. Fresh publication and no-overwrite protection are retained. A safe real conditional replacement backend would be additional work; no such capability was invented or claimed.

## Executed verification

- RED: `swift test --filter ReplacementReviewTests` with the original extracted dedup guard: completed explicit reimport failed (one assertion); then GREEN with corrected policy.
- Full `swift test`: 185 tests, 16 skipped, zero failures. Opt-in real SMB/native fixture tests were not enabled. Log: `/Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/t_85727eef-tests.log`.
- `python3 scripts/manual-metadata-queue-smoke.py --reimport-review`: PASS. Actual JobQueueService, durable store and native application harness: reported-name fixture reimport with completed history, watcher suppression, pending/active duplicate guards, cancellation with identical stored bytes, changed target/new consent, stale modal no-op, metadata retention and unsupported replacement blocked before conversion. No Apple Events, network or personal film conversion. Server conflict was seeded in this queue fixture; filesystem snapshot capture was real, not a real SMB/provider import integration.
- Light/dark actual SwiftUI host captures inspected: readable path/date/size, visible Ignorer / Confirmer remplacement… / trash, no clipping in the captured conflict layout. Host dimensions 380×499 points. Evidence: `/Users/mathiasbunnens/.hermes/cache/scratch/manual-metadata-queue-z3zv2lw3/state/review-NSAppearanceNameAqua.png` and `review-NSAppearanceNameDarkAqua.png`. Off-screen host snapshots do not certify every menu height or actual modal clicking.
- `python3 scripts/menu-ui-contract.py`: five tests pass.
- Build with `SUBLER_BUILD_LOCAL_ENGINE=1 SUBLER_BUILD_APP="$PWD/dist-local/Subler Automation Reimport Review.app" ./build.sh`: success, signed ad hoc, strict signature verification passes.
- `python3 scripts/test-bundle-engine.py --app "$PWD/dist-local/Subler Automation Reimport Review.app"`: valid=true, background=true, sourceDirty=false, build 7, exact original sibling engine. A signed isolated copy without sibling fails closed.
- `SUBLER_BUILD_APP="$PWD/dist-local/Subler Automation Reimport Review.app" python3 scripts/version-contract.py`: three tests pass, including unsigned Mach-O parity against the release product, exact plist and embedded commit.
- Original build-6 caller and original sibling engine signatures still pass; neither bundle replaced. No process stopped or normal app launched.

An initial candidate under `dist-update/reimport-review` was built but its diagnostic correctly rejected the copied engine because another local build was already running at the original path. It is NOT the handoff candidate. The final caller below shares the original, unchanged sibling engine, and its real diagnostic passes. No running engine was terminated to bypass this guard.

## Candidate and user acceptance

Final caller:
`/Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Automation Reimport Review.app`

Keep the unchanged sibling `dist-local/Subler Background.app`. Build 6 remains at `dist-local/Subler Automation Local.app`. When existing Automation work is idle, explicitly quit that caller and open the new Reimport Review app from Finder. Shared settings and instance lock remain; changed ad-hoc signing may require renewed macOS consent. Do not open both callers to force parallel processing.

1. Add a previously completed MKV explicitly: it must create a new task without removing history. Do not add a second copy while that new task is pending/active: a visible explanation must refer to the existing task.
2. Remove an inactive À vérifier entry: files stay. The unchanged watcher must not immediately recreate it; Ajouter… must accept it again.
3. For an identified title/year already at the exact mounted server destination, expect À vérifier / Existe déjà sur serveur, useful target details and no conversion yet. Metadata should remain selected. Cancel the dialog: no state/file change. A changed target requires refreshed review.
4. In this build, accepting replacement must visibly report “Remplacement SMB bloqué”, retaining the public original and source/local output. This candidate intentionally cannot perform an actual overwrite under an unproven atomic guarantee. Removal and later explicit reimport remain available.

Not verified: personal Mario import/provider result, real SMB publication/replacement, SMB disconnect behavior on actual hardware, TCC grant flow for build 7, actual confirmation dialog clicking, playback/TV/HDR/DV certification, or normal production activation. The engine/routing/native conversion evidence from build 6 is reused, not rerun or broadened here.
