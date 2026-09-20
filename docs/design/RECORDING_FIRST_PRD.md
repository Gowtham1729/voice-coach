# Voice Coach: recording-first product direction

- **Status:** Product contract for implementation, 20 September 2026
- **Platform:** Native, local-first macOS app
- **Decision:** Remove the New Session form. Recordings open directly. Mimic stays a workspace. Retry stacks stay visible. Do not introduce a third noun “Practice.”

This document supersedes the optional-Practice model in the earlier recording-first draft. It is not an approval to change DSP, report JSON, or the local-only privacy posture.

## 1. Verdict

Kill the New Session form. Name, mode, and “Save every take” before any audio is paperwork. Record, Import, and Mimic start as themselves.

Do not flatten grouping. Mimic is a real target (one reference + attempts). So is “three versions of the same answer.” Empty timestamped folders (`Quick Practice · Sep 20`) are not.

Do not add **Practice** as a user-facing noun. v1 grouping is a **retry stack** (visible related recordings + Record again) and a **Mimic** (reference + attempts). Call neither Session. Add named Practices later only if stacks and Mimic are not enough.

## 2. User-facing model

| Term | Meaning |
| --- | --- |
| Recording | One saved capture or import + analysis. Opens directly. Default title `Recording · 20 Sep, 1:04 AM` or imported filename. Editable in place. |
| Retry stack | Visible set from **Record another**, or a migrated session with a prompt or two or more takes. Numbered attempts, shared prompt if any, one Record again action. |
| Mimic | One reference excerpt + attempts. Name from the source file. Always a first-class destination. |
| Take / attempt | Numbering inside a Mimic or retry stack. Library uses that numbering when grouped. |
| Session | Legacy storage (`CoachingSession`) only. Not a create action. |

## 3. Navigation

- **Home:** Record, Import, Mimic. Recent recordings. Continue Mimic for the last-used Mimic (always on, not count-dependent).
- **Library:** Chronological recordings, including Mimic attempts and stack members. Search title, date, source, transcript if present, old session name, and prompt. Filters: all / recorded / imported / Mimic.
- **Mimics:** Always a sidebar item listing Mimic *items* (reference + attempt count), not flattened takes.
- Settings stays. Insights averages are gone; Home/Library show user-recorded counts excluding imports and references.
- There is no takes-list screen. A retry stack is visible as grouped Library rows, the Take 1 of N picker on Recording detail, and the shared prompt pinned on the detail. **Back from any Recording returns to Library.**

Do not decode dense analysis merely to render Library.

## 4. Entry flows

1. **Home Record** always creates a standalone Recording. It never appends to an open Mimic. Cancel / too short / permission denied creates nothing.
2. **Record another** on a standalone Recording (or stack member) stays in that lineage and opens the new Recording directly.
3. **Home Import** opens the file chooser. Cancel creates nothing. Success is a Recording marked imported, not counted as practice time. **Use as Mimic reference** is an explicit action on that Recording.
4. **Mimic** → Import Audio/Video or Capture Mac Audio → trim excerpt → Mimic workspace. No session name step. Try Again appends an attempt. Home Record does not.
5. Opening a Mimic attempt from Library lands in **Mimic Compare for that take**. Row title: `source name · Take N · time`.

## 5. Locked behavior

**Library rows**

- Standalone: edited title or `Recording · date`; imported filename if import.
- Stack member: `title or prompt excerpt · Take N · time`.
- Mimic attempt: `source name · Take N · time`.
- Mimic reference is not a user Recording and is not practice time.

**Delete / archive**

- Delete one Recording: siblings and Mimic reference stay. Take numbers keep original indexes (do not renumber).
- Archive Mimic: hide from Continue / Mimics; keep attempts, reference, comparisons.
- Delete Mimic: confirm copy names the reference and attempt count, then remove files.
- Deleting the last attempt does not delete the reference.
- Empty leftover sessions: Settings cleanup. No ghosts on disk with no UI.

**Migration (no file moves in the first UI pass)**

- Mimic sessions → Mimic items.
- General sessions with a prompt or ≥2 takes → retry stacks. Keep the name; pin `prompt` on the stack.
- Empty shells and single-take Quick Practice folders → standalone Recordings; old name as subtitle.
- Do not merge same-named sessions. Do not auto-delete empty ones.
- Search includes old session names and prompts.
- Legacy `keepsRecordings == false`: before the first new save, “Keep all from now on” (default) vs old replace, with a warning. New work always keeps valid recordings.

**Keyboard**

- Space on Home starts Record when idle.
- ⌘N Record (no longer New Session).
- Navigate ⌘1 Home, ⌘2 Library, ⌘3 Mimics.
- Library rows announce Take N of Mimic source, not only “Recording, date.”

## 6. Implementation boundary

Keep `CoachingSession` / `PracticeSession` as storage types. Put a Recording-oriented application API over `SessionLibrary` (lookup by take ID, optional Mimic membership, retry-stack membership, recorded vs imported). UI code should request recordings by stable take ID, not by “selected session” as the user-facing object.

Do not change `ReportFormatter` JSON, acoustic algorithms, or introduce cloud/medical fields.

## 7. Pointers

- `Sources/VoiceCoachApp/SessionLibrary.swift` — storage + recording catalog
- `Sources/VoiceCoachApp/AppModel.swift` — capture, import, navigation
- `Sources/VoiceCoachApp/HomeView.swift` — Home
- `Sources/VoiceCoachApp/DesktopShell.swift` — stack workspace, Library, Mimics
- `Sources/VoiceCoachApp/CreateSessionView.swift` — Mimic start only
- `Sources/VoiceCoachApp/MimicWorkspace.swift` — Mimic practice/compare
- `Sources/VoiceCoachApp/RenderPreviews.swift` — layout + migration fixtures
