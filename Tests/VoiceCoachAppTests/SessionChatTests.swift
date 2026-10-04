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

  @Test func completeTranscriptsArePreservedAndOnlyHistoryIsShortened() throws {
    let (session, take) = fixture(text: String(repeating: "word ", count: 5000) + "SECRET_TAIL")
    let context = try #require(SessionChatContext(session: session, take: take))
    let exchanges = (0..<10).map {
      SessionChatConversation.Exchange(
        question: "question-\($0)", answer: String(repeating: "reply ", count: 300))
    }
    let explain = SessionChatPromptComposer.make(
      context: context, transcript: nil, history: exchanges, task: .explain("Explain word")
    ).prompt
    #expect(explain.contains("SECRET_TAIL"))
    #expect(!explain.contains("remainder omitted"))
    #expect(explain.contains("Earlier:"))
    #expect(explain.contains("question-9"))
    let prompt = SessionChatPromptComposer.make(
      context: context, transcript: nil, history: exchanges, task: .ask("Why does that word fit?")
    ).prompt
    #expect(!prompt.contains("question-6"))
    #expect(prompt.contains("question-8"))
    #expect(prompt.contains("question-9"))
    #expect(prompt.count < (context.transcript?.count ?? 0) + 4500)
    let (emptySession, emptyTake) = fixture(text: " ")
    let empty = try #require(SessionChatContext(session: emptySession, take: emptyTake))
    #expect(!empty.hasTranscript)
    let emptyPrompt = SessionChatPromptComposer.make(
      context: empty, transcript: nil, history: [], task: .explain("What does this mean?")
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
        context: secondContext, transcript: nil, history: second.exchanges, task: .ask("Hello")
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
    responder.complete(.success(SessionChatReply(answer: "This late answer must be discarded")))
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
    responder.complete(.success(SessionChatReply(answer: "A short break in speech.")))
    try await waitUntil { !chat.isResponding }
    chat.draft = "Give me a synonym"
    chat.send()
    try await waitUntil { responder.pending != nil }
    #expect(responder.requests.last?.prompt.contains("A short break in speech.") == true)
    #expect(responder.requests.last?.prompt.contains("Give me a synonym") == true)
    #expect(responder.requests.last?.instructions.contains("follow-ups") == true)
    responder.complete(
      .success(
        SessionChatReply(
          answer: "\"A brief pause gives an idea room to land.\" Brief replaces thoughtful.")))
    try await waitUntil { !chat.isResponding }
    chat.draft = "Why does that word fit?"
    chat.send()
    try await waitUntil { responder.requests.count == 3 }
    #expect(responder.requests.last?.prompt.contains("Earlier:") == true)
    #expect(responder.requests.last?.prompt.contains("brief pause") == true)
    chat.cancel()
    responder.complete(.success(SessionChatReply(answer: "break")))
    #expect(chat.exchanges.count == 2)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["VOICE_COACH_TEST_LOCAL_CHAT"] == "1"))
  func liveDeviceModelSmoke() async throws {
    #expect(CoachingWordingGenerator.status == .available)
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = LocalSessionChatResponder()
    let meaning = SessionChatPromptComposer.make(
      context: context, transcript: nil, history: [],
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
        context: context, transcript: nil, history: history,
        task: .synonym("Give me a synonym that fits here and explain any difference.")))
    print("Local chat synonym response: \(second.answer)")
    #expect(!second.answer.isEmpty)
    #expect(!second.answer.localizedCaseInsensitiveContains("can't hear"))
    let misheard = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, transcript: "I want my stake cooked medium rare.", history: [],
        task: .explain("What does stake mean here?")))
    print("Local chat mishearing response: \(misheard.answer)")
    #expect(!misheard.answer.localizedCaseInsensitiveContains("can't hear"))
    #expect(!misheard.answer.localizedCaseInsensitiveContains("sorry"))
    #expect(!misheard.answer.localizedCaseInsensitiveContains("practiceline"))
    let translation = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, transcript: nil, history: [],
        task: .translate(language: "French", question: "Translate this into French.")))
    print("Local chat translation response: \(translation.answer)")
    #expect(!translation.answer.isEmpty)
    let wordMeanings = try await responder.respond(
      to: SessionChatPromptComposer.make(
        context: context, transcript: "Nous sommes de retour à Paris.", history: [],
        task: .ask(
          "Translate each word or phrase into English. One mapping per line: nous sommes = we are.")
      ))
    print("Local chat word mappings: \(wordMeanings.answer)")
    #expect(wordMeanings.answer.contains("="))
    #expect(wordMeanings.answer.components(separatedBy: .newlines).count > 1)

  }

  @Test func meaningQuestionsDoNotAskTheModelAboutHearing() async throws {
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    chat.draft = "What does pause mean here?"
    chat.send()
    try await waitUntil { !responder.requests.isEmpty }
    let request = try #require(responder.requests.last)
    #expect(request.prompt.contains("A thoughtful pause"))
    #expect(request.prompt.contains("What does pause mean here?"))
    #expect(request.instructions.contains("meanings, vocabulary, synonyms"))
    #expect(!request.instructions.localizedCaseInsensitiveContains("can't hear"))
    #expect(!request.instructions.localizedCaseInsensitiveContains("cannot hear"))
    responder.complete(
      .success(
        SessionChatReply(
          answer: "Sorry, I can't hear you. Pause means a brief stop so the idea can settle.")))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.answer == "Pause means a brief stop so the idea can settle.")

    chat.draft = "Does my voice sound confident?"
    chat.send()
    #expect(chat.exchanges.count == 2)
    #expect(responder.requests.count == 1)
    #expect(chat.exchanges.last?.answer == Self.wordsCannotAnswerLine)
    #expect(chat.exchanges.last?.answer.split(whereSeparator: \.isNewline).count == 1)

    chat.send(.translate(language: "French", question: "Translate this into French."))
    try await waitUntil { responder.requests.count == 2 }
    responder.complete(.success(SessionChatReply(answer: "Une pause réfléchie.")))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.answer == "Une pause réfléchie.")

  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["VOICE_COACH_TEST_LOCAL_CHAT"] == "1"))
  func liveSynonymSuggestionWorksWithImperfectTranscripts() async throws {
    let question = SessionChatTask.synonymSuggestion
    let responder = LocalSessionChatResponder()
    let transcripts = [
      "Salut! Nous sommes de retour à Paris et Noah sommes à tout début du mode juin mais il fait un tempest de novembre Gena Sapporque le tempest est compétent de réglé la méthode est déréglé.",
      "I'd really like to know what languages the Nvidia Power K model supports and it's important because we can make it make our app into a language learning app as well.",
    ]
    for text in transcripts {
      let (session, take) = fixture(text: text)
      let context = try #require(SessionChatContext(session: session, take: take))
      let reply = try await responder.respond(
        to: SessionChatPromptComposer.make(
          context: context,
          history: [
            .init(
              question: "Help me build my vocab", answer: "I cannot help with building vocabulary.")
          ],
          task: .synonym(question)))
      print("Suggested synonyms on imperfect transcript: \(reply.answer)")
      #expect(!reply.answer.isEmpty)
      #expect(!reply.answer.lowercased().contains("cannot provide synonyms"))
      #expect(!reply.answer.lowercased().contains("cannot help"))
      #expect(!reply.answer.lowercased().contains("language reference assistant"))
      #expect(!reply.hasUnsupportedLanguageRefusal)
      #expect(reply.answer.components(separatedBy: .newlines).count > 1)
    }
  }

  @Test func unsupportedCapabilityClaimsAreNotAnswersOrFollowupContext() async throws {
    let refusal =
      "I am a language reference assistant. I cannot provide synonyms or explain differences in meaning for words in the transcript."
    #expect(SessionChatReply(answer: refusal).hasUnsupportedLanguageRefusal)
    #expect(
      SessionChatReply(answer: "I cannot help with building vocabulary.")
        .hasUnsupportedLanguageRefusal)
    #expect(
      !SessionChatReply(
        answer: "Clear = easy to understand. Plain is a near synonym, but can also mean unadorned."
      ).hasUnsupportedLanguageRefusal)
    #expect(
      !SessionChatReply(answer: "This phrase is unclear. Which word did you intend?")
        .hasUnsupportedLanguageRefusal)
    #expect(
      !SessionChatReply(answer: "I cannot provide synonyms = I am unable to give equivalent words.")
        .hasUnsupportedLanguageRefusal)
    let (session, take) = fixture()
    let context = try #require(SessionChatContext(session: session, take: take))
    let request = SessionChatPromptComposer.make(
      context: context,
      history: [
        .init(question: "Synonyms?", answer: refusal),
        .init(question: "Meaning?", answer: "Pause means a short break."),
      ],
      task: .ask(SessionChatTask.synonymSuggestion))
    #expect(!request.prompt.contains("cannot provide synonyms"))
    #expect(request.prompt.contains("Pause means a short break."))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    chat.draft = SessionChatTask.synonymSuggestion
    chat.send()
    try await waitUntil { responder.pending != nil }
    responder.complete(.success(SessionChatReply(answer: refusal)))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.isEmpty)
    #expect(chat.draft == SessionChatTask.synonymSuggestion)
    #expect(chat.errorMessage == SessionChatError.unhelpfulResponse.errorDescription)
  }

  @Test func synonymSuggestionKeepsRealDistinctSourceWordsWithoutConstrainingCustomQuestions()
    throws
  {
    let answer = try #require(
      SessionChatSynonymAnswer.make(
        [
          .init(word: "tempête", synonym: "orage", difference: "A weather distinction."),
          .init(word: "réglé", synonym: "organisé", difference: "A fragment inside another word."),
          .init(word: "début", synonym: "Début", difference: "The same word."),
          .init(word: "début", synonym: "commencement", difference: "Both refer to a beginning."),
          .init(word: "début", synonym: "ouverture", difference: "A duplicate source word."),
        ], transcript: "Au début du mois, le temps est déréglé."))
    #expect(answer.answer.contains("commencement"))
    #expect(!answer.answer.contains("tempête"))
    #expect(!answer.answer.contains("organisé"))
    #expect(!answer.answer.contains("ouverture"))
    #expect(
      SessionChatSynonymAnswer.make(
        [
          .init(word: "word", synonym: "word", difference: "No difference.")
        ], transcript: "word") == nil)
    #expect(
      SessionChatRouter.route(SessionChatTask.synonymSuggestion)
        == .model(.synonym(SessionChatTask.synonymSuggestion)))
    let custom = "Give me synonyms in a table with French and English examples."
    #expect(SessionChatRouter.route(custom) == .model(.ask(custom)))
  }

  @Test func allSentencesAndParagraphsReachTheModelTogether() throws {
    let text =
      "Dr. Smith paid 3.50 euros. Then she left.\n\n"
      + String(repeating: "Another sentence. ", count: 80) + "Final sentence."
    let (session, take) = fixture(text: text)
    let context = try #require(SessionChatContext(session: session, take: take))
    #expect(context.sources.count == 1)
    #expect(context.defaultTranscript?.text == text)
    let request = SessionChatPromptComposer.make(
      context: context, history: [], task: .ask("Explain all of this"))
    let encoded = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
    #expect(request.prompt.contains(encoded))
    #expect(request.prompt.contains("Final sentence."))
    #expect(!request.prompt.contains("remainder omitted"))
  }

  @Test func languageFormatsAndAnswerCleaningRemainFlexible() {
    #expect(
      SessionChatAnswerCleaner.clean("Sorry, I can't hear you. Pause means a brief stop.")
        == "Pause means a brief stop.")
    #expect(
      SessionChatAnswerCleaner.clean("Pause means a brief stop.") == "Pause means a brief stop.")
    #expect(
      SessionChatRouter.route("What does pause mean here?")
        == .model(.ask("What does pause mean here?")))
    let task: SessionChatTask = .ask("Translate each word into English, one mapping per line.")
    #expect(task.instructions.contains("source = meaning"))
    #expect(!task.instructions.contains("Stay under 60 words"))
  }

  @Test func wordsCannotAnswerAudioUsesOneLockedLine() {
    #expect(SessionChatReply.voiceBoundary.answer == Self.wordsCannotAnswerLine)
    #expect(Self.wordsCannotAnswerLine.split(whereSeparator: \.isNewline).count == 1)
  }

  @Test func practiceNextChromeAndPlannerCopyStayPut() throws {
    let ordinary = CoachingPlanner.recording(current: plannerMetrics())
    #expect(ordinary.signals.isEmpty)
    #expect(ordinary.notice == nil)

    let clipped = CoachingPlanner.recording(current: plannerMetrics(clippingPercent: 2.5))
    #expect(clipped.signals.isEmpty)
    #expect(clipped.notice == "2.5% of this take's samples clipped.")

    let severeNoise = CoachingPlanner.recording(current: plannerMetrics(snrDB: 3.9))
    #expect(severeNoise.signals.isEmpty)
    #expect(
      severeNoise.notice
        == "Speech was 3.9 dB above the measured noise floor. Pitch and pause estimates may be unreliable."
    )

    let unmeasured = CoachingPlanner.recording(
      current: plannerMetrics(snrDB: .nan, clippingPercent: .nan))
    #expect(unmeasured.signals.isEmpty)
    #expect(
      unmeasured.notice == "This take did not provide a dependable recording-quality measurement.")

    let unreliable = CoachingPlanner.recording(
      current: plannerMetrics(snrDB: 20, clippingPercent: .nan))
    #expect(unreliable.notice == "Pitch and pause estimates may be unreliable at this recording quality.")

    let silent = AudioAnalyzer().analyze(
      samples: Array(repeating: Float(0), count: 1600), sampleRate: 16_000)
    let bare = PracticeSession(
      audioURL: URL(fileURLWithPath: "/tmp/no-words.wav"),
      result: silent,
      transcription: TranscriptionResult(text: "", words: []))
    let unmatched = CoachingPlanner.mimic(reference: bare, attempt: bare)
    #expect(unmatched.signals.isEmpty)
    #expect(unmatched.notice == "Word matching is too limited for a reference comparison.")

    let insights = try repositorySource("Sources/VoiceCoachApp/DesignSystem/TakeInsightsView.swift")
    #expect(insights.contains("SectionEyebrow(text: \"Practice next\")"))
    #expect(insights.contains("\"Metrics and practice next\""))
    let settings = try repositorySource("Sources/VoiceCoachApp/Features/Settings/SettingsView.swift")
    #expect(settings.contains("Text(\"Practice next\")"))
    #expect(
      settings.contains(
        "Reference comparisons include practice targets measured against the reference. Apple Intelligence can rephrase those exercises on this Mac."
      ))
    let planner = try repositorySource("Sources/VoiceCoachCore/Coaching/CoachingPlan.swift")
    for phrase in [
      "Reference comparison is limited by recording quality.",
      "Phrase timing",
      "Match the reference pace across the phrase, using the transition into",
      "Repeat the phrase at the reference pace, then check where the last word lands.",
      "Pitch across the phrase",
      "Follow the reference's pitch movement across the phrase, using",
      "Emphasis across the phrase",
      "Follow the reference's emphasis across the phrase, using",
    ] {
      #expect(planner.contains(phrase))
    }
  }

  @Test func coachingRequestsAreBlockedAcrossTypedAndExplicitPaths() async throws {
    let (session, take) = fixture()
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(
      context: try #require(SessionChatContext(session: session, take: take)), responder: responder)
    for question in [
      "How is my take and what can I improve?", "Give me feedback", "What should I work on?",
      "How can I improve my fluency?", "How should I practise this line?",
      "Does my voice sound confident?", "What does my voice sound like?",
    ] {
      chat.draft = question
      chat.send()
      #expect(chat.exchanges.last?.answer == Self.wordsCannotAnswerLine)
    }
    chat.send(.ask("Rate my take"))
    #expect(responder.requests.isEmpty)
    #expect(!chat.isResponding)
    for question in [
      "What does improve mean?", "Translate the word feedback", "Give me synonyms for pause",
      "I want it like nous sommes = we are", "Explain the grammar of nous sommes",
    ] {
      #expect(SessionChatRouter.route(question) == .model(.ask(question)))
    }
    chat.draft = "What does pause mean?"
    chat.send()
    try await waitUntil { responder.pending != nil }
    responder.complete(
      .success(SessionChatReply(answer: "You should pause more to sound confident.")))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.answer == Self.wordsCannotAnswerLine)
  }

  @Test func sourceIdentityAndSubmittedTextSurviveSelectionChanges() async throws {
    let (session, take) = fixture(text: "Identical sentence.")
    var mimic = session
    mimic.mode = .mimic
    let (_, reference) = fixture(text: "Identical sentence.")
    mimic.mimicReference = MimicReference(
      sourceName: "Reference", take: reference, sourceStart: 0, sourceEnd: 1)
    let context = try #require(SessionChatContext(session: mimic, take: take))
    let responder = ControlledChatResponder()
    let chat = SessionChatConversation(context: context, responder: responder)
    #expect(chat.activeTranscript?.origin == .reference)
    chat.draft = "Explain this sentence"
    chat.send()
    try await waitUntil { responder.pending != nil }
    #expect(responder.requests.last?.prompt.contains("Reference transcript") == true)
    chat.selection = context.sources.first { $0.origin == .attempt }
    #expect(chat.activeTranscript?.origin == .attempt)
    responder.complete(.success(SessionChatReply(answer: "An example of sameness.")))
    try await waitUntil { !chat.isResponding }
    #expect(chat.exchanges.last?.source == .reference)

  }

  @Test func requestedBreakdownsAndFollowupFormatsRemainIntact() throws {
    let (session, take) = fixture(text: "Nous sommes de retour à Paris.")
    let context = try #require(SessionChatContext(session: session, take: take))
    let answer = "**nous sommes** = we are\n**de retour** = back\n\n**à Paris** = in Paris"
    #expect(SessionChatReply(answer: answer).answer == answer)
    let question = "I want it like nous sommes = we are"
    let task = try #require(
      { () -> SessionChatTask? in
        if case .model(let task) = SessionChatRouter.route(question) { return task }
        return nil
      }())
    let request = SessionChatPromptComposer.make(
      context: context, transcript: nil,
      history: [
        .init(question: "Translate each word into English", answer: "We are back in Paris.")
      ], task: task)
    #expect(request.prompt.contains("Translate each word into English"))
    #expect(request.prompt.contains(question))
    #expect(request.instructions.contains("revise the format"))
    #expect(!request.instructions.contains("sentence only"))
    #expect(!request.instructions.contains("two or three"))
  }

  private static let wordsCannotAnswerLine =
    "Words can’t hear the audio. Ask about a word, a phrase, or a translation."

  private func plannerMetrics(
    snrDB: Double = 20,
    clippingPercent: Double = 0
  ) -> VoiceMetrics {
    VoiceMetrics(
      duration: 12,
      activeSpeechDuration: 12,
      sampleRateHz: 16_000,
      noiseFloorDBFS: -55,
      snrDB: snrDB,
      clippingPercent: clippingPercent,
      nonSpeechRatio: 0,
      internalPauseCount: 0,
      internalPauseTotalMs: 0,
      meanInternalPauseMs: 0,
      medianInternalPauseMs: 0,
      longestInternalPauseMs: 0,
      leadingSilenceMs: 0,
      trailingSilenceMs: 0,
      meanLoudnessDBFS: -20,
      loudnessDynamicRangeDB: 6,
      loudnessStandardDeviationDB: 1.5,
      phraseStartDBFS: -19,
      phraseEndDBFS: -21,
      phraseDecayDB: -1,
      medianPitchHz: 160,
      pitchLowHz: 145,
      pitchHighHz: 180,
      pitchVariationHz: 8,
      pitchRangeSemitones: 8,
      pitchStandardDeviationSemitones: 1.2,
      pitchInstabilityPercent: 2,
      hnrDB: 18,
      cppDB: 12
    )
  }

  private func repositorySource(_ relativePath: String) throws -> String {
    let root = relativePath.split(separator: "/").reduce(
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    ) { url, component in
      url.appendingPathComponent(String(component))
    }
    return try String(contentsOf: root, encoding: .utf8)
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
