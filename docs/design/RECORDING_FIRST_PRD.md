# Voice Coach: recording-first product direction

- **Status:** Proposed product requirements, 19 September 2026, for design review and implementation planning
- **Platform:** Native, local-first macOS app
- **Decision sought:** Replace mandatory Sessions → Takes navigation with a recording-first experience, while retaining intentional, reusable practice contexts
**Scope of this document:** Product behavior, information architecture, migration, acceptance, and agent handoff. It is not an approval to change the acoustic model, export contract, or cloud/privacy posture.

## 1. Executive decision

Voice Coach should help someone **speak, hear what happened, make another attempt, and find that work later**. Today the app makes a user choose or create a session before an ordinary recording has any value. That is a storage relationship masquerading as the primary user workflow.

Make a **Recording** the durable, independently discoverable object. A recording can be captured or imported, reviewed, renamed, exported, deleted, and searched without belonging to a user-visible container. Within a repeated exercise, the same object is called an **attempt** or **take** and may be numbered relative to that exercise.

Keep **Practice** as an optional, intentional object: a reusable goal, prompt, or Mimic reference with a history of attempts. Do not create one for every quick recording. The Mimic reference is a target, not a recording of the user's practice and not an attempt. Retire “Session” from new user-facing flows; retain it only as a compatibility concept until existing libraries are safely migrated.

This is more than a navigation cleanup. The new product loop is:

**Start → Capture/import → Review and listen → Retry or leave → Retrieve later.**

The app should provide useful evidence without pretending that an acoustic measurement is a grade, a diagnosis, or proof of improvement.

## 2. Why change

### User jobs, not current screens

| Job | What a successful experience feels like | Current friction to remove |
| --- | --- | --- |
| Capture a thought or rehearsal | Start speaking immediately and trust that a valid recording is saved | Name and configure a session, or enter an old one first |
| Analyze an existing clip | Import once, then open its audio and analysis | An import is silently attached to the selected session; canceling can leave an empty quick session |
| Improve a specific delivery | Repeat the same task with the target and previous attempts in view | Ordinary takes have weak identities; repeated work depends on a generic session |
| Mimic a reference | Keep one reference stable, compare attempts, retry | This already has a meaningful grouping relationship; it must survive simplification |
| Find something later | Search a recording by title, date, source, or locally available words | The library indexes sessions first and hides takes a level deeper |
| Understand progress | Compare like with like, and know when evidence is insufficient | Global averages combine unrelated tasks and imported media |

These are **product hypotheses based on the current implementation**, not validated claims about user behavior. A short usability study should test them before declaring success.

The opportunity is not to become a prettier audio-file manager. A useful coach helps the user close a loop: **hear an attempt, inspect a specific moment, decide what to try, and repeat**. The first release should remove friction and make the evidence easy to reach. A subsequent release can surface one or two timestamped, factual review moments (for example, the longest pause or a clipped segment) when the signal is reliable, with a tap to hear that moment. It should not manufacture advice from a weak metric or bury listening under a wall of charts.

### Perspectives a leadership review should challenge

- **New user:** Can I make a useful first recording without understanding the data model?
- **Frequent practitioner:** Can I repeat an exercise in one action and find the right prior attempt?
- **Occasional importer:** Can I analyze a file without accidentally counting another person's audio as my own practice?
- **Accessibility user:** Are the primary action, recording state, transport, result, and errors usable with keyboard and VoiceOver, not only visually?
- **Privacy-conscious user:** Is everything local, and can I tell exactly what is saved and deleted?
- **Product and research:** Are displayed comparisons fair across different scripts, durations, devices, and sources? What evidence would change our decision?
- **Engineering and support:** Can old libraries open with every audio file intact, including empty sessions and Mimic references?

## 3. Product principles and boundaries

