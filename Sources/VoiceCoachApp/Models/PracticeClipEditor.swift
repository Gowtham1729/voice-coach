import Foundation
import VoiceCoachCore

/// A creation-only choice. Adjusted phrases are transcribed again after trimming.
struct PracticeClipSelection: Equatable {
  let phraseID: Int?
  var start: Double
  var end: Double
}

struct PracticeClipEditor {
  let clips: [SuggestedPracticeClip]
  let duration: Double
  private(set) var selectedIDs: Set<Int> = []
  private(set) var activeID: Int?
  private(set) var usesCustomClip = false
  private var adjusted: [Int: PracticeClipSelection] = [:]
  private var custom: PracticeClipSelection

  init(clips: [SuggestedPracticeClip] = [], duration: Double = 0) {
    self.clips = clips
    self.duration = duration
    custom = PracticeClipSelection(phraseID: nil, start: 0, end: min(duration, 20))
    if let first = clips.first {
      selectedIDs = [first.id]
      activeID = first.id
    } else {
      usesCustomClip = true
    }
  }

  func selection(for clip: SuggestedPracticeClip) -> PracticeClipSelection {
    adjusted[clip.id] ?? PracticeClipSelection(phraseID: clip.id, start: clip.start, end: clip.end)
  }

  var activeClip: SuggestedPracticeClip? { clips.first { $0.id == activeID } }
  var activeSelection: PracticeClipSelection {
    activeClip.map { selection(for: $0) } ?? custom
  }
  var activeIsAdjusted: Bool { activeID.map { adjusted[$0] != nil } ?? false }
  var creationSelections: [PracticeClipSelection] {
    if usesCustomClip { return [custom] }
    return clips.filter { selectedIDs.contains($0.id) }.map { selection(for: $0) }
  }

  mutating func select(_ id: Int) {
    guard clips.contains(where: { $0.id == id }) else { return }
    selectedIDs.insert(id)
    activeID = id
    usesCustomClip = false
  }

  mutating func setSelected(_ id: Int, selected: Bool) {
    if selected { select(id) }
    else {
      selectedIDs.remove(id)
      if activeID == id { activeID = clips.first { selectedIDs.contains($0.id) }?.id }
      usesCustomClip = false
    }
  }

  mutating func chooseCustomClip() {
    let current = activeSelection
    custom = PracticeClipSelection(phraseID: nil, start: current.start, end: current.end)
    selectedIDs = []
    activeID = nil
    usesCustomClip = true
  }

  mutating func setBoundary(_ value: Double, isStart: Bool) {
    guard value.isFinite, duration >= 1 else { return }
    var range = activeSelection
    if isStart { range.start = min(max(0, value), range.end - 1) }
    else { range.end = max(min(duration, value), range.start + 1) }
    if let clip = activeClip {
      selectedIDs.insert(clip.id)
      // Returning a keyboard nudge to its original value must not trigger new recognition.
      if abs(range.start - clip.start) < 1e-9 { range.start = clip.start }
      if abs(range.end - clip.end) < 1e-9 { range.end = clip.end }
      if range.start == clip.start && range.end == clip.end { adjusted[clip.id] = nil }
      else { adjusted[clip.id] = range }
    } else {
      custom = range
      usesCustomClip = true
    }
  }

  mutating func resetActiveClip() {
    if let id = activeID { adjusted[id] = nil }
  }
}
