import AppKit
import VoculaKit

final class SystemClipboard: Clipboard, @unchecked Sendable {
  private let pasteboard = NSPasteboard.general

  private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
  private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

  var changeCount: Int { pasteboard.changeCount }

  func snapshot() -> ClipboardSnapshot {
    var total = 0
    var items: [[String: Data]] = []
    for item in pasteboard.pasteboardItems ?? [] {
      var stored: [String: Data] = [:]
      for type in item.types {
        guard let data = item.data(forType: type) else { continue }
        total += data.count
        guard total <= ClipboardSnapshot.byteCap else {
          return ClipboardSnapshot(
            items: [],
            changeCount: pasteboard.changeCount,
            abandoned: true)
        }
        stored[type.rawValue] = data
      }
      items.append(stored)
    }
    return ClipboardSnapshot(items: items, changeCount: pasteboard.changeCount)
  }

  func write(
    _ text: String, concealed: Bool,
    transient: Bool
  ) -> ClipboardWriteOutcome {
    let item = NSPasteboardItem()
    guard item.setString(text, forType: .string),
      !concealed || item.setString("", forType: Self.concealedType),
      !transient || item.setString("", forType: Self.transientType)
    else { return .failed(afterChangeCount: nil) }
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      return .failed(afterChangeCount: pasteboard.changeCount)
    }
    return .written(changeCount: pasteboard.changeCount)
  }

  @discardableResult
  func restore(_ snapshot: ClipboardSnapshot) -> Int? {
    pasteboard.clearContents()
    let items = snapshot.items.map { stored -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in stored {
        item.setData(data, forType: NSPasteboard.PasteboardType(type))
      }
      return item
    }
    if !items.isEmpty, !pasteboard.writeObjects(items) { return nil }
    return pasteboard.changeCount
  }
}
