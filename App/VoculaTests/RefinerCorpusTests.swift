import Foundation
import Synchronization
import Testing
import VoculaKit

@testable import Vocula

extension MLXRefinerTests {
  @Test(
    "invented dictations through the controller: never empty, one line, the transcript on refusal, on time",
    .enabled(if: installed != nil))
  func corpus() async throws {
    let refiner = try Self.refiner()
    _ = try await refiner.refine(
      "Ну вот, значит, это работает, проверка связи", deadline: .seconds(30))
    let recorded = RecordedRefiner(refiner)
    let heard = Heard()
    let pasteboard = Pasteboard()
    let controller = DictationController(
      dependencies: .init(
        audio: OneSecondOfAudio(), detector: OneSegment(), engine: heard, probe: SameField(),
        inserter: TextInserter(clipboard: pasteboard, paste: Pasted(), sleep: { _ in }),
        filter: TextFilter(), refiner: recorded, refinementIsEnabled: { true },
        history: NoHistory(), timings: .default, languages: { .default }))

    var report = ""
    var tally: [String: Int] = [:]
    for (index, dictation) in dictations.enumerated() {
      let session = index + 1
      heard.say(dictation)
      let recognised = TextFilter().evaluate(dictation.text, language: dictation.language).text
      let started = ContinuousClock.now
      await controller.handle(.start(session: session))
      await controller.handle(.stop(session: session, reason: .releasedHold))
      await controller.drain()
      let total = ContinuousClock.now - started

      #expect(pasteboard.writes.count == session, "#\(session) was not pasted exactly once")
      let pass = try #require(recorded.passes.count == session ? recorded.passes.last : nil)
      let pasted = try #require(pasteboard.writes.last)
      let blank = pasted.trimmingCharacters(in: .whitespaces).isEmpty
      let breaks = pasted.contains { $0.isNewline }
      #expect(!blank, "#\(session) pasted nothing")
      #expect(!breaks, "#\(session) pasted a line break")
      #expect(pass.took <= pass.deadline + .milliseconds(500), "#\(session) outran its deadline")
      #expect(total <= pass.deadline + .seconds(2), "#\(session) took \(total)")

      let outcome: String
      switch pass.output {
      case .failure(let error):
        outcome = "error \(error)"
        #expect(pasted == recognised, "#\(session) failed and pasted something else")
      case .success(let produced):
        switch RefinementPolicy.verdict(on: produced, original: pass.input) {
        case .refused(let why):
          outcome = "refused \(why.rawValue)"
          #expect(pasted == recognised, "#\(session) was refused and pasted something else")
        case .unchanged:
          outcome = "unchanged"
          #expect(pasted == pass.input)
        case .accepted(let accepted):
          outcome = "accepted"
          #expect(pasted == accepted)
        }
      }
      tally[outcome, default: 0] += 1
      let produced = (try? pass.output.get()) ?? "—"
      report += """
        #\(session) [\(dictation.language)] \(outcome), \(Int(pass.took / .milliseconds(1))) ms \
        of \(Int(pass.deadline / .milliseconds(1)))
          heard:  \(recognised)
          input:  \(pass.input == recognised ? "=" : pass.input)
          model:  \(produced)
          pasted: \(pasted)


        """
    }
    await refiner.unload()

    report +=
      tally.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
      .joined(separator: "\n") + "\n"
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("refiner-corpus-\(UUID().uuidString).txt")
    try report.write(to: file, atomically: true, encoding: .utf8)
    print("refiner corpus report: \(file.path)")
  }
}

private struct Dictation: Sendable {
  let language: String
  let text: String

  init(_ language: String, _ text: String) {
    self.language = language
    self.text = text
  }
}

private let dictations: [Dictation] = [
  .init(
    "ru", "Ну вот, значит, сборка опять упала на этапе подписи, и я, короче, не понимаю почему."),
  .init("ru", "Надо купить четыре пачки муки и два литра молока к субботе."),
  .init(
    "ru",
    "Сервер отвечает за 250 миллисекунд, а раньше отвечал за 40, это, ну, в шесть раз медленнее."),
  .init("ru", "Я хочу сказать. Я хочу сказать, что релиз переносится на следующую неделю."),
  .init("ru", "Как мне, э-э, откатить последний коммит, если я уже сделал push в main?"),
  .init(
    "ru", "Короче, в pull request надо поправить тесты, потом сделать rebase и только потом merge."),
  .init("ru", "Не надо удалять старую ветку, она ещё не смёржена, и это, ну, не срочно."),
  .init("ru", "Вот, значит, завтра будет около пятнадцати градусов, а дождя, кажется, не будет."),
  .init("ru", "Можно ли запустить этот скрипт на линуксе, или он работает только на маке?"),
  .init(
    "ru", "Ну, в общем, я поставил таймер на двадцать минут, а духовку разогрел до 180 градусов."),
  .init("ru", "А где лежит конфиг для деплоя? Я его, честно говоря, так и не нашёл."),
  .init(
    "ru",
    "Значит так, сначала обновить зависимости, потом прогнать тесты, а потом, ну, собрать архив."),
  .init("en", "So um I think we should, like, move the release to Thursday at 3 pm."),
  .init("en", "I want to say. I want to say that the build is green again after the cache fix."),
  .init(
    "en", "Can you check whether the backup ran last night, because I don't see the new files?"),
  .init("en", "Basically the deploy takes about twelve minutes, and uh we need it under five."),
  .init(
    "en",
    "We don't need to rewrite the parser, we just need to, you know, fix the off by one error."),
  .init("en", "The invoice total is 1,250 dollars and the shipping is another forty."),
  .init("en", "So yeah, the train leaves at 7:45 and, um, it takes two hours to get there."),
  .init("en", "Is it possible to, uh, export the report as CSV instead of PDF?"),
  .init("pl", "No więc, wiesz, ten serwer znowu nie odpowiada i nie wiem dlaczego."),
  .init("pl", "Trzeba kupić trzy kilogramy ziemniaków i dwa bochenki chleba na weekend."),
  .init("pl", "Czy możemy przesunąć wdrożenie na piątek, bo testy jeszcze nie przechodzą?"),
  .init("pl", "Chciałem powiedzieć. Chciałem powiedzieć, że aktualizacja jest gotowa do wydania."),
  .init("pl", "Yyy, no, pociąg odjeżdża o 8:15 i jedzie mniej więcej cztery godziny."),
  .init("pl", "Nie usuwaj tego pliku konfiguracyjnego, bo bez niego aplikacja się nie uruchomi."),
  .init("uk", "Ну, значить, збірка знову впала, і я, чесно кажучи, не розумію чому."),
  .init("uk", "Треба купити п'ять кілограмів яблук і три пляшки олії до неділі."),
  .init("uk", "Чи можна запустити цей скрипт на сервері, чи він працює тільки локально?"),
  .init("uk", "Я хочу сказати. Я хочу сказати, що реліз переноситься на наступний тиждень."),
  .init("uk", "Короче, у pull request треба виправити тести, а потім зробити merge у main."),
  .init(
    "uk", "Сервер відповідає за 300 мілісекунд, а раніше відповідав за сорок, це не нормально."),
]

