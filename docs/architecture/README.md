# Voice Coach architecture

Voice Coach uses a small layered package graph so local audio contracts stay reusable and macOS framework code stays at the edge.

```text
VoiceCoachApp ───────▶ VoiceCoachSession ───────▶ VoiceCoachCore
      │                                             ▲
      └─────────────────────────────────────────────┘

VoiceCoachCoreTests ───────────────────────────────▶ VoiceCoachCore
VoiceCoachSessionTests ─▶ VoiceCoachSession + VoiceCoachCore
VoiceCoachSelfTest ────────────────────────────────▶ VoiceCoachCore
```

## Module responsibilities

### VoiceCoachCore

Pure acoustic models and algorithms, report formatting, audio import, and local transcription adapters. It must not depend on SwiftUI, AppKit, app navigation, or session persistence. AVFoundation-dependent paths remain conditionally compiled so the contract runner can build without it.

### VoiceCoachSession

The Sessions → Takes domain and its on-disk repository. It depends on Core models but not on the macOS UI. `SessionStore` owns schema migration, thin-index commits, per-take analysis documents, and pruning. Keep storage-format compatibility tests beside every schema change.

### VoiceCoachApp

The macOS executable. `AppModel` is the SwiftUI-facing façade and is split by capability under `Application/`; it coordinates protocol-backed platform services but does not define acoustic or persistence formats.

The source folders have one purpose each:

- `App/`: scene entry point and commands.
- `Application/`: app state, dependencies, and feature action extensions.
- `Navigation/`: stable split-view shell, destinations, and source-list sidebar.
- `Features/`: Home, Library, Mimic, Take, and Settings UI.
- `Services/`: macOS audio capture/playback and on-device title generation.
- `DesignSystem/`: shared materials, chrome, controls, and presentation helpers.
- `Visualization/`: reusable waveform, chart, spectrogram, and timeline views.
- `Models/`: app-only presentation state.
- `PreviewSupport/`: synthetic fixtures and screenshot rendering.

## Dependency rules

1. Dependencies point inward: App → Session → Core. Core never imports App or Session.
2. Persisted types live in Session; acoustic/export types live in Core; transient selection state lives in App.
3. SwiftUI views call named AppModel actions. They do not write files, invoke transcription processes, or own AVFoundation objects.
4. Platform services enter AppModel through `AppDependencies` protocols. Add a protocol seam when a new external service needs replacement or deterministic tests.
5. Keep one primary responsibility per file. Split a file when unrelated types accumulate or a feature extension stops being scannable.
6. Preserve storage and JSON compatibility intentionally; add a focused regression test before changing either contract.

## Verification

Use the narrowest relevant check while editing, then run the release sequence before delivery:

```sh
./scripts/test.sh
swift run VoiceCoachSelfTest
./scripts/render-previews.sh
./scripts/build-app.sh
```

Synthetic tests do not verify real microphone input, headphones, system-audio capture permissions, or route synchronization. Smoke-test those on physical hardware when audio routing changes.
