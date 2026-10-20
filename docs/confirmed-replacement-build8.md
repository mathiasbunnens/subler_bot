# Confirmed replacement — build 8 candidate (t_cc77a812)

Status: implemented and exercised on local APFS; NOT certified for production SMB. Do not activate this candidate automatically. The running build 7 and its sibling Background engine are deliberately untouched.

## Implemented

- The former permanent production replacement gate is removed. The real confirmation action records one-use consent for the exact job, source path/fingerprint, existing output digest (when already validated), and destination snapshot. Metadata selection is retained and no additional confirmation is required while these identities remain unchanged.
- Review displays source/output and server paths, sizes and dates. Destination snapshots bind origin, filesystem ID/mount point, root/directory inode/device, regular-file inode/device, size and nanosecond modification/change timestamps. Directory timestamps are excluded from persisted consent because creating the transaction itself changes them. Legacy snapshots require refreshed review.
- Replacement prepares an exclusively created UUID stage in the SAME server movie directory, streams and hashes against the validated output digest, synchronizes and fully rereads it. It then independently copies, synchronizes and verifies the old movie into a UUID `.backup` before touching the final entry.
- Publication uses NSFileCoordinator and FileManager.replaceItemAt with native backup retention, not remove(destination)+move(stage). The native operation also retains `.backup.native`; neither old version is automatically deleted. Unrelated films, subtitles, subdirectories, the source and user preferences are not cleaned or migrated. The new MP4 is byte-identical to its validated digest, including embedded media metadata.
- A synchronized JSON intent journal binds job, source output path, digest, old digest, destination snapshot and exact UUID transaction names. Restart recovery is READ-ONLY: recognize an already committed matching final only after verifying the retained backups and container identity. Never replay a journal as permission to overwrite. A missing final with a recoverable old version requires explicit intervention. Incomplete/cancelled/corrupt transactions retain their owned files; no recursive prefix cleanup.
- Independent backup plus native backup can require approximately two old-film copies plus the new output on the server. ENOSPC before publication preserves the existing public film. Backups remain until an operator deliberately reviews/removes them.

## Real executed evidence

- Initial RED: inherited replacement tests did not compile because recoverReplacement was absent. Implemented recovery; the three real filesystem publication/recovery tests then passed.
- Additional RED: new failure tests did not compile before the internal I/O-fault seam existed. GREEN with operations injected at copy-chunk, synchronization and old-backup-copy boundaries. These are deterministic EIO/ENOSPC simulations on real filesystem transfers, NOT an actual full NAS disk or power outage.
- Final full `SUBLER_TEST_SMB=0 swift test`: 198 tests, 16 skipped, zero failures. Log: `/Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/t_cc77a812-final-tests.log`. Skips include external/native media fixtures and all real SMB tests; a skipped test is not SMB evidence.
- Real APFS executor tests cover publication and byte replacement, preserved original/sidecars/source, boolean-without-snapshot refusal, changed snapshot, mutation during copy, cancellation, replaced root/symlink directory, concurrent transfer refusal, accented names, corrupt readback/final, native rename failure, interruption with absent final, lost commit acknowledgement/restart, unrelated job/source/digest refusal, and corrupt backup refusal without cleanup.
- Signed isolated queue/UI harness: `python3 scripts/manual-metadata-queue-smoke.py --reimport-review` passes. It calls the actual acceptReplacement action method and then the SAME publishValidatedOutput method used by production, exercising native replacement and retained backup. It also checks source mutation, cancel/no-consent refusal, stale modal, exact reported Mario identifier, completed history, explicit reimport, watcher suppression and duplicate enqueue during the actual transfer.
- Harness conversion/validated status is seeded with digest-bound synthetic bytes; no real Subler conversion, provider result, full end-to-end runJob, or modal button click is claimed. Production metadata/media validation remains covered by its existing tests.
- Actual light/dark SwiftUI host rendering passes at 380×572 points. Inspected captures show wrapped source/target paths, dates, sizes and accessible confirmation/removal controls without visible clipping. Final harness evidence: `/Users/mathiasbunnens/.hermes/cache/scratch/manual-metadata-queue-0mmnzhb5/`. Previous equivalent inspected captures: `manual-metadata-queue-eze5oum5` under the same scratch parent.
- `python3 scripts/menu-ui-contract.py`: five checks pass. `git diff --check`: clean.

