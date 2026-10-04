import Combine
import Foundation

@MainActor
final class SessionChatConversation: ObservableObject {
  struct Exchange: Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    let source: SessionChatTranscript.Origin?

    init(
      id: UUID = UUID(),
      question: String,
      answer: String,
      source: SessionChatTranscript.Origin? = nil
    ) {
      self.id = id
      self.question = question
      self.answer = answer
      self.source = source
    }
  }

  let context: SessionChatContext
  @Published var draft = ""
  @Published var selection: SessionChatTranscript?
  var activeTranscript: SessionChatTranscript? {
    selection ?? context.defaultTranscript
  }
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
      commit(question: question, passage: activeTranscript, reply: reply)
    case .model(let task):
      submit(task)
    }
  }

  func send(_ task: SessionChatTask) {
    guard canSubmit(task.question) else { return }
    if SessionChatRouter.isCoachingRequest(task.question) {
      commit(question: task.question, passage: activeTranscript, reply: .voiceBoundary)
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
    let passage = activeTranscript
    let request = SessionChatPromptComposer.make(
      context: context, transcript: passage?.text, history: exchanges, task: task,
      source: passage?.origin)
    let responder = responder
    self.task = Task { [weak self] in
      do {
        let reply = try await responder.respond(to: request)
        guard let self, !Task.isCancelled, self.requestID == id else { return }
        guard !reply.hasUnsupportedLanguageRefusal else {
          throw SessionChatError.unhelpfulResponse
        }
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

  private func commit(question: String, passage: SessionChatTranscript?, reply: SessionChatReply) {
    exchanges.append(
      Exchange(
        question: question,
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
    requestID = nil
    task = nil
  }
}
