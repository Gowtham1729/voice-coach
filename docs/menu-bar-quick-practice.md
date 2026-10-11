# Menu bar quick practice

Ichido's ribbon appears in the menu bar while the app is running. Click it to
**Capture Mac audio** while another app plays a clip. Capture uses the existing
local Core Audio process tap, excludes Ichido's own playback, and does not record
the microphone. It retains the existing 90-second limit and audio-validation gates.

**Stop and review** opens the normal reference sheet. Choose a phrase, check the
speech language, and **Start practice** to save the reference. Automatic stop and
capture interruptions leave a **Review capture…** action in the menu bar; they
do not bring a sheet in front of the source app. A checkmark on the ribbon marks
a prepared clip. **Discard capture** deletes the staged audio. A capture is not a
saved practice session until the existing creation flow succeeds.

The compact capture panel shows elapsed time, the audio meter, and whether Mac
audio is currently arriving. **Continue practice** identifies the saved reference
by name and clip length. **Record my voice** and **Open Ichido** open the main
window; the native **…** options menu holds **Settings…** and **Quit Ichido**. Capturing,
permission requests, preparation, and unsaved practice work block conflicting
quick actions. A filled dot on the ribbon indicates active capture or recording;
the menu gives the status in words and shows elapsed time. Closing the main window
keeps the app and capture running. Quit asks before discarding an active recording
or captured reference and waits while audio is being prepared.

**Settings → General → Show Ichido in the menu bar** controls visibility. It is
enabled by default for discoverability; visibility cannot be turned off while a
menu bar reference needs review. The in-app reference capture flow remains
available when the icon is hidden. This does not enable launch at login.

## Design guidance

- [Apple HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar):
  compact template icon, user-controlled visibility, and equivalent in-app access.
  The ribbon uses black and transparent pixels so macOS can tint it for the menu
  bar appearance and selection. Three strokes preserve the existing brand at a
  small size; recording and ready badges also distinguish state without color.
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra):
  the window style is used for the live level meter, elapsed time, and capture
  controls. Trimming and transcription settings stay in the main app. Plain
  action menus are the HIG default; these live controls justify the compact
  window-style exception.
- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps):
  reuse the shipping process-tap service and its audio permission rather than
  introduce screen capture or a second recording pipeline.

The local Mac follow-up uses the existing desktop panel material for the capture
area, system glass buttons, full-row secondary actions, and a native options menu.
Recent practice includes its name and duration. Capture errors give a short
recovery step; **Show details…** opens the full error in Ichido.

Actual Mac captures: [idle popup](screenshots/12-menu-bar-quick-practice.png) and
[live audio meter](screenshots/13-menu-bar-capturing.png). These use an isolated
library with generated speech.

## Local Mac verification

Requires macOS 26+ and an Xcode toolchain supporting Swift 6.2 or later. Synthetic tests do not establish
real audio routing or permissions.

1. Check out the PR branch and run `./scripts/test.sh --all`, then
   `./script/build_and_run.sh`. Confirm a normal Dock icon, launch window, and
   menu bar ribbon. Open the menu in Light and Dark appearance; check keyboard
   navigation, VoiceOver labels, and Reduce Transparency / Reduce Motion.
2. Play spoken audio in another app. Click **Capture Mac audio**. Check permission
   handling, elapsed time, and the Mac audio meter. Click outside the menu and
   verify capture continues without bringing Ichido forward.
3. Click **Stop and review**. Confirm the existing main window comes forward
   (also test minimized and closed windows), the full captured clip is available
   for trimming, and **Start practice** opens a usable reference. Record a take
   with Listen & Repeat and Speak Along. Confirm the reference survives relaunch.
4. Repeat with silence, a capture shorter than a second, denied permissions,
   and a capture allowed to reach 90 seconds. Rejected clips must not create a
   library entry. Auto-stop should leave a review action without taking focus.
5. Discard an active capture and a prepared clip. Verify no draft or temporary
   WAV remains. Double-click Start; try microphone recording and Import during
   capture and during preparation. They must not replace or interrupt the clip.
6. Close the main window while capturing. Confirm the menu can stop/review the
   clip. Test Quit from both the menu bar and Command-Q: cancel preserves capture;
   discard quits and removes staged audio.
7. Try Record my voice and Continue practice. Test visibility off/on in General
   Settings, relaunch with visibility off, and capture from the in-app reference
   sheet. Do not expect launch-at-login behavior.

For layout previews run `./scripts/render-previews.sh`. For live interaction
checks use [PEEKABOO.md](PEEKABOO.md) after CI passes. Linux cannot build the Mac
app or visually verify this menu bar surface.

## Mac follow-up to PR 108

Local investigation on macOS 27.0.1 / Xcode 27 found three failures that the Linux
handoff could not expose:

- MenuBarExtra repeatedly wrote its unchanged insertion state through AppStorage,
  causing a launch-time scene-update loop. The binding now ignores unchanged values.
- Core Audio startup could wait on the recording-permission dialog on the main
  thread. Startup now completes asynchronously, with cancellation and stale-result
  cleanup before another capture is allowed.
- A dismissed reference sheet could run its disappearance cleanup after a new
  background capture started. Cleanup now belongs to explicit cancellation,
  sheet dismissal, and successful creation.

Capture and microphone timers use common run-loop modes so menu tracking does not
pause elapsed time or the capture limit. Reference-source actions preserve a
background capture, and quit protection includes in-app drafts and pending takes.

Automated verification includes the full Core, Session, and App test suites,
SelfTest, the release app build and signature verification, and light/dark menu
layout previews. An opt-in DEBUG device check uses `--test-library <isolated-path>`
and `--capture-smoke <generated-speech.wav>`; optional flags
`--capture-smoke-auto-stop` and `--capture-smoke-self-playback` check the 90-second
limit, discard cleanup, and exclusion of Ichido's own playback. It writes
`capture-smoke.json` inside the isolated test library and never reads the personal
library. Release builds do not expose these flags.

The controlled device run captured and transcribed 7.02 seconds of generated
speech, saved and reloaded the reference, automatically stopped a repeated capture
at 89.83 seconds of audio, deleted its staged WAV on discard, and excluded the app's
own reference playback. This establishes the tested speaker route; it does not
establish every microphone, headphone, Bluetooth, permission-denial, or
assistive-technology configuration.

Live popup clicks also verified Capture → incoming audio meter → Stop and review
→ reference sheet, and Cancel returned to Home. The capture remains local and
uses the normal reference-creation flow. Keyboard/VoiceOver traversal and all
window/quit permutations still need the manual checklist above.