1. **The next useful action wins.** Record, Import, and Mimic are visible without a setup form. Ask for a name or goal only when it helps the user.
2. **One object, one clear meaning.** A Recording is an audio artifact and its analysis. A Practice is a reusable target and its attempts. A Reference is source material for Mimic, not a user's attempt.
3. **Grouping is earned.** A user creates or resumes a Practice because they intend to repeat a target, not because the app needs a folder.
4. **Evidence before interpretation.** Preserve objective acoustic data, transcript uncertainty, and original audio. Avoid scores, rankings, diagnoses, and unsupported “better/worse” claims.
5. **Safe by default.** Keep valid recordings; never silently replace an older one. Deletion and migration must be explicit and recoverable where practical.
6. **Local-first is a product promise.** No cloud upload or mandatory account, LLM, or network dependency. Failure of optional transcription never discards a valid recording.
7. **Native and dense, not dashboard theater.** Keep standard macOS navigation, toolbar, menus, inspector, shortcuts, materials, and accessibility behavior. Put the recording and its evidence ahead of decorative cards.

## 4. Options considered

| Direction | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Keep Sessions → Takes and improve copy | Small implementation change; preserves Mimic | Still asks every user to understand a parent object | Reject as the primary model |
| Flatten everything into a list of takes | Fast capture and retrieval | Loses stable Mimic targets and intentional repetition | Reject |
| Make Recordings primary; Practices optional | Simple default and a home for repeated work | Requires careful navigation and migration | **Recommend** |
| Automatically create a dated session each day | Hides a setup form | Creates invisible grouping rules and ambiguity across days | Reject |

The word **“Take”** remains valuable *inside* a Practice (“Take 2 of 3”). In the global library, use **“Recording”**: “Take 2” without its target is not a useful identity.

## 5. Proposed information architecture

### Primary navigation

- **Home:** Record, Import, Start Mimic; recent recordings; a small “Continue practice” area when applicable. Home is not the last-selected session.
- **Library:** All saved recordings, including practice attempts, in one searchable chronological list. A recording opens directly.
- **Practices:** Reusable goals/prompts and Mimic references, each with its attempt history. Empty state explains when to create one.
- **Settings:** Existing local storage, transcription, privacy, and app preferences.

Do **not** retain “All Sessions” or session recents as parallel primary navigation. Do not promote the current global “Insights” page unchanged. Its all-take averages mix unlike work and can imply progress that the data cannot support. In the first release, put trustworthy activity facts in Library/Practice and defer a dedicated **Progress** destination until it has a clear question and comparison rules.

For someone who does not know what to say, Home may offer one small, optional, locally bundled practice starter (for example, “Explain an idea in 30 seconds”). It must never gate Record behind a prompt picker or pretend a starter is a personalized plan.

### Domain language

| User-facing term | Meaning | Notes for implementation |
| --- | --- | --- |
| Recording | One saved audio artifact and its analysis | Stable ID, independent library entry; imported clips are marked as imports |
| Practice | An optional reusable task or goal with attempts | May contain a prompt, or a Mimic reference and style |
| Take / attempt | A recording in the context of one Practice | Numbering is local to that Practice, not its global title |
| Reference | Imported target audio for Mimic | Stored separately; not counted as user practice or a take |
| Session | Legacy storage/user concept only | Must remain readable during migration, not a new creation action |

Do not add a separate “Project,” “Folder,” “Collection,” and “Session” vocabulary in this release. If users later need free-form organization, validate it before introducing another noun.

## 6. Target journeys and screen requirements

### A. First recording

1. Home presents **Record** as the primary action, **Import** as a secondary action, and **Mimic a reference** as a distinct practice path. No name, mode, or retention question precedes capture.
2. Record requests microphone permission only when necessary. The recording surface shows device, live level, elapsed time, Stop, and an unambiguous cancel/discard path. The existing duration and minimum-valid-audio safeguards remain.
3. On Stop, a valid audio file is protected immediately while on-device analysis runs. Show progress and a plain explanation of what is still available if transcription is missing. A failed analysis must not silently lose the audio; offer retry or export/reveal recovery where feasible.
4. Open the saved Recording detail. Give it a predictable default title such as “Recording · 19 Sep, 10:30 AM,” editable in place. Do not automatically turn an uncertain or private transcript into a title. A transcript excerpt may aid recognition, with an option to hide previews in the library.
5. Show **Record another** and **Back to Library/Home**. “Record another” carries the current intent forward and links the two recordings as retries without forcing a named Practice. It must not overwrite the first.

