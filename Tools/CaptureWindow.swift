// swift Tools/CaptureWindow.swift <pid> <output.png>
//
// screencapture -l reads a window's own backing store, so the frame carries the
// system shadow and a transparent surround, and nothing floating above the
// window lands in it. It needs a CGWindowID, which only
// CGWindowListCopyWindowInfo can supply.
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data(("capture: " + message + "\n").utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let pid = Int(arguments[0]) else {
  fail("usage: CaptureWindow <pid> <output.png>")
}
let output = arguments[1]
let minimumWidth = 900.0

func settingsWindow() -> Int? {
  let listed =
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
  return
    listed
    .filter {
      $0[kCGWindowOwnerPID as String] as? Int == pid
        && $0[kCGWindowLayer as String] as? Int == 0
        // A window is listed as soon as it is ordered in, before it has been
        // laid out to its own minimum, so a narrow one is not yet the window.
        && ($0[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0 >= minimumWidth
    }
    .compactMap { $0[kCGWindowNumber as String] as? Int }
    .first
}

var number: Int?
for _ in 0..<80 {
  number = settingsWindow()
  if number != nil { break }
  Thread.sleep(forTimeInterval: 0.25)
}
guard let number else { fail("process \(pid) opened no window \(Int(minimumWidth))pt or wider") }

func shoot(_ path: String) {
  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  task.arguments = ["-x", "-l\(number)", path]
  guard (try? task.run()) != nil else { fail("could not run /usr/sbin/screencapture") }
  task.waitUntilExit()
  guard task.terminationStatus == 0 else { fail("screencapture refused \(path)") }
}

// Being listed is not being drawn: the window is ordered in before SwiftUI has
// rendered and while it is still fading. Waiting for two identical frames would
// be the honest proof, but the Microphone section draws a live level meter and
// never produces two, so the wait is fixed instead — long enough for the fade
// and for ModelStore.isReady, measured at 601ms over the full manifest.
Thread.sleep(forTimeInterval: 1.5)
shoot(output)
