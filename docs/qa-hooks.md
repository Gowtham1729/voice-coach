# Debug QA hooks

The injection, replay log, and support-directory overrides compile only in `DEBUG` app builds. The release app has no QA hook strings; `./scripts/check-release-hooks.sh` checks its binary after `./scripts/build-app.sh`.

From the repository root, build a separate debug bundle and launch it with a fresh support directory:

```sh
./scripts/build-app.sh --debug
QA_ROOT=$(mktemp -d /tmp/voicecoach-qa.XXXXXX)
open -n -F -a "$PWD/build/Ichido-Debug.app" --env "VOICECOACH_SUPPORT_DIR=$QA_ROOT"
```

To exercise an existing WAV through the app's import, analysis, and save path, copy both the library and WAV into disposable `/tmp` paths first. Launch the debug bundle with `VOICECOACH_INJECT_TAKE` and use Practice → Inject QA take (Command-Shift-J). `VOICECOACH_REPLAY_LOG=1` enables span logging.

```sh
QA_ROOT=$(mktemp -d /tmp/voicecoach-qa.XXXXXX)
cp -R /tmp/qa-lib/. "$QA_ROOT/"
cp /tmp/qa-deliberate5/edited-about.wav "$QA_ROOT/staged.wav"
open -n -F -a "$PWD/build/Ichido-Debug.app" \
  --env "VOICECOACH_SUPPORT_DIR=$QA_ROOT" \
  --env "VOICECOACH_INJECT_TAKE=$QA_ROOT/staged.wav" \
  --env VOICECOACH_REPLAY_LOG=1
```

Quit only the debug instance after QA. The `VoiceCoachSelfTest` flags `--retry-verdicts` and `--retry-legacy-loads` are separate development CLI checks, not app hooks.