**Empty, interrupted, or denied states:** Canceling before a valid recording leaves no library item. A permission denial gives a clear route to macOS settings without a dead-end sheet. An interruption preserves recoverable captured audio according to the existing recorder safety behavior. Never create an empty Practice as a side effect.

### B. Import for analysis

1. Import opens the file chooser directly; Cancel creates nothing. Audio and video normalization remain local.
2. A successful import becomes a Recording with an import source marker, original filename as an editable suggested title, audio, transcript if available, and analysis. A long analysis should show progress and recover gracefully.
3. An imported clip is **not automatically counted as the user's speaking-practice time**. Imported material may be another speaker or a reference. It can still be reviewed and exported.
4. “Use as Mimic reference” is a separate, explicit route; it never converts a user's saved recording or an imported analysis into a reference silently.

### C. Review a Recording

- Center: editable title/context, transcript with time-linked playback, Pitch/Loudness/Spectrum views, and the sticky waveform transport. Preserve the existing detailed measurements and export actions.
- Inspector: concise objective measurements, recording/source metadata, Copy Coach Prompt, Copy Raw JSON, Export Audio + JSON, Reveal Audio, and Delete. The screen must work with the inspector hidden.
- Contextual actions: **Record another**, **Add to Practice** (or create a Practice from this intent), and—only when a fair comparison exists—**Compare**. Do not make comparison or a score the obligatory result screen.
- Transcription unavailable: show audio and acoustic analysis, an honest notice, and a retry/setup route. Do not fabricate word timing or pitch.
- Listening is the default path through the result. Where a measured event has a trustworthy timestamp, a concise **Review moment** may link directly into the audio; no auto-generated grade, diagnosis, or unverified “coaching insight.” Ship this as a separate, evaluated iteration if the initial recording-first release cannot support it cleanly.
- Deletion: deleting one recording must not remove another recording or a shared Mimic reference. Confirm destructive operations and define recovery/undo behavior before implementation.

### D. Reusable Practice

- A user may explicitly create a **Prompt/goal Practice** with a title and optional prompt. A title alone can represent a real recurring goal (for example, interview answers); the app should not create a generic “Morning Practice” automatically.
- The Practice view pins the goal/prompt and offers **Record an attempt**, recent attempts, and direct access to each Recording. Retry remains one action. Imported analysis may be attached only by an explicit user action.
- A **Mimic Practice** pins one imported reference excerpt, retains Listen & Repeat and Speak Along, and preserves every attempt. Its reference-versus-attempt playback, comparison reliability limits, and Try Again loop remain intact.
- Changing a Mimic target after attempts exist creates a new Practice or an explicit duplicate; it must not rewrite the meaning of old comparisons.
- The Practices list favors “Continue” and meaningful target names, not counts of empty containers. Existing empty sessions remain accessible as legacy drafts, but are not placed in Home recents by default.
- **Archive Practice** is the safe default removal action: it hides the target from active continuation but retains attempts, reference, and historical comparisons. Deleting a Practice and its files is a separate destructive action that enumerates its reference and attempt count before confirmation. Never silently cascade-delete recordings from a generic “Remove” action.

### E. Library and retrieval

- Default sort: newest saved recording first, across all Practices and standalone work. Show title, created date/time, duration, recorded/imported source, and Practice name where relevant.
- Search titles, source filenames, Practice names, and locally available transcript text. The library must remain useful when transcription is absent. Offer simple source/Practice/date filters; do not require a complex query syntax.
- Selecting a row opens the Recording directly. A Practice link may open its target and attempt history. Provide rename, reveal, export, and delete through native row/context actions.
- Avoid a sidebar and a page that duplicate the same list. Keep recent recordings as a short Home continuation aid, not a second library.
- The library must remain responsive with many takes and dense transcript data; do not decode or lay out every waveform/transcript merely to render the list.

