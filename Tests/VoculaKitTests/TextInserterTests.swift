import Foundation
import Testing

@testable import VoculaKit

private final class FakeClipboard: Clipboard, @unchecked Sendable {
  var changeCount = 10
  var contents = "previous"
  var lastWriteWasConcealed = false
  var lastWriteWasTransient = false
  var restored: [String] = []
  var writeSucceeds = true
  var bumpOnNextRead: Bool = false
  var snapshotIsAbandoned = false
  var refuseRestore = false

  func snapshot() -> ClipboardSnapshot {
    if snapshotIsAbandoned {
      return ClipboardSnapshot(items: [], changeCount: changeCount, abandoned: true)
    }
    return ClipboardSnapshot(
      items: [["public.utf8-plain-text": Data(contents.utf8)]],
      changeCount: changeCount)
  }

  func write(
    _ text: String, concealed: Bool,
    transient: Bool
  ) -> ClipboardWriteOutcome {
    contents = text
    lastWriteWasConcealed = concealed
    lastWriteWasTransient = transient
    changeCount += 1
    return writeSucceeds
      ? .written(changeCount: changeCount)
      : .failed(afterChangeCount: changeCount)
  }

  func restore(_ snapshot: ClipboardSnapshot) -> Int? {
    if refuseRestore { return nil }
    let text =
      snapshot.items.first.map {
        String(decoding: $0["public.utf8-plain-text"]!, as: UTF8.self)
      } ?? ""
    restored.append(text)
    contents = text
    changeCount += 1
    return changeCount
  }
}

private final class FakePaste: PasteSending, @unchecked Sendable {
  var sent = 0
  var succeeds = true
  let onSend: @Sendable () -> Void
  init(onSend: @escaping @Sendable () -> Void = {}) { self.onSend = onSend }
  func sendPaste() -> Bool {
    sent += 1
    onSend()
    return succeeds
  }
}

private final class Recorded<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Value] = []
  func append(_ value: Value) { lock.withLock { values.append(value) } }
  var all: [Value] { lock.withLock { values } }
  var last: Value? { lock.withLock { values.last } }
}

private func approval() -> InsertApproval {
  let snapshot = TargetSnapshot(pid: 1, secureInputWasUp: false)
  let comparison = TargetComparison(
    pid: 1, sameWindow: true, sameElement: true,
    subrole: .other("AXTextField"), secureInputIsUp: false)
  return TargetGuardPolicy.approveInsert(snapshot: snapshot, comparison: comparison)!
}

private func settle(_ outcome: InsertOutcome, with inserter: TextInserter) async -> Bool? {
  guard case .sent(let restore) = outcome else { return nil }
  return await inserter.restoreClipboard(restore)
}

@Suite("TextInserter")
struct TextInserterTests {
  @Test("the text is written, pasted, and the previous contents come back")
  func happyPath() async {
    let clipboard = FakeClipboard()
    let paste = FakePaste()
    let inserter = TextInserter(
      clipboard: clipboard, paste: paste,
      timings: .default, sleep: { _ in })
    let outcome = await inserter.insert("dictated text", approval: approval())
    #expect(paste.sent == 1)
    #expect(clipboard.restored.isEmpty)
    #expect(await settle(outcome, with: inserter) == true)
    #expect(clipboard.restored == ["previous"])
  }

