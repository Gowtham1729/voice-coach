import AppKit
import SwiftUI

/// Language exploration scoped to the open take, with explicit transcript context.
struct SessionChatInspector: View {
  @ObservedObject var conversation: SessionChatConversation
  @EnvironmentObject private var model: AppModel
  @Environment(\.studioSnapshot) private var snapshot
  @State private var status = CoachingWordingGenerator.status
  @State private var copiedAnswerID: UUID?
  @State private var choosingSentence = false
  @State private var showingContext = false
  @State private var translationPassage: SessionChatPassage?

  private var busy: Bool {
    model.isRecording || model.isAnalyzing || model.isCapturingMimicReference
  }
  private var modelReady: Bool { snapshot || status == .available }
  private var canSend: Bool {
    modelReady && !busy && !conversation.isResponding
      && !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && conversation.draft.count <= SessionChatConversation.questionLimit
  }
  private var activePassage: SessionChatPassage? { conversation.activePassage }
  private var sources: [SessionChatPassage.Origin] {
    [.reference, .attempt].filter { origin in
      conversation.context.passages.contains { $0.origin == origin }
    }
  }
  private var sourcePassages: [SessionChatPassage] {
    conversation.context.passages.filter { $0.origin == activePassage?.origin }
  }
  private var sourceSelection: Binding<SessionChatPassage.Origin> {
    Binding(
      get: { activePassage?.origin ?? .attempt },
      set: { origin in
        conversation.selection = conversation.context.passages.first { $0.origin == origin }
      })
  }

  var body: some View {
    InspectorShell(scrollToken: "\(conversation.exchanges.count)-\(conversation.isResponding)") {
      InspectorHeader(
        eyebrow: "Language chat · Experimental",
        title: conversation.context.title,
        meta: ["On this Mac · Temporary conversation"]
      ) {
        Button("Clear", action: conversation.clear)
          .controlSize(.small)
          .disabled(
            conversation.exchanges.isEmpty && !conversation.isResponding
              && conversation.draft.isEmpty
          )
          .help("Clear this take's conversation")
      }
    } content: {
      VStack(alignment: .leading, spacing: 20) {
        if conversation.exchanges.isEmpty && !conversation.isResponding {
          VStack(alignment: .leading, spacing: 8) {
            Text("Explore the words").font(.headline)
            Text(
              "Ask about meanings, translations, grammar, or synonyms. Follow up in your own words."
            )
            .foregroundStyle(.secondary)
            Text("For example: “Break this into phrases and explain each one.”")
              .foregroundStyle(.secondary)
          }
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(conversation.exchanges) { exchange in
          message(
            question: exchange.question, quotedLine: exchange.quotedLine, source: exchange.source,
            answer: exchange.answer, id: exchange.id)
          Divider()
        }
        if let question = conversation.pendingQuestion {
          message(
            question: question, quotedLine: conversation.pendingPassage?.text,
            source: conversation.pendingPassage?.origin, answer: nil, id: nil)
          ProgressView("Thinking on this Mac…").controlSize(.small)
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
    question: String, quotedLine: String?, source: SessionChatPassage.Origin?,
    answer: String?, id: UUID?
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("You").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Text(question).font(.callout).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if let quotedLine {
        DisclosureGroup("\(sourceName(source ?? .attempt)) · Text used") {
          Text(quotedLine).font(.caption).foregroundStyle(.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption).foregroundStyle(.secondary)
      }
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
        Text("Keep questions under \(SessionChatConversation.questionLimit) characters.")
          .font(.caption).foregroundStyle(.orange)
      } else {
        Text("AI answers can be wrong. Language help only; no take evaluation.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var contextPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      if sources.count > 1 {
        if snapshot {
          HStack(spacing: 0) {
            ForEach(sources, id: \.self) { origin in
              Text(sourceName(origin))
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(
                  activePassage?.origin == origin ? Studio.accent.opacity(0.18) : Color.clear)
            }
          }.background(Studio.surface, in: RoundedRectangle(cornerRadius: 6))
        } else {
          Picker("Source", selection: sourceSelection) {
            ForEach(sources, id: \.self) { origin in Text(sourceName(origin)).tag(origin) }
          }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Transcript source")
        }
      } else {
        Text(sourceName(activePassage?.origin ?? .attempt))
          .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      }
      HStack {
        Text(
          activePassage.map {
            $0.index < 0 ? "Selected text" : "Sentence \($0.index + 1) of \(sourcePassages.count)"
          }
            ?? "Selected text"
        )
        .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Translate…") {
          translationPassage = activePassage
        }
        .controlSize(.small).help("Translate the selected text with macOS")
        .accessibilityLabel("Translate with macOS")
        if sourcePassages.count > 1 {
          Button("Choose…") { choosingSentence = true }
            .controlSize(.small).accessibilityLabel("Choose transcript sentence")
            .popover(isPresented: $choosingSentence) { sentenceList }
        }
      }
      if let passage = activePassage {
        DisclosureGroup(isExpanded: $showingContext) {
          ScrollView {
            Text(passage.text).font(.callout).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }.frame(maxHeight: 140)
        } label: {
          Text(passage.text).font(.callout).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help("Show the full text sent with your question")
      }
    }
    .disabled(conversation.isResponding || busy)
  }

  private var sentenceList: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(sourceName(activePassage?.origin ?? .attempt)) sentences")
        .font(.headline).padding(12)
      Divider()
      List(
        selection: Binding<String?>(
          get: { activePassage?.id },
          set: { id in
            if let passage = sourcePassages.first(where: { $0.id == id }) {
              conversation.selection = passage
              choosingSentence = false
            }
          }
        )
      ) {
        ForEach(sourcePassages) { passage in
          HStack(alignment: .top, spacing: 8) {
            Text("\(passage.index + 1)").font(.caption.monospacedDigit()).foregroundStyle(
              .secondary)
            Text(passage.text).font(.callout).multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
          }.padding(.vertical, 4).tag(passage.id)
        }
      }.listStyle(.inset)
    }.frame(width: 360, height: 360)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Menu("Suggested questions") {
        Button("Explain the meaning") { conversation.draft = "What does this sentence mean?" }
        Button("Word-by-word meanings") {
          conversation.draft =
            "Explain each word or meaningful phrase in English. Use one mapping per line: source = meaning."
        }
        Button("Synonyms in context") {
          conversation.draft =
            "Which words in this sentence have useful synonyms? Explain the differences in meaning."
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
          Text("Ask about these words…").font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        } else {
          TextField("Ask about these words…", text: $conversation.draft, axis: .vertical)
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

  private func sourceName(_ origin: SessionChatPassage.Origin) -> String {
    origin == .reference ? "Reference" : (conversation.context.isMimic ? "This take" : "Recording")
  }
}
