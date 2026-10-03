import Foundation
import Testing
import VoiceCoachCore
import VoiceCoachSession

@testable import VoiceCoachApp

@MainActor
struct SessionChatTests {
  private func fixture(text: String = "A thoughtful pause gives an idea room to land.") -> (
    CoachingSession, PracticeSession
  ) {
    let result = AudioAnalyzer().analyze(
      samples: Array(repeating: Float(0), count: 16000), sampleRate: 16000)
    let take = PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/chat-fixture.wav"), result: result,
      transcription: TranscriptionResult(text: text, words: [])
    )
    let session = CoachingSession(
      name: "One recording", mode: .general, prompt: "", keepsRecordings: true, takes: [take])
    return (session, take)
  }

  @Test func contextScopesEachTakeAndSeparatesMimicReference() throws {
    let (session, take) = fixture()
    let ordinary = try #require(SessionChatContext(session: session, take: take))
    var mimic = session
    mimic.mode = .mimic
    let (_, reference) = fixture(text: "Reference phrase")
    mimic.mimicReference = MimicReference(
      sourceName: "Reference", take: reference, sourceStart: 0, sourceEnd: 1)
    let attempt = try #require(SessionChatContext(session: mimic, take: take))
    let referenceOnly = try #require(SessionChatContext(session: mimic, take: nil))
    #expect(ordinary.referenceTranscript == nil)
    #expect(attempt.referenceTranscript == "Reference phrase")
    #expect(attempt.transcript == take.transcription?.text)
    #expect(attempt.scope != referenceOnly.scope)
    #expect(SessionChatContext(session: session, take: nil) == nil)
  }

  @Test func longTranscriptsAndHistoryAreBoundedWithoutInventingMissingWords() throws {
    let (session, take) = fixture(text: String(repeating: "word ", count: 5000) + "SECRET_TAIL")
    let context = try #require(SessionChatContext(session: session, take: take))
    let exchanges = (0..<10).map {
      SessionChatConversation.Exchange(
        question: "question-\($0)", answer: String(repeating: "reply ", count: 300))
    }
    let explain = SessionChatPromptComposer.make(
      context: context, focus: nil, history: exchanges, task: .explain("Explain word")
    ).prompt
    #expect(explain.contains("remainder omitted"))
    #expect(!explain.contains("SECRET_TAIL"))
    #expect(!explain.contains("Earlier:"))
    #expect(!explain.contains("question-9"))
    let prompt = SessionChatPromptComposer.make(
      context: context, focus: nil, history: exchanges, task: .ask("What should I try next?")
    ).prompt
    #expect(!prompt.contains("question-7"))
    #expect(prompt.contains("question-8"))
    #expect(prompt.contains("question-9"))
    #expect(prompt.count < 2500)
    let (emptySession, emptyTake) = fixture(text: " ")
    let empty = try #require(SessionChatContext(session: emptySession, take: emptyTake))
    #expect(!empty.hasTranscript)
    let emptyPrompt = SessionChatPromptComposer.make(
      context: empty, focus: nil, history: [], task: .explain("What does this mean?")
    )
    #expect(emptyPrompt.prompt.contains("No transcript."))
    #expect(!emptyPrompt.instructions.localizedCaseInsensitiveContains("can't hear"))
    #expect(!emptyPrompt.instructions.localizedCaseInsensitiveContains("cannot hear"))
  }

  @Test func chatCachePreservesNavigationAndIsolatesRecordings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(storageRoot: root, loadPersistedData: false)
    let (firstSession, firstTake) = fixture()
    let (secondSession, secondTake) = fixture(text: "Another recording")
    let firstContext = try #require(
      model.sessionChatContext(session: firstSession, take: firstTake))
    let secondContext = try #require(
      model.sessionChatContext(session: secondSession, take: secondTake))
    let first = model.conversation(for: firstContext)
    first.draft = "My private question"
    let second = model.conversation(for: secondContext)
    #expect(first !== second)
    #expect(second.draft.isEmpty)
    #expect(model.conversation(for: firstContext) === first)
    #expect(
      !SessionChatPromptComposer.make(
        context: secondContext, focus: nil, history: second.exchanges, task: .ask("Hello")
      ).prompt.contains("My private question"))
    model.removeSessionChats(sessionID: firstSession.id, takeID: firstTake.id)
    #expect(first.draft.isEmpty)
    #expect(model.sessionChats[firstContext.scope] == nil)
    #expect(model.sessionChats[secondContext.scope] === second)
    model.clearExperimentalChats()
    #expect(model.sessionChats.isEmpty)
  }

  @Test func failedReplyCanBeRetriedAndCancelledReplyCannotReappear() async throws {
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    chat.draft = "Explain pause"
    chat.send()
    try await waitUntil { responder.pending != nil }
    responder.complete(.failure(SessionChatError.unsupportedLanguage))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.isEmpty)
    #expect(chat.draft == "Explain pause")
    #expect(chat.errorMessage?.contains("language") == true)
    chat.send()
    try await waitUntil { responder.pending != nil }
    chat.clear()
    responder.complete(.success(SessionChatReply(answer: "This late answer must be discarded", practiceLine: nil)))
    try await Task.sleep(for: .milliseconds(30))
    #expect(chat.exchanges.isEmpty)
    #expect(chat.draft.isEmpty)
    #expect(chat.errorMessage == nil)
  }

  @Test func followupsUseOnlyCompletedExchangesAndRejectOversizedQuestions() async throws {
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    chat.draft = String(repeating: "x", count: 501)
    chat.send()
    #expect(!chat.isResponding)
    chat.draft = "Explain pause"
    chat.send()
    try await waitUntil { responder.pending != nil }
    responder.complete(.success(SessionChatReply(answer: "A short break in speech.", practiceLine: nil)))
    try await waitUntil { !chat.isResponding }
    chat.draft = "Give me a synonym"
    chat.send()
    try await waitUntil { responder.pending != nil }
    #expect(responder.requests.last?.prompt.contains("A short break in speech.") == false)
    #expect(responder.requests.last?.prompt.contains("Give me a synonym") == true)
    #expect(responder.requests.last?.instructions.contains("more naturally") == true)
    responder.complete(
      .success(SessionChatReply(answer: "\"A brief pause gives an idea room to land.\" Brief replaces thoughtful.", practiceLine: "A brief pause gives an idea room to land.")))
    try await waitUntil { !chat.isResponding }
    chat.draft = "Why does that word fit?"
    chat.send()
    try await waitUntil { responder.requests.count == 3 }
    #expect(responder.requests.last?.prompt.contains("Earlier:") == true)
    #expect(responder.requests.last?.prompt.contains("brief pause") == true)
    chat.cancel()
    responder.complete(.success(SessionChatReply(answer: "break", practiceLine: nil)))
    #expect(chat.exchanges.count == 2)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["VOICE_COACH_TEST_LOCAL_CHAT"] == "1"))
  func liveDeviceModelSmoke() async throws {
    #expect(CoachingWordingGenerator.status == .available)
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = LocalSessionChatResponder()
    let meaning = SessionChatPromptComposer.make(
      context: context, focus: nil, history: [],
      task: .explain("What does pause mean in this sentence?"))
    #expect(!meaning.instructions.localizedCaseInsensitiveContains("can't hear"))
    #expect(!meaning.instructions.localizedCaseInsensitiveContains("cannot hear"))
    let first = try await responder.respond(to: meaning)
    print("Local chat vocabulary response: \(first.answer)")
    #expect(!first.answer.isEmpty)
    #expect(!first.answer.localizedCaseInsensitiveContains("can't hear"))
    #expect(!first.answer.localizedCaseInsensitiveContains("cannot hear"))
    #expect(!first.answer.localizedCaseInsensitiveContains("sorry"))
    let history = [
      SessionChatConversation.Exchange(question: "What does pause mean?", answer: first.answer)
    ]
    let second = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, focus: nil, history: history,
        task: .synonym("Give me a synonym that fits here and explain any difference.")))
    print("Local chat synonym response: \(second.answer) / \(second.practiceLine ?? "")")
    #expect(second.practiceLine?.isEmpty == false)
    #expect(!second.answer.localizedCaseInsensitiveContains("can't hear"))
    let misheard = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, focus: "I want my stake cooked medium rare.", history: [],
        task: .explain("What does stake mean here?")))
    print("Local chat mishearing response: \(misheard.answer)")
    #expect(!misheard.answer.localizedCaseInsensitiveContains("can't hear"))
    #expect(!misheard.answer.localizedCaseInsensitiveContains("sorry"))
    #expect(!misheard.answer.localizedCaseInsensitiveContains("practiceline"))
    let translation = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, focus: nil, history: [],
        task: .translate(language: "French", question: "Translate this into French.")))
    print("Local chat translation response: \(translation.answer) / \(translation.practiceLine ?? "")")
    #expect(!translation.answer.isEmpty)
    let clearer = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, focus: nil, history: [],
        task: .rephrase("Give me a more natural way to say this.")))
    print("Local chat rephrase response: \(clearer.answer) / \(clearer.practiceLine ?? "")")
    #expect(clearer.practiceLine?.isEmpty == false)
  }

  @Test func meaningQuestionsDoNotAskTheModelAboutHearing() async throws {
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    chat.focus = "A thoughtful pause gives an idea room to land."
    chat.draft = "What does pause mean here?"
    chat.send()
    try await waitUntil { !responder.requests.isEmpty }
    let request = try #require(responder.requests.last)
    #expect(request.prompt.contains("A thoughtful pause"))
    #expect(request.prompt.contains("What does pause mean here?"))
    #expect(request.instructions.contains("Define the word"))
    #expect(!request.instructions.localizedCaseInsensitiveContains("can't hear"))
    #expect(!request.instructions.localizedCaseInsensitiveContains("cannot hear"))
    responder.complete(
      .success(
        SessionChatReply(
          answer: "Sorry, I can't hear you. Pause means a brief stop so the idea can settle.",
          practiceLine: nil)))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.answer == "Pause means a brief stop so the idea can settle.")

    chat.draft = "Does my voice sound confident?"
    chat.send()
    #expect(chat.exchanges.count == 2)
    #expect(responder.requests.count == 1)
    #expect(chat.exchanges.last?.answer.contains("words") == true)

    chat.draft = "Translate this."
    chat.send()
    #expect(chat.exchanges.last?.answer.contains("language") == true)
    #expect(responder.requests.count == 1)

    chat.send(.translate(language: "French", question: "Translate this into French."))
    try await waitUntil { responder.requests.count == 2 }
    responder.complete(.success(SessionChatReply(answer: "Une pause réfléchie.", practiceLine: nil)))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.practiceLine == "Une pause réfléchie.")
  }

  @Test func passagesFollowWordSelectionAndTasksStaySeparate() {
    let text = "A thoughtful pause gives an idea room to land. The budget can wait."
    let sentences = SessionChatPassages.sentences(in: text)
    #expect(sentences.count == 2)
    let words = sentences.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
      .enumerated().map { index, word in
        TranscriptWord(word: word, start: Double(index), end: Double(index) + 0.2)
      }
    #expect(
      SessionChatPassages.sentence(containingWordAt: 2, words: words, text: text)?.contains("pause")
        == true)
    #expect(
      SessionChatPassages.sentence(containingWordAt: 9, words: words, text: text)?.contains("budget")
        == true)
    #expect(
      SessionChatAnswerCleaner.clean("Sorry, I can't hear you. Pause means a brief stop.")
        == "Pause means a brief stop.")
    #expect(SessionChatAnswerCleaner.clean("Pause means a brief stop.") == "Pause means a brief stop.")
    #expect(
      SessionChatAnswerCleaner.clean("\"Stake\" means the cut of beef.\n\nPracticeLine: [ ]")
        == "\"Stake\" means the cut of beef.")
    #expect(SessionChatReply(answer: "Steak.", practiceLine: "[ ]").practiceLine == nil)
    #expect(SessionChatRouter.route("What does pause mean here?") == .model(.explain("What does pause mean here?")))
    if case .model(.translate(let language, _)) = SessionChatRouter.route("Translate this into French.") {
      #expect(language == "French")
    } else {
      Issue.record("French translation was not routed to the model")
    }
    #expect(SessionChatRouter.route("Give me a more natural way to say this.") == .model(.rephrase("Give me a more natural way to say this.")))
    let tasks: [SessionChatTask] = [
      .explain("q"), .rephrase("q"), .synonym("q"), .translate(language: "French", question: "q"),
      .practise("q"), .ask("q"),
    ]
    for task in tasks {
      #expect(!task.instructions.localizedCaseInsensitiveContains("can't hear"))
      #expect(!task.instructions.localizedCaseInsensitiveContains("cannot hear"))
    }
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
      guard ContinuousClock.now < deadline else { throw SessionChatError.emptyResponse }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

@MainActor
private final class ControlledChatResponder: SessionChatResponding {
  var requests: [SessionChatRequest] = []
  var pending: CheckedContinuation<SessionChatReply, any Error>?

  func respond(to request: SessionChatRequest) async throws -> SessionChatReply {
    requests.append(request)
    return try await withCheckedThrowingContinuation { pending = $0 }
  }

  func complete(_ result: Result<SessionChatReply, any Error>) {
    let continuation = pending
    pending = nil
    continuation?.resume(with: result)
  }
}
