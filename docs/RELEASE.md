# Releasing Ichido

GitHub Releases host the **ad-hoc signed** app zip and a signed [Sparkle](https://sparkle-project.org/documentation/) appcast. Pushing a `v*` semver tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml) on `macos-26`: tests, `build-app.sh`, zip, sign the update feed, and publish the ZIP aliases and appcast. There is no Developer ID signing or notarization.

## Soft gate

Treat CI job `test` as a release gate: wait for green before merging to `main` and before cutting a release. Peekaboo stays a live Mac check after CI, not an Actions job.

## Versioning

- Git tags are semver with a `v` prefix: `vX.Y.Z` (example: `v3.2.0`).
- Marketing version is `CFBundleShortVersionString` in [`Resources/Info.plist`](../Resources/Info.plist) (`X.Y.Z`, no `v`).
- Build number is `CFBundleVersion` in the same plist (monotonic integer).

Bump **both** plist keys in a PR **before** tagging. Merge that PR, then tag the merge commit. Do not retag; if the zip is wrong, cut `vX.Y.Z+1` (or a patch) with a new build number.

## Must be green

Before tagging:

1. CI job **`test`** on `main` (or the release PR) is green. That job runs `./scripts/test.sh --all` and `./scripts/build-app.sh`.
2. Prefer the `Build app` step specifically — it is the contract that `build/Ichido.app` still packs and ad-hoc codesigns.

Do not ship from a red `test` run. `render-previews` and Peekaboo are not CI; run them locally when the release includes UI/layout changes. The tag workflow re-runs the same test + build steps, then zips.

## Who cuts the release

The **repo owner** bumps `Info.plist` in a PR, waits for green `test`, merges, and tags the merge commit. Actions builds the zip and signed `appcast.xml` and attaches both to the GitHub Release. Edit the release body with the changelog (the workflow leaves an ad-hoc / Gatekeeper stub plus the tag message). Keep the README and website on the stable latest-release alias. Verify that both
stable ZIP aliases and the signed appcast exist before publishing website copy for a new version.

If Actions fails, repair the release job or create the ZIP aliases and appcast with Sparkle's tools before publishing. A zip alone will not reach existing app installations through auto-update.

## Build the zip

Actions uses this `ditto` line (VERSION is the tag without the leading `v`, e.g. `v3.3.0` → `Ichido-3.3.0-macOS.zip`):

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "build/Ichido.app" \
  "Ichido-X.Y.Z-macOS.zip"
```

To exercise the job without publishing a GitHub Release, use **Actions → Release → Run workflow** (`workflow_dispatch` dry-run; zip and appcast are uploaded as workflow artifacts).

Manual fallback, on a Mac with Xcode 26.x (same major as CI: 26.6 today):

```sh
./scripts/test.sh --all
./scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent \
  "build/Ichido.app" \
  "Ichido-X.Y.Z-macOS.zip"
```

Artifact name is exact: `Ichido-X.Y.Z-macOS.zip` (hyphens, no spaces, `macOS` suffix).

Actions also publishes an identical `Ichido-macOS.zip` asset for the website
and README. Their stable download URL is
`https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`;
release notes use `/releases/latest`. Keep this alias in every release so future
downloads follow GitHub's latest release without a website deployment. The
Sparkle appcast continues to reference the versioned archive. Keep the identical legacy
`Voice-Coach-macOS.zip` alias so old website and README links continue to work. The
app remains `com.gowtham.voicecoach` and uses the existing `Application Support/VoiceCoach`
library and preference keys; the visible bundle is now `Ichido.app`.

The zip is **ad-hoc signed** (`codesign --sign -` in `build-app.sh`), not Developer ID and not notarized. First launch may be blocked by Gatekeeper: unzip, move **Ichido.app** to Applications, then follow [Apple’s opening guidance](https://support.apple.com/en-us/102445), including **System Settings > Privacy & Security** approval when appropriate.

### What is not in the zip

- **No Parakeet / NeMo-Speech runtime.** `build-app.sh` copies the executable, `Info.plist`, `AppIcon.icns`, and Sparkle framework. On-device transcription is an optional later download (**Settings → Transcription**, ~714 MB) into Application Support.
- No personal recordings, no `.build/` intermediates, no preview PNGs.

## GitHub Release

1. Bump both plist keys in a PR, wait for green `test`, merge.
2. Tag the merge commit: `git tag -a vX.Y.Z -m "Ichido X.Y.Z"` and push the tag.
3. Wait for the **Release** workflow on that tag. It creates the GitHub Release and attaches `Ichido-X.Y.Z-macOS.zip` and `appcast.xml`.
4. Edit the release body with the changelog (see `v3.2.0` for tone). The workflow already includes the ad-hoc / Gatekeeper / no-Parakeet notes.
5. If the workflow fails, fix it before publishing. Both release assets must be present and signed for in-app updates.

## Sparkle signing key and update checks

- `Resources/Info.plist` contains only the public EdDSA key. The private key is in the macOS login Keychain under account `com.gowtham.voicecoach`; back it up securely. Never commit or paste it into a workflow file.
- The release job requires repository secret `SPARKLE_ED25519_PRIVATE_KEY`, containing the base64 private key exported by Sparkle's `generate_keys --account com.gowtham.voicecoach -x <secure-file>`. Configure this in GitHub Actions before the first updater-enabled release. The job fails rather than publish a zip without an appcast when the secret is missing.
- The app checks `https://github.com/Gowtham1729/voice-coach/releases/latest/download/appcast.xml` automatically and provides **Ichido → Check for Updates…**. Sparkle verifies the signed feed and ZIP before installation. The GitHub repository and release assets must stay public for this URL to work.
- Run a `workflow_dispatch` dry-run, then test an installed older updater-enabled build against a newer signed release. Existing versions without Sparkle need one manual upgrade to receive this feature. Keep the app in Applications, not a read-only disk image.

## Distribution limitation

Developer ID signing, Apple notarization, and stapling are **out of scope**. Gatekeeper may block the first launch; follow [Apple’s opening guidance](https://support.apple.com/en-us/102445), including **System Settings > Privacy & Security** approval when appropriate. The ad-hoc signed update flow must be validated on a separate installed build before calling it seamless.