### F. Progress, later and only if defensible

The first release may show factual counts such as **user-recorded takes** and **user-recorded duration**, clearly excluding imported media and references. Do not claim that more minutes equals better speaking. A later Progress view can show a selected Practice over time, with comparable task context, original samples, uncertainty, and the metric definition nearby. Do not average pitch or pause measures across arbitrary imported clips, scripts, durations, and devices and label that “improvement.”

The longer-term roadmap should be driven by whether people actually repeat, listen, and retrieve—not by a desire to fill an Insights screen. After the recording-first foundation, test a listening-led review moment and an optional user-chosen focus within a Practice. Only then consider progress trends for comparable attempts. None of these require a global baseline score.

## 7. Screen-by-screen change map

| Current surface | Replace or evolve to | What must remain |
| --- | --- | --- |
| Studio empty/selected-session screen | Home with immediate Record/Import/Mimic and explicit Continue Practice | Native split view, toolbar, local-only reassurance |
| New Session sheet | Remove for ordinary capture; provide a focused New Practice flow only when requested | Mimic reference import/trim; optional practice goal |
| Session workspace | Practice workspace only for intentional repeatable targets | Mic monitor, attempt history, stable Mimic reference |
| All Sessions | Recordings Library plus a separate Practices list | Search, rename, delete confirmation, access to all old work |
| Take detail | Recording detail, reachable from anywhere | Transcript, charts, transport, inspector, report/export |
| Recents sidebar | Short recent Recordings/Continue Practice section on Home | Direct return to ongoing work |
| Insights | Remove from primary navigation until meaningful Progress is designed | Reliable activity facts and existing analysis data |
| Settings | Keep; move general retention/storage management here | On-device copy, ASR setup, accessibility preferences |

Visual direction: reuse the app's native macOS structure and materials. Keep a dense three-column layout where it helps, but make the center answer “what can I do now?” The primary action should be apparent without reading an inspector. Do not solve the product problem with a new layer of decorative cards or a web-style onboarding wizard.

## 8. Data, privacy, and migration contract

The current library stores `CoachingSession` objects containing `PracticeSession` takes, with audio under session UUID directories. The current code reads schemas 1 and 2 and writes schema 2. This is a **migration constraint, not a reason to keep Sessions in the interface**.

### Required invariants

- Every existing recording ID, creation time, audio URL, analysis result, transcript, prompt, and Mimic reference remains accessible. Do not move audio files in the first UI pass just to make folder names match new language.
- Read old libraries and produce an explicit, versioned, idempotent migration when the new model is ready. Make a verified pre-migration backup before replacing the index; use atomic writes and failure rollback. Test schema 1 and 2, empty/one/many-take sessions, imported media, Mimic, missing files, and interrupted migration.
- Existing generic sessions may appear as legacy Practices or provenance on their recordings. Do not delete zero-take legacy entries automatically. Do not silently merge distinct old sessions with the same name.
- A new Recording may have an optional Practice ID and/or a `retryOf` relationship to another Recording. The latter supports “Record another” without creating an invisible Practice; deleting one side must not orphan an unreadable library item. Preserve original created-at ordering and stable IDs.
- The old `keepsRecordings == false` path deletes prior audio after a new save. A redesigned UI must **not accidentally trigger this destructive behavior**. Before the first new attempt in such a legacy Practice, clearly offer “Keep all from now on” (recommended) or the old replacement behavior with an explicit warning; preserve earlier data until the choice is made.
- New standalone recordings and new Practices keep all valid attempts by default. Storage cleanup is a separate, explicit action with previews and confirmation, not a checkbox before a first recording.
- The exported objective report structure and `ReportFormatter.makeReport` contract stay unchanged in this initiative. Waveforms and dense analysis remain in the app, not the exported JSON. No cloud pipeline or medical/subjective fields are introduced.
- A failed optional transcription is soft. A failed persistence operation must not report success; preserve/reveal recoverable audio and offer retry.

### Suggested implementation boundary

