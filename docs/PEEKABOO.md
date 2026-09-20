# Peekaboo QA & Automation Guide for Voice Coach

This guide details how coding agents and developers can build, run, inspect, and automate QA testing on **Voice Coach** using [Peekaboo](https://github.com/stephancill/peekaboo) on macOS.

---

## 1. Environment & Prerequisites

Peekaboo uses macOS Accessibility (AXorcist) and ScreenCaptureKit to automate native macOS apps.

- **Executable path**: `/opt/homebrew/bin/peekaboo` (or on `$PATH`)
- **Required permissions**:
  - `Accessibility` (Required): Allows inspecting the accessibility tree, clicking buttons, typing, and reading UI state.
  - `Screen Recording` (Required for visual captures): Allows capturing full-resolution window screenshots (`--path`) and annotated overlays (`--annotate`).
  - `Event Synthesizing` (Optional / Granted): Allows synthetic clicks and key chords.

Check permission status anytime:
```sh
peekaboo permissions
```

---

## 2. Fast Build & Launch

Always build the production app and launch the bundle directly:

```sh
# 1. Build & codesign the app
./scripts/build-app.sh

# 2. Kill existing process if running, then launch
pkill -x VoiceCoachApp 2>/dev/null || true
open "build/Voice Coach.app"

# 3. Verify process PID
pgrep -l VoiceCoachApp
```

> **Target App Name Gotcha:**  
> Always use `--app "Voice Coach"` in Peekaboo commands.  
> Do **not** use `VoiceCoachApp` — Peekaboo will treat it as a fuzzy executable match and reject mutation operations (`click`, `set-value`, `type`).

---

## 3. Inspecting the UI

### Fast Accessibility Tree Inspection (~0.1s)
When you only need to check state, verify element presence, or obtain element IDs without taking a screenshot:
```sh
peekaboo see --app "Voice Coach" --tree --no-screenshot
```

### Capturing Screenshots
Capture full-window screenshot:
```sh
peekaboo see --app "Voice Coach" --path /tmp/voice_coach_screen.png
```

Capture with visual interactive element bounding boxes & labels:
```sh
peekaboo see --app "Voice Coach" --path /tmp/voice_coach_screen.png --annotate
# Annotated output is automatically saved to /tmp/voice_coach_screen_annotated.png
```

### JSON Inspection (for scripts & parsing)
```sh
peekaboo see --app "Voice Coach" --tree --no-screenshot --json
```
UI elements will be in `data.ui_elements`, with fields `id`, `role`, `ax_role`, `label`, `value`, `is_value_settable`, and `bounds`.

---

## 4. Multi-Window Handling (Settings)

Voice Coach uses standard macOS window architecture:
- Main Studio Window: Index `1` (or window ID)
- Settings Window (Command+, or Settings gear): Appears as a separate window.

List open windows:
```sh
peekaboo window list --app "Voice Coach"
```

Inspect or interact with the Settings window (e.g. index 2):
```sh
# Inspect Settings window
peekaboo see --app "Voice Coach" --window-index 2 --tree --no-screenshot

# Capture Settings screenshot
peekaboo see --app "Voice Coach" --window-index 2 --path /tmp/voice_coach_settings.png

# Click tabs inside Settings
peekaboo click "Transcription" --app "Voice Coach" --window-index 2
peekaboo click "General" --app "Voice Coach" --window-index 2
peekaboo click "Library" --app "Voice Coach" --window-index 2

# Close Settings window
peekaboo click "close button" --app "Voice Coach" --window-index 2
```

---

## 5. User Interaction Recipes

### Clicking Elements
You can click by visible label, role description, or opaque element ID from the latest snapshot:
```sh
# Click by text
peekaboo click "Home" --app "Voice Coach"
peekaboo click "Library" --app "Voice Coach"
peekaboo click "Mimics" --app "Voice Coach"

# Click by element ID
peekaboo click --on elem_84 --app "Voice Coach"

# Toggle checkboxes (Pitch, Loudness, Spectrum)
peekaboo click "Loudness" --app "Voice Coach"
```

### Text Input & Search
```sh
# Direct accessibility value set (fastest, no focus required):
peekaboo set-value "Stress" --on elem_161 --app "Voice Coach"

# Clear search field using the SwiftUI searchable cancel button:
peekaboo click "cancel" --app "Voice Coach"

# Or type using synthetic keystrokes with auto-clear:
peekaboo type "Stress" --app "Voice Coach" --clear
```

### Verifying Clipboard Outputs
Test export / copy actions (such as **"Copy coach notes"**):
```sh
# Trigger the copy in the app
peekaboo click "Copy coach notes" --app "Voice Coach"

# Inspect clipboard content directly
peekaboo clipboard get
```

### Collapsing & Expanding Navigation Panes
```sh
# Toggle Sidebar
peekaboo click "Hide Sidebar" --app "Voice Coach"
peekaboo click "Show Sidebar" --app "Voice Coach"

# Toggle Right Inspector
peekaboo click "Hide Inspector" --app "Voice Coach"
peekaboo click "Show Inspector" --app "Voice Coach"
```

---

## 6. Critical Agent Gotchas

1. **Snapshot Staleness (`Snapshot is stale`)**:
   - Whenever an interaction alters the UI (navigation change, window resize, tab switch), the previous snapshot's coordinate map and element IDs are invalidated.
   - If a click fails with `Snapshot is stale`, run a quick refresh before retrying:
     ```sh
     peekaboo see --app "Voice Coach" --tree --no-screenshot > /dev/null && peekaboo click "<Target>" --app "Voice Coach"
     ```

2. **Background by Default**:
   - Peekaboo dispatches background AX events and coordinates without stealing system focus. You do not need to bring the app to the foreground unless testing active window focus states.

3. **Settable Values vs Buttons**:
   - SwiftUI `.searchable` search bar creates both an `AXTextField` and a magnifying glass `AXButton`. When targeting search, target the `textField` role or element ID rather than the generic `"Search"` query if Peekaboo hits the button.

---

## 7. Standard QA Test Checklist

Run through these scenarios when performing an automated QA pass:

1. **Home Dashboard**:
   - [ ] Stats cards render (recordings count, total duration, Mimic count).
   - [ ] Action buttons present (`Import`, `Mimic`, `Record`).
   - [ ] Recents list populated and clickable.

2. **Take Analysis**:
   - [ ] Open a recording take.
   - [ ] Verify Waveform scrubber and pitch contour render.
   - [ ] Toggle contour filters (`Pitch`, `Loudness`, `Spectrum`).
   - [ ] Check acoustic metrics panel (Pitch range, Drop at phrase end, Clarity, Pauses).
   - [ ] Test **"Copy coach notes"** and verify report JSON via `peekaboo clipboard get`.

3. **Library View**:
   - [ ] Table columns display `RECORDING`, `DURATION`, `DATE`.
   - [ ] Search filtering responds to input.
   - [ ] Clear button resets the search filter.

4. **Mimics Workspace**:
   - [ ] List of Mimic templates and recorded attempts renders.
   - [ ] Open a Mimic (e.g. `Stress Perception Impact`).
   - [ ] Mode switcher operates cleanly between `Practice`, `Compare`, and `Analysis`.
   - [ ] Dual transcript shows aligned Reference and User text.
   - [ ] Word buttons in Analysis mode show valid start-end timings.

5. **Settings Modal**:
   - [ ] Open Settings with gear icon.
   - [ ] Verify engine readiness on `Transcription` tab (System & Parakeet).
   - [ ] Close modal cleanly.

6. **Self-Test Contracts**:
   - [ ] In tandem with UI testing, run `./scripts/test.sh --self-test` to ensure DSP and JSON contracts remain unbroken.
