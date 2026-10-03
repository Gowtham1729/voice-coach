import Combine
import Foundation

@MainActor
final class SessionChatConversation: ObservableObject {
  struct Exchange: Identifiable, Equatable {
    let id: UUID
    let question: String
    let quotedLine: String?
    let answer: String
    let practiceLine: String?

    init(
      id: UUID = UUID(),
      question: String,
      quotedLine: String? = nil,
      answer: String,
      practiceLine: String? = nil
    ) {
      self.id = id
      self.question = question
      self.quotedLine = quotedLine
      self.answer = answer
      self.practiceLine = practiceLine
    }
  }

  let context: SessionChatContext
  @Published var draft = ""
  @Published var focus: String?
  @Published private(set) var exchanges: [Exchange] = []
  @Published private(set) var pendingQuestion: String?
  @Published private(set) var errorMessage: String?
  private var task: Task<Void, Never>?
  private var requestID: UUID?
  private let responder: any SessionChatResponding

  var isResponding: Bool { pendingQuestion != nil }
  static let questionLimit = 500

  init(
    context: SessionChatContext, responder: any SessionChatResponding = LocalSessionChatResponder()
  ) {
    self.context = context
    self.responder = responder
  }

  func send() {
    let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSubmit(question) else { return }
    switch SessionChatRouter.route(question) {
    case .local(let reply):
      commit(question: question, reply: reply)
    case .model(let task):
      submit(task)
    }
  }

  func send(_ task: SessionChatTask) {
    guard canSubmit(task.question) else { return }
    submit(task)
  }

  func cancel() {
    if let pendingQuestion { draft = pendingQuestion }
    task?.cancel()
    finishRequest()
  }

  func clear() {
    cancel()
    draft = ""
    exchanges = []
    errorMessage = nil
  }

  #if DEBUG
    func replaceForPreview(exchanges: [Exchange]) {
      self.exchanges = exchanges
    }
  #endif

  private func canSubmit(_ question: String) -> Bool {
    !isResponding && !question.isEmpty && question.count <= Self.questionLimit
  }

  private func submit(_ task: SessionChatTask) {
    let question = task.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = UUID()
    requestID = id
    pendingQuestion = question
    errorMessage = nil
    if draft.trimmingCharacters(in: .whitespacesAndNewlines) == question { draft = "" }
    let request = SessionChatPromptComposer.make(
      context: context, focus: focus, history: exchanges, task: task)
    taskRun(id: id, question: question) {
      let reply = try await self.responder.respond(to: request)
      return self.speakableLine(in: reply, for: task)
    }
  }

  /// Rewrites and translations are there to be said. If the model leaves the
  /// practice line empty, use its first sentence so the inspector can offer Copy.
  private func speakableLine(in reply: SessionChatReply, for task: SessionChatTask) -> SessionChatReply {
    if reply.practiceLine != nil { return reply }
    switch task {
    case .explain, .practise, .ask:
      return reply
    case .translate, .rephrase, .synonym:
      let line = SessionChatAnswerCleaner.stripQuotes(
        SessionChatAnswerCleaner.firstSentence(reply.answer))
      guard line.count > 1, line.count < 180 else { return reply }
      return SessionChatReply(answer: reply.answer, practiceLine: line)
    }
  }

  private func taskRun(
    id: UUID, question: String, operation: @escaping @MainActor () async throws -> SessionChatReply
  ) {
    task = Task { [weak self] in
      do {
        let reply = try await operation()
        guard let self, !Task.isCancelled, self.requestID == id else { return }
        self.commit(question: question, reply: reply)
        self.finishRequest()
      } catch {
        guard let self, !Task.isCancelled, self.requestID == id else { return }
        self.errorMessage =
          (error as? SessionChatError)?.errorDescription
          ?? "The local model could not finish. Try again."
        if self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.draft = question
        }
        self.finishRequest()
      }
    }
  }

  private func commit(question: String, reply: SessionChatReply) {
    let quoted = focus ?? context.fallbackQuote
    exchanges.append(
      Exchange(
        question: question,
        quotedLine: quoted == SessionChatContext.missingTranscript ? nil : quoted,
        answer: reply.answer,
        practiceLine: reply.practiceLine
      )
    )
    exchanges = Array(exchanges.suffix(12))
    if draft.trimmingCharacters(in: .whitespacesAndNewlines) == question { draft = "" }
    errorMessage = nil
  }

  private func finishRequest() {
    pendingQuestion = nil
    requestID = nil
    task = nil
  }
}
