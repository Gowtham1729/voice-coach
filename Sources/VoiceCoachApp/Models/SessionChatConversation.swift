import Combine
import Foundation

@MainActor
final class SessionChatConversation: ObservableObject {
  struct Exchange: Identifiable, Equatable {
    let id: UUID
    let question: String
    let quotedLine: String?
    let answer: String
    let source: SessionChatPassage.Origin?

    init(
      id: UUID = UUID(),
      question: String,
      quotedLine: String? = nil,
      answer: String,
      source: SessionChatPassage.Origin? = nil
    ) {
      self.id = id
      self.question = question
      self.quotedLine = quotedLine
      self.answer = answer
      self.source = source
    }
  }

  let context: SessionChatContext
  @Published var draft = ""
  @Published var selection: SessionChatPassage?
  var focus: String? {
    get { selection?.text }
    set {
      guard let newValue else {
        selection = nil
        return
      }
      selection =
        context.passages.first { $0.origin == .attempt && $0.text == newValue }
        ?? context.passages.first { $0.text == newValue }
        ?? SessionChatPassage(origin: .attempt, index: -1, text: newValue)
    }
  }
  var activePassage: SessionChatPassage? {
    selection ?? context.passages.first { $0.origin == (context.isMimic ? .reference : .attempt) }
      ?? context.passages.first
  }
  @Published private(set) var pendingPassage: SessionChatPassage?
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
      commit(question: question, passage: activePassage, reply: reply)
    case .model(let task):
      submit(task)
    }
  }

  func send(_ task: SessionChatTask) {
    guard canSubmit(task.question) else { return }
    if SessionChatRouter.isCoachingRequest(task.question) {
      commit(question: task.question, passage: activePassage, reply: .voiceBoundary)
    } else {
      submit(task)
    }
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
    let passage = activePassage
    pendingPassage = passage
    let request = SessionChatPromptComposer.make(
      context: context, focus: passage?.text, history: exchanges, task: task,
      source: passage?.origin)
    let responder = responder
    self.task = Task { [weak self] in
      do {
        let reply = try await responder.respond(to: request)
        guard let self, !Task.isCancelled, self.requestID == id else { return }
        self.commit(
          question: question, passage: passage,
          reply: SessionChatRouter.containsCoachingAdvice(reply.answer) ? .voiceBoundary : reply)
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

  private func commit(question: String, passage: SessionChatPassage?, reply: SessionChatReply) {
    exchanges.append(
      Exchange(
        question: question,
        quotedLine: passage?.text,
        answer: reply.answer,
        source: passage?.origin
      )
    )
    exchanges = Array(exchanges.suffix(12))
    if draft.trimmingCharacters(in: .whitespacesAndNewlines) == question { draft = "" }
    errorMessage = nil
  }

  private func finishRequest() {
    pendingQuestion = nil
    pendingPassage = nil
    requestID = nil
    task = nil
  }
}
