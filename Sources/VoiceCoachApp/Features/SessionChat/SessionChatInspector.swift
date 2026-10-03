import AppKit
import SwiftUI

/// Trailing-inspector chat for the recording or Mimic that is already open.
/// The main column stays on the transcript and charts.
struct SessionChatInspector: View {
  @ObservedObject var conversation: SessionChatConversation
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @State private var status = CoachingWordingGenerator.status
  @State private var copiedLineID: UUID?

  private var busy: Bool {
    model.isRecording || model.isAnalyzing || model.isCapturingMimicReference
  }

  private var modelReady: Bool { snapshot || status == .available }

  private var canSend: Bool {
    modelReady && !busy && !conversation.isResponding
      && !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && conversation.draft.count <= SessionChatConversation.questionLimit
  }

  private var passages: [SessionChatPassage] { conversation.context.passages }

  private var activePassage: SessionChatPassage? {
    if let focus = conversation.focus, let match = passages.first(where: { $0.text == focus }) {
      return match
    }
    return passages.first { $0.origin == .attempt } ?? passages.first
  }

  var body: some View {
    InspectorShell(scrollToken: conversation.exchanges.count + (conversation.isResponding ? 1 : 0)) {
      InspectorHeader(
        eyebrow: "On this Mac",
        title: conversation.context.title,
        meta: ["Temporary · this \(conversation.context.isMimic ? "Mimic" : "recording") only"]
      ) {
        Button("Clear", action: conversation.clear)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(
            conversation.exchanges.isEmpty && !conversation.isResponding && conversation.draft.isEmpty
          )
      }
    } content: {
      VStack(alignment: .leading, spacing: 14) {
        if conversation.exchanges.isEmpty && !conversation.isResponding {
          Text("Ask what a word means, then try a clearer way to say the line.")
            .font(.callout)
            .foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(conversation.exchanges) { exchange in
          message(
            question: exchange.question,
            quotedLine: exchange.quotedLine,
            answer: exchange.answer,
            practiceLine: exchange.practiceLine,
            id: exchange.id
          )
        }
        if let question = conversation.pendingQuestion {
          message(question: question, quotedLine: activeQuote, answer: nil, practiceLine: nil, id: nil)
          ProgressView("Thinking on this Mac…")
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = conversation.errorMessage {
          Text(error)
            .font(.callout)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } footer: {
      footer
    }
    .onAppear { status = CoachingWordingGenerator.status }
  }

  private func message(
    question: String,
    quotedLine: String?,
    answer: String?,
    practiceLine: String?,
    id: UUID?
  ) -> some View {
    let reply = answer.map { SessionChatReply(answer: $0, practiceLine: practiceLine) }
    let showAnswer = reply.map { !$0.answer.isEmpty && !$0.answerRepeatsPracticeLine } ?? false
    return VStack(alignment: .leading, spacing: 6) {
      Text("You")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Studio.secondary)
      Text(question)
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if let quotedLine {
        Text("“\(quotedLine)”")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
          .lineLimit(3)
          .textSelection(.enabled)
      }
      if showAnswer, let answer {
        Text(answer)
          .font(.callout)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }
      if let practiceLine, let id {
        practiceCard(practiceLine, id: id)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func practiceCard(_ line: String, id: UUID) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        SectionEyebrow(text: "Say this")
        Spacer()
        Button(copiedLineID == id ? "Copied" : "Copy") {
          copy(line, id: id)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help("Copy line")
        .accessibilityLabel("Copy line")
      }
      Text(line)
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .background(Studio.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var activeQuote: String? {
    let quote = conversation.focus ?? conversation.context.fallbackQuote
    return quote == SessionChatContext.missingTranscript ? nil : quote
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !modelReady {
        HStack {
          Text(status.settingsLabel)
            .font(.callout)
            .foregroundStyle(Studio.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          Button("Check again") { status = CoachingWordingGenerator.status }
            .controlSize(.small)
        }
      } else if conversation.context.hasTranscript {
        linePicker
        actions
        composer
      } else {
        Text("No transcript yet. Type a sentence with your question.")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
        composer
      }
      if conversation.draft.count > SessionChatConversation.questionLimit {
        Text("Keep questions under \(SessionChatConversation.questionLimit) characters.")
          .font(.caption)
          .foregroundStyle(.orange)
      } else {
        Text("Check a line before you practise it.")
          .font(.caption)
          .foregroundStyle(Studio.secondary)
      }
    }
  }

  @ViewBuilder
  private var linePicker: some View {
    if passages.count > 1 && !snapshot {
      Menu {
        passageButtons(passages.filter { $0.origin == .attempt }, title: "This take")
        passageButtons(passages.filter { $0.origin == .reference }, title: "Reference")
      } label: {
        lineLabel
      }
      .menuStyle(.borderlessButton)
      .accessibilityLabel("Line to ask about")
    } else if let passage = activePassage ?? passages.first {
      Text(passage.menuTitle)
        .font(.callout)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    if conversation.context.usesTranscriptExcerpt {
      Text("Long transcript. Pick the line you mean, or paste it into the question.")
        .font(.caption)
        .foregroundStyle(Studio.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var lineLabel: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(activePassage?.menuTitle ?? "Choose a line")
        .font(.callout)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      Spacer(minLength: 4)
      Image(systemName: "chevron.up.chevron.down")
        .font(.caption2)
        .foregroundStyle(Studio.secondary)
    }
  }

  @ViewBuilder
  private func passageButtons(_ passages: [SessionChatPassage], title: String) -> some View {
    if !passages.isEmpty {
      Section(title) {
        ForEach(menuPassages(passages)) { passage in
          Button {
            conversation.focus = passage.text
          } label: {
            if passage.text == activePassage?.text {
              Label(passage.menuTitle, systemImage: "checkmark")
            } else {
              Text(passage.menuTitle)
            }
          }
        }
      }
    }
  }

  private func menuPassages(_ passages: [SessionChatPassage]) -> [SessionChatPassage] {
    var shown = Array(passages.prefix(8))
    if let active = activePassage, active.origin == passages.first?.origin, !shown.contains(active) {
      shown.append(active)
    }
    return shown
  }

  private var actions: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        taskButton("Explain") { conversation.send(.explain("What does this line mean?")) }
        taskButton("Clearer line") {
          conversation.send(.rephrase("Give me a more natural way to say this."))
        }
      }
      HStack(spacing: 6) {
        translateMenu
        taskButton("Practise") {
          conversation.send(.practise("How should I practise this line?"))
        }
      }
    }
    .disabled(conversation.isResponding || busy)
  }

  private func taskButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }

  private var translateMenu: some View {
    Menu {
      ForEach(SessionChatTask.menuLanguages, id: \.self) { language in
        Button(language) {
          conversation.send(
            .translate(language: language, question: "Translate this into \(language)."))
        }
      }
    } label: {
      Text("Translate")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .frame(maxWidth: .infinity)
    .disabled(conversation.isResponding || busy)
    .accessibilityLabel("Translate this line")
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 8) {
      composerField
      Button(action: sendOrStop) {
        Image(systemName: conversation.isResponding ? "stop.fill" : "arrow.up")
      }
      .studioGlassButton(prominent: !conversation.isResponding)
      .disabled(!conversation.isResponding && !canSend)
      .accessibilityLabel(conversation.isResponding ? "Stop" : "Send")
      .help(conversation.isResponding ? "Stop" : "Send")
    }
  }

  @ViewBuilder
  private var composerField: some View {
    if snapshot {
      Text(conversation.draft.isEmpty ? "Ask about this line…" : conversation.draft)
        .font(.callout)
        .foregroundStyle(Studio.secondary)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    } else {
      TextField("Ask about this line…", text: $conversation.draft, axis: .vertical)
        .lineLimit(1...3)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Question about this line")
        .onSubmit { if canSend { conversation.send() } }
        .disabled(conversation.isResponding || busy)
    }
  }

  private func sendOrStop() {
    if conversation.isResponding {
      conversation.cancel()
    } else {
      conversation.send()
    }
  }

  private func copy(_ line: String, id: UUID) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(line, forType: .string)
    copiedLineID = id
    model.toastMessage = "Line copied"
  }
}
