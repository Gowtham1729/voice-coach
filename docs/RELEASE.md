# Releasing Ichido

GitHub Releases host the **notarized** app zip and a signed [Sparkle](https://sparkle-project.org/documentation/) appcast. Pushing a `v*` semver tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which calls [`.github/workflows/notarize.yml`](../.github/workflows/notarize.yml) on `macos-26`. That job tests, signs with Developer ID (Sparkle inside-out, no `codesign --deep`), notarizes, staples, re-zips, signs the update feed, and publishes the ZIP alias and appcast. Missing signing or notary secrets fail the job. It does not fall back to an ad-hoc signature.

A **Notarize** `workflow_dispatch` runs that same sign, staple, and appcast path and uploads artifacts. It does not create a GitHub Release.

## Soft gate

Treat CI job `test` as a release gate: wait for green before merging to `main` and before cutting a release. Peekaboo stays a live Mac check after CI, not an Actions job.

## Versioning

- Git tags are semver with a `v` prefix: `vX.Y.Z` (example: `v3.2.0`).
- Marketing version is `CFBundleShortVersionString` in [`Resources/Info.plist`](../Resources/Info.plist) (`X.Y.Z`, no `v`).
- Build number is `CFBundleVersion` in the same plist (monotonic integer).

Bump **both** plist keys in a PR **before** tagging. Merge that PR, then tag the merge commit. Do not retag. If the zip is wrong, bump `CFBundleVersion`, set `CFBundleShortVersionString` to the next patch, and tag that exact string, for example `vX.Y.(Z+1)`. The workflow rejects a tag whose version differs from `CFBundleShortVersionString`.

## Must be green

Before tagging:

1. CI job **`test`** on `main` (or the release PR) is green. That job runs `./scripts/test.sh --all` and `./scripts/build-app.sh`.
2. The CI `Build app` step packs `build/Ichido.app` with an ad-hoc signature so the bundle still builds. That check is not the public download. Tag releases sign with Developer ID instead.

Do not ship from a red `test` run. `render-previews` and Peekaboo are not CI; run them locally when the release includes UI/layout changes. The tag workflow re-runs the tests, then signs, notarizes, and zips.

## Who cuts the release

The **repo owner** bumps `Info.plist` in a PR, waits for green `test`, merges, and tags the merge commit. Actions builds the notarized zip and signed `appcast.xml` and attaches both to the GitHub Release. Edit the release body with the changelog (the workflow leaves a notarized-download note, a note that the Parakeet model is not in the zip, and the tag message). Keep the README and website on the stable latest-release alias. Verify that the stable ZIP alias and the signed appcast exist before publishing website copy for a new version.

If Actions fails, repair the release job before publishing. A zip alone will not reach existing app installations through auto-update. Do not publish an ad-hoc zip in its place.

## Build the zip

Actions uses this `ditto` line twice: once to submit for notarization, and again after `stapler staple`, so the published zip is the stapled app. VERSION is the tag without the leading `v`, e.g. `v0.0.4` → `Ichido-0.0.4-macOS.zip`:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "build/Ichido.app" \
  "Ichido-X.Y.Z-macOS.zip"
```

To exercise signing, notarization, and the appcast without publishing a GitHub Release, use **Actions → Notarize → Run workflow** and leave **publish** off. The stapled zip and appcast are workflow artifacts. **Release** runs only on a pushed `v*` tag, and that is what publishes.

`./scripts/build-app.sh` with no arguments is an ad-hoc bundle for CI and local development. It is not a release artifact. Tag releases pass `--developer-id` with the identity read from the imported certificate.

Artifact name is exact: `Ichido-X.Y.Z-macOS.zip` (hyphens, no spaces, `macOS` suffix).

Actions also publishes an identical `Ichido-macOS.zip` asset for the website
and README. Their stable download URL is
`https://github.com/Gowtham1729/voice-coach/releases/latest/download/Ichido-macOS.zip`;
release notes use `/releases/latest`. Keep this alias in every release so future
downloads follow GitHub's latest release without a website deployment. The
Sparkle appcast continues to reference the versioned archive. The app remains `com.gowtham.voicecoach` and uses the existing `Application Support/VoiceCoach`
library and preference keys; the visible bundle is now `Ichido.app`.

The published zip is signed with the Developer ID Application certificate for team `88HMB5SB4X`. The common name is read from the imported `.p12`. Sparkle is signed inside-out, with the hardened runtime and a timestamp. The job does not use `codesign --deep`.

### What is not in the zip

- **No Parakeet / NeMo-Speech runtime.** `build-app.sh` copies the executable, `Info.plist`, `AppIcon.icns`, and Sparkle framework. On-device transcription is an optional later download (**Settings → Transcription**, ~714 MB) into Application Support.
- No personal recordings, no `.build/` intermediates, no preview PNGs.

## GitHub Release

1. Bump both plist keys in a PR, wait for green `test`, merge.
2. Tag the merge commit: `git tag -a vX.Y.Z -m "Ichido X.Y.Z"` and push the tag.
3. Wait for the **Release** workflow on that tag. It creates the GitHub Release and attaches `Ichido-X.Y.Z-macOS.zip`, `Ichido-macOS.zip`, and `appcast.xml`.
4. Edit the release body with the changelog, matching the tone of the latest release notes. The workflow already includes the notarized-download note and the no-Parakeet note. Editing those notes does not change the signed appcast.
5. If the workflow fails, fix it before publishing. Missing `CSC_P12_BASE64`, `CSC_P12_PASSWORD`, `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`, or `SPARKLE_ED25519_PRIVATE_KEY` fails the job. The versioned ZIP, `Ichido-macOS.zip`, and the signed appcast must all be present. There is no ad-hoc fallback.

## Sparkle signing key and update checks

- `Resources/Info.plist` contains only the public EdDSA key. The private key is in the macOS login Keychain under account `com.gowtham.voicecoach`; back it up securely. Never commit or paste it into a workflow file.
- The release job requires repository secret `SPARKLE_ED25519_PRIVATE_KEY`, containing the base64 private key exported by Sparkle's `generate_keys --account com.gowtham.voicecoach -x <secure-file>`. Configure this in GitHub Actions before the first updater-enabled release. The job fails rather than publish a zip without an appcast when the secret is missing. A `workflow_dispatch` dry-run still signs the appcast, so it needs the same secret, plus the Developer ID and notary secrets.
- `Info.plist` sets `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`. Do not hand-edit `appcast.xml` after the workflow signs it. Editing the GitHub release notes does not change the appcast. Do not set `SUAutomaticallyUpdate`. Sparkle keeps prompting. Do not rotate the Ed25519 key in the same release that changes the Apple signature.
- The app checks `https://github.com/Gowtham1729/voice-coach/releases/latest/download/appcast.xml` automatically and provides **Ichido → Check for Updates…**. Sparkle verifies the signed feed and ZIP before installation. The GitHub repository and release assets must stay public for this URL to work.
- The first hop from the ad-hoc 0.0.3 install to this Developer ID signature keeps the same Ed25519 key. Sparkle's documented rotation rule assumes the installed app is already Developer ID signed. Test an installed 0.0.3 against the first notarized appcast. If Sparkle refuses the signature change, that install needs one manual download of the notarized zip. Later updates then follow the appcast. Do not call the update seamless until that installed-build test has passed. Keep the app in Applications, not a read-only disk image.

## Distribution

Tag releases Developer ID-sign, notarize, and staple. The public download is that stapled zip. It is a direct download, not a Mac App Store install.

**Notarize** signs with the Developer ID Application certificate for team `88HMB5SB4X` (the common name comes from the imported certificate). **Release** calls that workflow with publishing turned on. If a required secret is missing, or the certificate is not a Developer ID Application identity for that team, the job fails and does not fall back to an ad-hoc zip.

Secrets, set in GitHub Actions and not committed: `CSC_P12_BASE64` (base64 of the Developer ID Application `.p12`), `CSC_P12_PASSWORD`, `NOTARY_KEY` (notarytool API `.p8` contents, or base64 of that file), `NOTARY_KEY_ID`, `NOTARY_ISSUER`, and the existing `SPARKLE_ED25519_PRIVATE_KEY`. Leave the Sparkle key as it is. The notary key submits the zip to Apple. It does not create a Mac App Store listing.
