import AppKit

enum MenuBarMark {
  case idle
  case recording

  var image: NSImage {
    switch self {
    case .idle: return Self.idleImage
    case .recording: return Self.recordingImage
    }
  }

  private static let idleImage = render([
    (2.20, 1.50, 9.00), (5.05, 4.50, 8.50), (7.90, 7.50, 8.00),
    (10.75, 4.50, 8.50), (13.60, 1.50, 9.00),
  ])
  private static let recordingImage = render([
    (2.20, 1.00, 10.60), (5.05, 3.60, 10.20), (7.90, 6.20, 9.80),
    (10.75, 3.60, 10.20), (13.60, 1.00, 10.60),
  ])

  private static func render(_ bars: [(CGFloat, CGFloat, CGFloat)]) -> NSImage {
    let width: CGFloat = 2.20
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
      NSColor.black.setFill()
      for (x, top, height) in bars {
        NSBezierPath(
          roundedRect: NSRect(x: x, y: top, width: width, height: height),
          xRadius: width / 2, yRadius: width / 2
        ).fill()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