## Explicit unresolved guarantees / blockers

1. Real SMB certification requires permission to create ONE exclusively owned directory `Subler Replacement QA Amélie <UUID>` at the mounted Movies share, only a few MB of synthetic data, with backup/journal retained for inspection. Mount presence was discovered through mount metadata only. NO server file was written, replaced, removed, mounted or disconnected in this run. No personal movie was searched or processed.
2. NSFileCoordinator does not serialize an uncoordinated writer on another SMB client. Revalidating immediately before a native replacement is NOT portable compare-and-swap. A deterministic last-instruction-race test demonstrates this explicitly: the third-party bytes are retained in `.backup.native`, the reviewed original is retained independently, the new output can already occupy the final path, and the operation/recovery refuse to report success. Thus strict “never displace a changed third-party target” remains UNSATISFIED for that window. Certification needs either an agreed exclusive-writer protocol or a server/backend supporting conditional publication; do not claim that testing a cooperative SMB happy path proves this stronger guarantee.
3. Foundation/fsync do not establish SMB server power-loss atomicity or server durable-write behavior. Real disconnect/remount/power-loss tests were NOT run. Do not interrupt a user's mounted share to obtain this evidence.
4. The candidate must retain the existing local bundle identifier and original co-local Background engine. Ad-hoc code-signature changes may still require macOS consent; no TCC database edit, identity reset, process restart, user settings change or automatic activation is authorized.

## Bounded real-SMB test (only after explicit permission)

Run only the replacement test with both explicit opt-ins; do not enable the entire SMB suite or use personal media:

    SUBLER_TEST_SMB_REPLACEMENT=I_ALLOW_UNIQUE_SCRATCH_FIXTURE \
    SUBLER_TEST_SMB_REPLACEMENT_MOUNT=/Volumes/Movies \
    TMPDIR="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" \
    swift test --filter TransferTests.testRealSMBConfirmedReplacementInUniqueScratchDirectory

The test leaves its exact UUID directory, synthetic final, subtitle, backups and journal for independent inspection. No recursive cleanup is performed. A successful result certifies only the tested server/filesystem happy path, not multi-client compare-and-swap or disconnect atomicity.

## Built candidate and provenance

- Source commit: `7ed5a9f775e9e089978d8534ea7780078c4c679d` (local only, no push). The report-only commit following it does not change the built Sources.
- Built successfully with `SUBLER_BUILD_LOCAL_ENGINE=1 SUBLER_BUILD_APP="$PWD/dist-local/Subler Automation Replacement Preview.app" ./build.sh`. Build log: `/Users/mathiasbunnens/.hermes/profiles/codex-dev-2/cache/scratch/t_cc77a812-build8.log`.
- Candidate: `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Automation Replacement Preview.app`, version 1.1.0 build 8. Retains `com.mathiasbunnens.SublerAutomation.Local`; original sibling `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-local/Subler Background.app` is required and unchanged. No normal app activation was performed.
- `test-bundle-engine.py` on the actual signed candidate: valid=true, background=true, exact original co-local engine, sourceDirty=false, exact source commit. Missing sibling in an isolated signed copy fails closed. Diagnostic mode does not initialize the user's queue or restart the engine.
- `version-contract.py` with SUBLER_BUILD_APP: three checks pass, including source plist/version, embedded source commit and unsigned Mach-O equality with the release executable. This HEAD-sensitive check was run at the source commit, before this report-only update.
- Strict/deep codesign verification passes for candidate, running build-7 caller, and unchanged sibling Background engine. Local ad-hoc signing, not notarization. Candidate designated cdhash: `799efa4942793db57997de391644e2ea178c590a`.
- Candidate signed executable SHA-256: `1dd15b49f3e0405639056d696c7752ce76c444729d60099210df36e5831456b1`.
- Original sibling engine executable SHA-256: `ed75ed860da1d1e2139292c2c692cdfca6bbacd8802fc9a1c824ba62c46369fb`.
- The unrelated untracked `.vscode/` and `.worktrees/` remain excluded from commits. No process was stopped/restarted, no TCC database was modified, and no personal/server media was touched.

Handoff remains blocked for explicit bounded scratch-SMB permission and the strict multi-client no-displacement guarantee described above. A working APFS preview is not final acceptance of those outstanding criteria; do not silently close the card or activate the candidate.