First create a stable `Recording`-oriented application API over the existing storage, then migrate the persisted shape only when read/write and round-trip tests are complete. UI code should request recordings by stable ID, not by `selectedSessionID + selectedTakeID`. Practice membership can be optional. This keeps the user-facing change testable without a risky simultaneous file move.

## 9. Release slices and agent handoff

The following are independently reviewable work packages, **not permission to have several agents edit `AppModel.swift` or `SessionLibrary.swift` concurrently**. Integrate in dependency order; give one owner the shared state and migration contract.

| Slice | Ownership and deliverable | Depends on | Exit gate |
| --- | --- | --- | --- |
| 0. Validate direction | Product/design: low-fidelity native flow specification and 5–8 task-based usability sessions using realistic recorded/imported fixtures; document where users expect recordings versus Practices | This PRD | Confirm or revise nouns, entry points, and retrieval model |
| 1. Recording API and migration | One backend owner: stable recording lookup, optional practice membership, source classification, safe legacy adapter/migration, rollback and fixture tests | Direction decision | V1/V2 round-trip and no lost audio/reference/analysis |
| 2. Home and capture | UI owner: Home, direct Record/Import, recording/progress/error states, commands and navigation; use the new API | Slice 1 interface | No setup sheet or empty artifact on cancel; valid capture opens detail |
| 3. Library and detail | UI owner: flat list/search/filters and direct Recording detail; keep analysis/export; avoid shared shell edits until integration | Slice 1 interface | Standalone and Practice recordings equally findable; keyboard/VoiceOver path |
| 4. Practices and Mimic | UI owner: focused creation/continuation, attempt history, Mimic reference and comparisons; coordinate state changes with backend owner | Slices 1–3 | Existing Mimic flows and attempts preserved; retry one action |
| 5. Integration and release | Integrator: remove stale Session copy/navigation, redefine activity facts, update Settings/README/screenshots/commands, run full verification | All prior slices | Acceptance matrix below passes on real app and migrated fixtures |

Agents should work against a written API contract after Slice 1. New view files can be developed in parallel; changes to shared navigation, `AppModel`, persistence, and deletion must be serialized or assigned to one integrator. Each slice must state which behavior it preserves and which tests prove it.

An agent handoff can be as simple as: “Read `AGENTS.md` and `docs/design/RECORDING_FIRST_PRD.md`. Implement only Slice N. Treat its exit gate and the acceptance matrix as the contract; do not alter recording DSP, report JSON, or user data outside that scope. List changed files, checks, and any unverified live audio/VoiceOver behavior.” The integrator should review each slice against the whole journey, not merely accept passing compilation.

### Main risks and mitigations

| Risk | Mitigation |
| --- | --- |
| A flat library gets noisy as it grows | Fast search, a small number of useful filters, contextual Practice names, and performance fixtures with many recordings |
| Existing users lose their named groupings | Keep legacy Practices/provenance visible; validate retrieval with real migrated fixtures before removing old navigation |
| A UI rewrite accidentally deletes old audio | Isolate persistence ownership, back up and round-trip old schemas, require an explicit choice for replace-only behavior |
| Simpler entry produces an unstructured pile of audio | Editable titles, direct retry links, optional Practices, and a small guided starter without mandatory setup |
| “Progress” confuses activity with improvement | Distinguish recorded from imported sources; defer cross-take claims until tasks and conditions are comparable |
| A polished preview conceals audio or accessibility regressions | Separate visual, keyboard/VoiceOver, storage, microphone, playback, and headphone-route acceptance |

## 10. Acceptance matrix

