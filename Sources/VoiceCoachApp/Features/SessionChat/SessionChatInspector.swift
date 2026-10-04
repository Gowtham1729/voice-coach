import AppKit
import SwiftUI

/// Language exploration scoped to the open take, with explicit transcript context.
struct SessionChatInspector: View {
  @ObservedObject var conversation: SessionChatConversation
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @State private var status = CoachingWordingGenerator.status
  @State private var copiedAnswerID: UUID?
  @State private var translationPassage: SessionChatTranscript?

  private var busy: Bool {
    model.isRecording || model.isAnalyzing || model.isCapturingMimicReference
  }
  private var modelReady: Bool { snapshot || status == .available }
  private var canSend: Bool {
    modelReady && !busy && !conversation.isResponding
      && !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && conversation.draft.count <= SessionChatConversation.questionLimit
  }
  private var activeTranscript: SessionChatTranscript? { conversation.activeTranscript }
  private var sources: [SessionChatTranscript.Origin] {
    [.reference, .attempt].filter { origin in
      conversation.context.sources.contains { $0.origin == origin }
    }
  }
  private var sourceSelection: Binding<SessionChatTranscript.Origin> {
    Binding(
      get: { activeTranscript?.origin ?? .attempt },
      set: { origin in
        conversation.selection = conversation.context.sources.first { $0.origin == origin }
      })
  }

  var body: some View {
    InspectorShell(scrollToken: "\(conversation.exchanges.count)-\(conversation.isResponding)") {
      InspectorHeader(
        eyebrow: "Words · Experimental",
        title: conversation.context.title,
        meta: ["On this Mac · Clears when you quit"]
      ) {
        Button("Clear chat", action: conversation.clear)
          .controlSize(.small)
          .disabled(
            conversation.exchanges.isEmpty && !conversation.isResponding
              && conversation.draft.isEmpty
          )
          .help("Delete all messages in this chat")
      }
    } content: {
      VStack(alignment: .leading, spacing: 20) {
        if conversation.exchanges.isEmpty && !conversation.isResponding {
          VStack(alignment: .leading, spacing: 8) {
            Text("Explore the words").font(.headline)
            Text(
              "Ask about meanings, grammar, synonyms, or translations."
            )
            .foregroundStyle(.secondary)
          }
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(conversation.exchanges) { exchange in
          message(
            question: exchange.question,
            answer: exchange.answer, id: exchange.id)
          Divider()
        }
        if let question = conversation.pendingQuestion {
          message(
            question: question, answer: nil, id: nil)
          ProgressView("Thinking…").controlSize(.small)
        }
        if let error = conversation.errorMessage {
          Text(error).font(.callout).foregroundStyle(.orange)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } footer: {
      footer
    }
    .onAppear { status = CoachingWordingGenerator.status }
    .sheet(item: $translationPassage) { passage in
      SessionChatTranslationSheet(text: passage.text)
    }
  }

  private func message(
    question: String,
    answer: String?, id: UUID?
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("You").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Text(question).font(.callout).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if let answer, let id {
        HStack {
          Text("Assistant").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Spacer()
          if snapshot {
            Text("Copy").font(.caption).foregroundStyle(Studio.accent)
          } else {
            Button(copiedAnswerID == id ? "Copied" : "Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(answer, forType: .string)
              copiedAnswerID = id
            }
            .buttonStyle(.borderless).controlSize(.small)
            .accessibilityLabel("Copy answer").help("Copy the complete answer")
          }
        }.padding(.top, 8)
        // Inline Markdown styling keeps emphasis readable. Render lines individually
        // so mappings, lists, and paragraph breaks survive the attributed-string parser.
        VStack(alignment: .leading, spacing: 3) {
          ForEach(Array(answer.components(separatedBy: .newlines).enumerated()), id: \.offset) {
            _, line in
            if line.isEmpty {
              Color.clear.frame(height: 5)
            } else {
              Text(
                (try? AttributedString(
                  markdown: line,
                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                  ?? AttributedString(line)
              )
              .font(.callout).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !modelReady {
        HStack {
          Text(status.settingsLabel).font(.callout).foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Button("Check again") { status = CoachingWordingGenerator.status }.controlSize(.small)
        }
      }
      if conversation.context.hasTranscript { contextPicker }
      composer
      if conversation.draft.count > SessionChatConversation.questionLimit {
        Text("Use \(SessionChatConversation.questionLimit) characters or fewer.")
          .font(.caption).foregroundStyle(.orange)
      } else {
        Text("AI can be wrong. It can’t hear or evaluate your audio.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var contextPicker: some View {
    HStack {
      if sources.count > 1 {
        if snapshot {
          HStack(spacing: 4) {
            Text(sourceName(activeTranscript?.origin ?? .attempt))
            Image(systemName: "chevron.down").font(.caption2)
          }.font(.caption).foregroundStyle(.secondary)
        } else {
          Picker("Context", selection: sourceSelection) {
            ForEach(sources, id: \.self) { origin in Text(sourceName(origin)).tag(origin) }
          }
          .pickerStyle(.menu).labelsHidden().controlSize(.small)
          .fixedSize().accessibilityLabel("Transcript source")
        }
      } else {
        Text(sourceName(activeTranscript?.origin ?? .attempt))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if snapshot {
        Text("Translate…").font(.caption).foregroundStyle(Studio.accent)
      } else {
        Button("Translate…") { translationPassage = activeTranscript }
          .buttonStyle(.borderless).controlSize(.small)
          .help("Translate the complete transcript with macOS")
          .accessibilityLabel("Translate with macOS")
      }
    }
    .disabled(conversation.isResponding || busy)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Menu("Suggested questions") {
        Button("Explain the meaning") { conversation.draft = "What does this transcript mean?" }
        Button("Word-by-word meanings") {
          conversation.draft =
            "Explain each word or meaningful phrase in English. Use one mapping per line: source = meaning."
        }
        Button("Synonyms in context") {
          conversation.draft = SessionChatTask.synonymSuggestion
        }
        Menu("Translate into") {
          ForEach(SessionChatTask.menuLanguages, id: \.self) { language in
            Button(language) { conversation.draft = "Translate this into \(language)." }
          }
        }
      }
      .controlSize(.small).disabled(!modelReady || conversation.isResponding || busy)
      HStack(alignment: .bottom, spacing: 8) {
        if snapshot {
          Text("Ask about this transcript…").font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        } else {
          TextField("Ask about this transcript…", text: $conversation.draft, axis: .vertical)
            .lineLimit(1...5).textFieldStyle(.roundedBorder)
            .accessibilityLabel("Language question")
            .onSubmit { if canSend { conversation.send() } }
            .disabled(!modelReady || conversation.isResponding || busy)
        }
        Button {
          if conversation.isResponding { conversation.cancel() } else { conversation.send() }
        } label: {
          Image(systemName: conversation.isResponding ? "stop.fill" : "arrow.up")
        }
        .buttonStyle(.borderedProminent).controlSize(.regular)
        .disabled(!conversation.isResponding && !canSend)
        .accessibilityLabel(conversation.isResponding ? "Stop response" : "Send question")
        .help(conversation.isResponding ? "Stop response" : "Send question (Return)")
      }
    }
  }

  private func sourceName(_ origin: SessionChatTranscript.Origin) -> String {
    origin == .reference ? "Reference" : (conversation.context.isMimic ? "This take" : "Recording")
  }
}
