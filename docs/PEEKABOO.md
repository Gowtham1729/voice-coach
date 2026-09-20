# Peekaboo UI Testing Guide for Voice Coach

How coding agents and developers can build, run, inspect, and test **Voice Coach** using [Peekaboo](https://github.com/stephancill/peekaboo) on macOS.

---

## 1. Environment & Prerequisites

Peekaboo uses macOS Accessibility (AXorcist) and ScreenCaptureKit.

- **Binary path**: `/opt/homebrew/bin/peekaboo`
- **Required permissions**:
  - `Accessibility` (Required): Tree inspection, clicks, typing, and state verification.
  - `Screen Recording` (Required for visual captures): Full-resolution screenshots (`--path`) and annotated overlays (`--annotate`).
  - `Event Synthesizing` (Optional / Granted): Synthetic clicks and keyboard chords.

Check permissions:
```sh
peekaboo permissions
```

---

## 2. Fast Build & Launch

Build the app and launch the bundle:

```sh
# 1. Build & codesign
./scripts/build-app.sh

# 2. Relaunch Voice Coach
pkill -x VoiceCoachApp 2>/dev/null || true
open "build/Voice Coach.app"

# 3. Verify process PID
pgrep -l VoiceCoachApp
```

> **Target App Name Rule:**  
> Always specify `--app "Voice Coach"` in Peekaboo commands.  
> Do **not** use `VoiceCoachApp` — Peekaboo flags executable names as fuzzy matches and rejects mutation operations (`click`, `set-value`, `type`).

---

## 3. Inspecting the UI & Screenshots

### Fast Accessibility Tree (~0.1s, no screenshot)
Check UI hierarchy, element labels, and find IDs without saving images:
```sh
peekaboo see --app "Voice Coach" --tree --no-screenshot
```

### Visual Window Screenshots
```sh
# Clean screenshot
peekaboo see --app "Voice Coach" --path /tmp/voice_coach_screen.png

# Annotated screenshot with element IDs and bounding boxes
# (saves annotated image to /tmp/voice_coach_screen_annotated.png)
peekaboo see --app "Voice Coach" --path /tmp/voice_coach_screen.png --annotate
```

### Structured JSON Inspection
```sh
peekaboo see --app "Voice Coach" --tree --no-screenshot --json
```
Elements appear under `data.ui_elements` with `id`, `role`, `ax_role`, `label`, `value`, `is_value_settable`, and `bounds`.

---

## 4. Multi-Window Handling (Settings)

Voice Coach uses standard macOS window architecture where Settings is a separate window.

List open windows:
```sh
peekaboo window list --app "Voice Coach"
```

Inspect or interact with the Settings window (`--window-index 2`):
```sh
# Inspect Settings tree
peekaboo see --app "Voice Coach" --window-index 2 --tree --no-screenshot

# Capture Settings screenshot
peekaboo see --app "Voice Coach" --window-index 2 --path /tmp/voice_coach_settings.png

# Switch tabs in Settings
peekaboo click "Transcription" --app "Voice Coach" --window-index 2
peekaboo click "General" --app "Voice Coach" --window-index 2
peekaboo click "Library" --app "Voice Coach" --window-index 2

# Close Settings
peekaboo click "close button" --app "Voice Coach" --window-index 2
```

---

## 5. Interaction Recipes

### Clicking Elements
Click by label, role description, or opaque element ID (`--on`):
```sh
# Click by button / navigation label
peekaboo click "Home" --app "Voice Coach"
peekaboo click "Library" --app "Voice Coach"
peekaboo click "Mimics" --app "Voice Coach"

# Click by snapshot element ID
peekaboo click --on elem_84 --app "Voice Coach"

# Toggle contour filters
peekaboo click "Loudness" --app "Voice Coach"
```

### Text Input & Search
```sh
# Direct accessibility value set (fastest, no focus required):
peekaboo set-value "Stress" --on elem_161 --app "Voice Coach"

# Clear search field via SwiftUI searchable cancel button:
peekaboo click "cancel" --app "Voice Coach"

# Or type using keystrokes with auto-clear:
peekaboo type "Stress" --app "Voice Coach" --clear
```

### Verifying Clipboard Outputs
Test export / copy actions (e.g. **"Copy coach notes"**):
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
   - Whenever an action alters the UI (navigation, window bounds change, tab switch), previous snapshot element IDs and coordinates are invalidated.
   - If a command fails with `Snapshot is stale`, run a quick refresh before retrying:
     ```sh
     peekaboo see --app "Voice Coach" --tree --no-screenshot > /dev/null && peekaboo click "<Target>" --app "Voice Coach"
     ```

2. **Background Dispatch**:
   - Peekaboo sends events in the background without stealing system focus. Pass `--foreground` only if you specifically need window focus testing.

3. **Search Text Field vs Button**:
   - SwiftUI's `.searchable` exposes both an `AXTextField` and an `AXButton` with the label "Search". Target the text field element ID or use `peekaboo type` instead of querying generic "Search" if it accidentally clicks the search icon.
