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

The menu also offers **Record my voice**, **Continue practice** when there is a
saved reference, **Open Ichido**, **Settings…**, and **Quit Ichido**. Capturing,
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

## Local Mac verification

Requires macOS 26+, Xcode 26.x, and Swift 6.2. Synthetic tests do not establish
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