  @Test("the text is marked concealed and transient for clipboard managers")
  func markedForClipboardManagers() async {
    let clipboard = FakeClipboard()
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in })
    _ = await inserter.insert("secret", approval: approval())
    #expect(clipboard.lastWriteWasConcealed == true)
    #expect(clipboard.lastWriteWasTransient == true)
  }

  @Test("if the clipboard moved during the delay, the previous contents are NOT restored")
  func doesNotClobberTheUsersCopy() async {
    let clipboard = FakeClipboard()
    let paste = FakePaste()
    let inserter = TextInserter(
      clipboard: clipboard, paste: paste, timings: .default,
      sleep: { _ in clipboard.changeCount += 5 })
    let outcome = await inserter.insert("dictated text", approval: approval())
    #expect(await settle(outcome, with: inserter) == false)
    #expect(clipboard.restored.isEmpty)
  }

  @Test("the restore waits the spec's delay so the receiver can read the paste")
  func waitsBeforeRestoring() async {
    let slept = Recorded<Duration>()
    let inserter = TextInserter(
      clipboard: FakeClipboard(), paste: FakePaste(),
      timings: .default, sleep: { slept.append($0) })
    let outcome = await inserter.insert("text", approval: approval())
    #expect(slept.all.isEmpty)
    _ = await settle(outcome, with: inserter)
    #expect(slept.all == [.seconds(1)])
  }

  @Test("the paste is sent AFTER the text is on the clipboard, never before")
  func orderIsWriteThenPaste() async {
    let clipboard = FakeClipboard()
    let contentsAtPaste = Recorded<String>()
    let paste = FakePaste(onSend: { contentsAtPaste.append(clipboard.contents) })
    let inserter = TextInserter(
      clipboard: clipboard, paste: paste,
      timings: .default, sleep: { _ in })
    _ = await inserter.insert("dictated text", approval: approval())
    #expect(contentsAtPaste.last == "dictated text")
  }

  @Test("empty text is not pasted at all")
  func emptyTextIsNotPasted() async {
    let paste = FakePaste()
    let inserter = TextInserter(
      clipboard: FakeClipboard(), paste: paste,
      timings: .default, sleep: { _ in })
    _ = await inserter.insert("   ", approval: approval())
    #expect(paste.sent == 0)
  }

  @Test("a failed clipboard write never sends paste and restores the snapshot")
  func clipboardWriteFailureIsLocalFailure() async {
    let clipboard = FakeClipboard()
    clipboard.writeSucceeds = false
    let paste = FakePaste()
    let outcome = await TextInserter(
      clipboard: clipboard, paste: paste,
      sleep: { _ in }
    ).insert("text", approval: approval())
    #expect(outcome == .failedLocally)
    #expect(paste.sent == 0)
    #expect(clipboard.restored == ["previous"])
  }

  @Test("failure to create the paste chord restores our clipboard write")
  func localPasteFailureRestoresClipboard() async {
    let clipboard = FakeClipboard()
    let paste = FakePaste()
    paste.succeeds = false
    let outcome = await TextInserter(
      clipboard: clipboard, paste: paste,
      sleep: { _ in }
    ).insert("text", approval: approval())
    #expect(outcome == .failedLocally)
    #expect(clipboard.restored == ["previous"])
  }

  @Test("an over-cap clipboard is emptied rather than left holding the transcript")
  func abandonedSnapshotIsNotRestored() async {
    let clipboard = FakeClipboard()
    clipboard.snapshotIsAbandoned = true
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in })
    let outcome = await inserter.insert("dictated text", approval: approval())
    #expect(await settle(outcome, with: inserter) == false)
    #expect(clipboard.restored == [""])
  }

  @Test("dropping an over-cap clipboard is recorded exactly once")
  func abandonedSnapshotIsRecorded() async {
    let clipboard = FakeClipboard()
    clipboard.snapshotIsAbandoned = true
    let recorded = Recorded<Bool>()
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in },
      recordClipboardNotRestored: { recorded.append(true) })
    let outcome = await inserter.insert("dictated text", approval: approval())
    _ = await settle(outcome, with: inserter)
    #expect(recorded.all == [true])
  }

  @Test("an ordinary insert records nothing about the clipboard")
  func normalInsertRecordsNothing() async {
    let recorded = Recorded<Bool>()
    let clipboard = FakeClipboard()
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(), timings: .default,
      sleep: { _ in clipboard.changeCount += 5 },
      recordClipboardNotRestored: { recorded.append(true) })
    let outcome = await inserter.insert("dictated text", approval: approval())
    _ = await settle(outcome, with: inserter)
    #expect(recorded.all.isEmpty)
  }

  @Test("a restore that actually happens records nothing")
  func successfulRestoreRecordsNothing() async {
    let recorded = Recorded<Bool>()
    let clipboard = FakeClipboard()
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in },
      recordClipboardNotRestored: { recorded.append(true) })
    let outcome = await inserter.insert("dictated text", approval: approval())
    #expect(await settle(outcome, with: inserter) == true)
    #expect(recorded.all.isEmpty)
    #expect(clipboard.restored == ["previous"])
  }
}

@Suite("A clipboard restore that does not take")
struct FailedRestoreTests {
  @Test("it is recorded rather than reported as success")
  func failedRestoreIsRecorded() async {
    let clipboard = FakeClipboard()
    clipboard.refuseRestore = true
    let recorded = Recorded<Bool>()
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in },
      recordClipboardNotRestored: { recorded.append(true) })
    let outcome = await inserter.insert("dictated text", approval: approval())
    #expect(await settle(outcome, with: inserter) == false)
    #expect(recorded.all == [true], "a lost clipboard left no record")
  }
}

@Suite("Two dictations close enough to overlap")
struct OverlappingInsertTests {
  @Test("the second one does not strand the clipboard the user had before either")
  func theUsersOwnCopySurvivesBothDictations() async {
    let clipboard = FakeClipboard()
    clipboard.contents = "the user's own copy"
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in })

    let first = await inserter.insert("first dictation", approval: approval())
    let second = await inserter.insert("second dictation", approval: approval())
    _ = await settle(first, with: inserter)
    _ = await settle(second, with: inserter)

    #expect(
      clipboard.restored.last == "the user's own copy",
      "the clipboard was left holding a transcript instead of what the user copied")
    #expect(
      !clipboard.restored.contains("first dictation"),
      "one dictation's text was restored over another's")
  }

  @Test(
    "the second one takes its snapshot from the restored clipboard, not from the first transcript")
  func theSecondSnapshotIsTheUsersCopy() async {
    let clipboard = FakeClipboard()
    clipboard.contents = "the user's own copy"
    let inserter = TextInserter(
      clipboard: clipboard, paste: FakePaste(),
      timings: .default, sleep: { _ in })

    _ = await inserter.insert("first dictation", approval: approval())
    guard case .sent(let second) = await inserter.insert("second dictation", approval: approval())
    else {
      Issue.record("the second insert did not report as sent")
      return
    }
    #expect(
      second.previous.items.first?["public.utf8-plain-text"] == Data("the user's own copy".utf8))
  }
}
