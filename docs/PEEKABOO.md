# Peekaboo UI Testing Guide for Ichido

How coding agents and developers can build, run, inspect, and test **Ichido** using [Peekaboo](https://github.com/stephancill/peekaboo) on macOS.

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

# 2. Relaunch Ichido
pkill -x VoiceCoachApp 2>/dev/null || true
open "build/Ichido.app"

# 3. Verify process PID
pgrep -l VoiceCoachApp
```

> **Target App Name Rule:**
> Always specify `--app "Ichido"` in Peekaboo commands.
> Do **not** use `VoiceCoachApp` — Peekaboo flags executable names as fuzzy matches and rejects mutation operations (`click`, `set-value`, `type`).

---

## 3. Inspecting the UI & Screenshots

### Fast Accessibility Tree (~0.1s, no screenshot)
Check UI hierarchy, element labels, and find IDs without saving images:
```sh
peekaboo see --app "Ichido" --tree --no-screenshot
```

### Visual Window Screenshots
```sh
# Clean screenshot
peekaboo see --app "Ichido" --path /tmp/voice_coach_screen.png

# Annotated screenshot with element IDs and bounding boxes
# (saves annotated image to /tmp/voice_coach_screen_annotated.png)
peekaboo see --app "Ichido" --path /tmp/voice_coach_screen.png --annotate
```

### Structured JSON Inspection
```sh
peekaboo see --app "Ichido" --tree --no-screenshot --json
```
Elements appear under `data.ui_elements` with `id`, `role`, `ax_role`, `label`, `value`, `is_value_settable`, and `bounds`.

---

## 4. Multi-Window Handling (Settings)

Ichido uses standard macOS window architecture where Settings is a separate window.

List open windows:
```sh
peekaboo window list --app "Ichido"
```

Inspect or interact with the Settings window (`--window-index 2`):
```sh
# Inspect Settings tree
peekaboo see --app "Ichido" --window-index 2 --tree --no-screenshot

# Capture Settings screenshot
peekaboo see --app "Ichido" --window-index 2 --path /tmp/voice_coach_settings.png

# Switch tabs in Settings
peekaboo click "Transcription" --app "Ichido" --window-index 2
peekaboo click "General" --app "Ichido" --window-index 2
peekaboo click "Library" --app "Ichido" --window-index 2
peekaboo click "Experiments" --app "Ichido" --window-index 2

# Close Settings
peekaboo click "close button" --app "Ichido" --window-index 2
```

---

## 5. Interaction Recipes

### Clicking Elements
Click by label, role description, or opaque element ID (`--on`):
```sh
# Click by button / navigation label
peekaboo click "Home" --app "Ichido"
peekaboo click "Library" --app "Ichido"
peekaboo click "Practice" --app "Ichido"

# Click by snapshot element ID
peekaboo click --on elem_84 --app "Ichido"

# Toggle contour filters
peekaboo click "Loudness" --app "Ichido"
```

### Text Input & Search
```sh
# Direct accessibility value set (fastest, no focus required):
peekaboo set-value "Stress" --on elem_161 --app "Ichido"

# Clear search field via SwiftUI searchable cancel button:
peekaboo click "cancel" --app "Ichido"

# Or type using keystrokes with auto-clear:
peekaboo type "Stress" --app "Ichido" --clear
```

### Verifying clipboard output
The menu item is **Copy AI analysis prompt + JSON** (`⌥⌘C`), not a coach-notes button:
```sh
peekaboo click "Copy AI analysis prompt + JSON" --app "Ichido"
peekaboo clipboard get
```

### Collapsing & Expanding Navigation Panes
```sh
# Toggle Sidebar
peekaboo click "Hide Sidebar" --app "Ichido"
peekaboo click "Show Sidebar" --app "Ichido"

# Toggle Right Inspector
peekaboo click "Hide Inspector" --app "Ichido"
peekaboo click "Show Inspector" --app "Ichido"
```

---

## 6. Critical Agent Gotchas

1. **Snapshot Staleness (`Snapshot is stale`)**:
   - Whenever an action alters the UI (navigation, window bounds change, tab switch), previous snapshot element IDs and coordinates are invalidated.
   - If a command fails with `Snapshot is stale`, run a quick refresh before retrying:
     ```sh
     peekaboo see --app "Ichido" --tree --no-screenshot > /dev/null && peekaboo click "<Target>" --app "Ichido"
     ```

2. **Background Dispatch**:
   - Peekaboo sends events in the background without stealing system focus. Pass `--foreground` only if you specifically need window focus testing.

3. **Search Text Field vs Button**:
   - SwiftUI's `.searchable` exposes both an `AXTextField` and an `AXButton` with the label "Search". Target the text field element ID or use `peekaboo type` instead of querying generic "Search" if it accidentally clicks the search icon.
