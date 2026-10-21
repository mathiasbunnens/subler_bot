# Standalone app — build 10

Task `t_9b9db00c`. Private local use only; no installation, push or publication.

Deliverable: `/Users/mathiasbunnens/Downloads/SublerAutomation/dist-standalone/Subler Automation.app`.
Move only this outer app into Applications, then open it. Do not separately move or launch `Contents/Helpers/Subler Background.app`. Version 1.1.0/build 10 retains the Local caller bundle ID and existing engine identity/protocol, embedded notices and native dependencies. Ad-hoc signing is not Developer ID signing/notarization; macOS consent can still be required after moving or signing changes.

## Resume and discovered regression

The user authorized quitting the old engine only while idle. PID 10111 was verified as the user's exact old executable. Its background state was `0|false|2|0`; no ready/working queue items existed. It quit gracefully without changing queue entries or opening/converting user media.

Strict packaging then passed with `valid=true` both at the deliverable path and in a relocated accented/spaced path without a sibling. All 376 engine files/symlinks match the reviewed original, including Credits.rtf. Missing/non-executable engines reject without fallback and inherited engine environment selection is ignored.

The first actual relocated conversion caught a real routing defect: AppleScript's literal application path can relaunch another LaunchServices-registered copy sharing the bundle ID. It launched old-path PID 8316 and imported only the synthetic fixture, then the existing guard refused further work. This is a failed E2E, not acceptance. That scratch-only unsaved document prompted during graceful quit; read-only process sampling and System Events identified the exact `Generated.2026.mkv` save alert. Only its “Ne pas enregistrer” button was clicked; PID 8316 exited. No user document was dismissed or modified.

The shared target now launches its validated URL with NSWorkspace (inactive, new instance), validates the returned and running URLs before media Apple Events, and refuses AppleScript dispatch if that engine has exited. Both service entry points and native permission preparation use this shared launch operation; no second resolver or installed-engine fallback was added.

## Executed verification

- Targeted Swift suites: 19 discovered, 15 passed, 4 explicitly skipped opt-in native/online tests; zero failures. Invalid targets also reject the new launch operation before AppleScript.
- Packaging: 5 passed. Permission running-target contracts: 2 passed. Shared About presenter/view contract passed. `git diff --check` passed.
- After the routing fix, the actual signed release was copied beneath scratch `Applications simulées` in an accented/spaced directory and launched via LaunchServices. Only TEST_ROOT selected a fresh scratch queue/settings root; no engine environment override was used. Real Apple Events and native conversion were not mocked. Permission preflight alone is injected in TEST_ROOT.
- First fixed E2E evidence: `dist-standalone/evidence/resumed-launch-fixed.log`. Exact nested running engine PID 10769 was observed externally, 472 samples: zero engine windows, zero engine-frontmost samples, installed Subler queue digest unchanged. Real output reached validated/waitingForServer (no server configured), source digest unchanged; native decode returned 48 images and seek returned 3. Independent ffprobe found HEVC/hvc1, AAC, duration 2.005 seconds, title `Generated Finder launch`, date `2026`.
- Final clean-commit build, strict packaging, version/binary parity and relocated LaunchServices acceptance are recorded in `dist-standalone/evidence/final-*.log`. The final launch harness also asserts hvc1, audio, positive duration and persisted title/year and saves ffprobe/decode/seek reports in its printed scratch settingsRoot.

Run reproducibly from the repository:

```sh
SUBLER_BUILD_SCRATCH="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" SUBLER_BUILD_EMBEDDED_ENGINE=1 ./build.sh
TMPDIR="$HOME/.hermes/profiles/codex-dev-2/cache/scratch" python3 scripts/test-bundle-engine.py --app "$PWD/dist-standalone/Subler Automation.app" --engine-source "$PWD/dist-local/Subler Background.app"
python3 scripts/standalone-acceptance.py
SUBLER_BUILD_APP="$PWD/dist-standalone/Subler Automation.app" python3 scripts/version-contract.py
```

Do not rerun against another relocated copy while an earlier engine copy remains running. Verify its exact PID/path, no active queue and `0|false|2|0`, then gracefully quit only the test-owned engine. Never weaken the running-copy guard or reset TCC to obtain a pass.

## Scope and limits

No production settings/queue/locks, replacement-confirmation/backup behavior or native remux implementation changed. Reuse the unchanged build-8 replacement/SMB and earlier native rich-media evidence; no NAS write or user-film conversion was performed for packaging. TV playback, interactive About rendering and actual production migration are not certified. No new TCC bypass or database modification was performed. The old build-9 report is retained as historical blocked evidence; this report supersedes its acceptance status.