private final class RecordedRefiner: TextRefining, Sendable {
  struct Pass: Sendable {
    let input: String
    let deadline: Duration
    let took: Duration
    let output: Result<String, any Error>
  }

  private let inner: MLXRefiner
  private let recorded = Mutex<[Pass]>([])

  init(_ inner: MLXRefiner) { self.inner = inner }

  var modelID: String { inner.modelID }
  var passes: [Pass] { recorded.withLock { $0 } }

  func refine(_ text: String, deadline: Duration) async throws -> String {
    let started = ContinuousClock.now
    let output: Result<String, any Error>
    do {
      output = .success(try await inner.refine(text, deadline: deadline))
    } catch {
      output = .failure(error)
    }
    let pass = Pass(
      input: text, deadline: deadline, took: ContinuousClock.now - started, output: output)
    recorded.withLock { $0.append(pass) }
    return try output.get()
  }
}

private final class Heard: Transcribing, Sendable {
  private let current = Mutex(Dictation("en", ""))

  func say(_ dictation: Dictation) { current.withLock { $0 = dictation } }

  func transcribe(
    _ samples: [Float], languages: LanguageSelection, deadline: Duration
  ) async throws -> Transcription {
    let dictation = current.withLock { $0 }
    return Transcription(text: dictation.text, language: dictation.language)
  }
}

private final class OneSecondOfAudio: AudioRecording {
  var isRunning: Bool { get async { true } }
  func levelUpdates() -> AsyncStream<Float> { AsyncStream { $0.finish() } }
  func deviceChangeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
  func start() async throws {}
  func stop() async -> [Float] { [Float](repeating: 0.2, count: 16_000) }
  func discard() async {}
}

private struct OneSegment: SpeechDetecting {
  func markup(_ samples: [Float]) async throws -> SpeechMarkup {
    SpeechMarkup(
      segments: [SpeechSegment(start: .zero, end: .milliseconds(900), probability: 0.9)],
      totalDuration: .milliseconds(1_000))
  }
}

private struct SameField: TargetProbing {
  func snapshot(budget: Duration) async -> (TargetSnapshot, FocusedSubrole) {
    (TargetSnapshot(pid: 1, secureInputWasUp: false), .other("AXTextArea"))
  }
  func compare(_ snapshot: TargetSnapshot, budget: Duration) async -> TargetComparison {
    TargetComparison(
      pid: 1, sameWindow: true, sameElement: true, subrole: .other("AXTextArea"),
      secureInputIsUp: false)
  }
  func release(_ snapshot: TargetSnapshot) async {}
}

private final class Pasteboard: Clipboard, Sendable {
  private let state = Mutex((changeCount: 1, writes: [String]()))

  var changeCount: Int { state.withLock { $0.changeCount } }
  var writes: [String] { state.withLock { $0.writes } }

  func snapshot() -> ClipboardSnapshot { ClipboardSnapshot(items: [], changeCount: changeCount) }

  func write(_ text: String, concealed: Bool, transient: Bool) -> ClipboardWriteOutcome {
    state.withLock {
      $0.writes.append(text)
      $0.changeCount += 1
      return .written(changeCount: $0.changeCount)
    }
  }

  func restore(_ snapshot: ClipboardSnapshot) -> Int? {
    state.withLock {
      $0.changeCount += 1
      return $0.changeCount
    }
  }
}

private struct Pasted: PasteSending {
  func sendPaste() -> Bool { true }
}

private struct NoHistory: SessionRecording {
  func createDraft(
    session: Int, startedAt: Date, durationMilliseconds: Int, targetBundleID: String?,
    modelID: String?
  ) async -> UUID? { nil }
  func markTruncated(_ id: UUID) async {}
  func attachMetrics(_ id: UUID, _ metrics: SpeechMetrics) async {}
  func attachRawText(_ id: UUID, _ text: String, language: String?) async {}
  func attachFinalText(_ id: UUID, _ text: String) async {}
  func attachRefinement(_ id: UUID, modelID: String) async {}
  func setState(_ id: UUID, _ state: SessionState, reason: String?) async {}
}