| Scenario | Required observable result |
| --- | --- |
| Fresh library → Record | One clear action starts permission/recording; no Session/Practice form; a valid stop saves one Recording and opens it |
| Record canceled, too short, or permission denied | No empty library item or Practice; clear next step; no false success toast |
| Import chooser canceled | No session, Practice, recording, or orphan file created |
| Import succeeds | Directly retrievable Recording with correct source, playback, analysis, and editable title; not counted as user-recorded practice time |
| Optional ASR unavailable | Audio and acoustic analysis still save; honest transcript notice; export works within existing contract |
| Record another | New independent Recording, linked as a retry; previous audio remains intact |
| Mimic start → compare → retry → relaunch | Stable reference, all attempts, playback and conservative comparison restored; reference never counted as an attempt |
| Open a legacy library | Every old take and reference accessible; names/prompt and audio preserved; migration repeat is idempotent |
| Legacy replace-only Practice | No prior recording is deleted by an unannounced new-default action |
| Search and navigation | Find a take directly by title/date/source or available transcript; keyboard and VoiceOver identify result and primary action |
| Delete one Recording / archive Practice / delete Practice | One-recording deletion leaves siblings and reference intact; archive retains comparisons; destructive Practice deletion names the full scope; failures do not corrupt the index |
| Inspector hidden / reduced motion/transparency | Core capture, review, retry, and export remain available and legible |

Verification is proportional to modality: `VoiceCoachSelfTest` for core/report invariants; preview generation for layout and migration fixtures; production app build; live macOS keyboard/VoiceOver/navigation checks; and physical microphone, import, playback, headphone/Speak Along, interruption, and relaunch tests. Synthetic preview PNGs do not prove audio behavior.

## 11. How to judge whether it worked

Do not add remote telemetry by default. In moderated or local-only testing, ask participants to complete: first recording, import-and-find, retry, resume Mimic, find a recording from a week ago, and delete the intended item. Record task completion, time and wrong turns, confidence in what is saved, and confusion between Recording and Practice.

**Launch targets to validate, not existing measurements:** Most first-time participants should start a recording without instruction; canceling should create zero artifacts; participants should retrieve a specified recording without first guessing its parent Practice; no participant should misinterpret imported audio as their own practice time; existing users should locate all migrated work. Observe several real use patterns before promoting Progress or adding further organization.

Evidence that would change this direction: repeated-practice users overwhelmingly seek a named target before every recording, or a flat library becomes harder to navigate than a practice-led one at realistic volume. If so, increase the prominence of Practices—not the mandatory setup cost for every capture.

## 12. Out of scope and open review decisions

**Not in this initiative:** cloud sync, accounts, LLM coaching, diagnosis, composite voice scores, automatic “best take,” generic baseline scoring, new acoustic algorithms, a whole-app visual reskin, or cross-task claims of improvement. A/B comparison of arbitrary standalone recordings is a later research question; existing Mimic comparison remains.

**Design review should settle before implementation:** exact naming of “Practice” versus “Exercise”; whether Home shows transcript snippets by default on a shared screen; whether direct Record enters a focused full workspace or a compact capture panel; the explicit keep/replace choice for legacy replace-only sessions; and whether a user-created Practice can be an unprompted recurring goal. These choices should be tested with realistic tasks, not settled by storage terminology.

**Recommendation:** Approve the recording-first model and the no-data-loss migration boundary as the product direction. Validate the navigation and language with a small usability pass, then implement in the slices above. Do not begin by renaming `CoachingSession` across the codebase; that would change the internals before proving the new user journey.

## Appendix: current implementation pointers (not design rationale)

- `Sources/VoiceCoachApp/AppModel.swift`: navigation, selection, capture/import, append, retention, Mimic state.
- `Sources/VoiceCoachApp/SessionLibrary.swift`: current session/take model and v1/v2 persistence, audio paths.
- `Sources/VoiceCoachApp/ContentView.swift`, `DesktopShell.swift`, `VoiceCoachApp.swift`: split-view shell, sidebar, toolbar, commands, session and take surfaces.
- `Sources/VoiceCoachApp/TakeView.swift`, `LibraryViews.swift`, `CreateSessionView.swift`: detail, aggregate Insights, creation form.
- `Sources/VoiceCoachApp/MimicWorkspace.swift`, `MimicComparisonView.swift`, `MimicReferencePicker.swift`: reference-led practice and retry.
- `Sources/VoiceCoachSelfTest/main.swift`, `Sources/VoiceCoachApp/RenderPreviews.swift`: contract and synthetic layout/persistence checks; use the repository's `AGENTS.md` verification rules as well.
