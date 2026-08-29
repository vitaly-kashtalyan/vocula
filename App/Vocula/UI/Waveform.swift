import SwiftUI

enum WaveformGeometry {
  static let pitch: CGFloat = 0.5
  static let width: CGFloat = 78
  static var barCount: Int { Int(width / pitch) }
}

struct WaveformPalette {
  let resting: Color
  let cool: Color
  let warm: Color

  static let pane = WaveformPalette(
    resting: Theme.paneInk,
    cool: Theme.paneHighlight,
    warm: Theme.paneSand)

  static let window = WaveformPalette(
    resting: Theme.textMuted,
    cool: Theme.windowRampCool,
    warm: Theme.windowRampWarm)
}

struct Waveform: View, Animatable {
  var samples: [CGFloat]
  var width: CGFloat
  var height: CGFloat
  var opacity: Double
  var spread: CGFloat
  var glass: Double
  var palette: WaveformPalette

  nonisolated var animatableData: CGFloat {
    get { spread }
    set { spread = newValue }
  }

  private static let edgeFade: CGFloat = 0.08

  var body: some View {
    Canvas { context, size in
      let barWidth = WaveformGeometry.pitch * (1 - spread / 2)
      let count = max(1, Int(size.width / WaveformGeometry.pitch))
      let mid = size.height / 2
      let reach = size.height / 2 - 2
      let shading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [
          palette.resting.mix(with: palette.cool, by: Double(spread)),
          palette.resting.mix(with: palette.warm, by: Double(spread)),
        ]),
        startPoint: CGPoint(x: 0, y: mid),
        endPoint: CGPoint(x: size.width, y: mid))
      for index in 0..<count {
        let half = max(barWidth / 2, sample(at: index, of: count) * reach)
        let x = size.width - CGFloat(count - index) * WaveformGeometry.pitch
        let bar = Path(
          roundedRect: CGRect(
            x: x, y: mid - half,
            width: barWidth, height: half * 2),
          cornerRadius: barWidth / 2 * spread)
        context.fill(bar, with: shading)
      }
    }
    .mask(
      LinearGradient(
        stops: [
          .init(color: .white.opacity(0.8), location: 0),
          .init(color: .white, location: 0.5),
          .init(color: .white.opacity(0.8), location: 1),
        ],
        startPoint: .top, endPoint: .bottom)
    )
    .mask(
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .white, location: Self.edgeFade),
          .init(color: .white, location: 1 - Self.edgeFade),
          .init(color: .clear, location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)
    )
    .indicatorPane(
      RoundedRectangle(cornerRadius: 8, style: .continuous),
      horizontal: 9, vertical: 3, opacity: glass
    )
    .frame(width: width, height: height)
    .opacity(opacity)
  }

  private func sample(at index: Int, of count: Int) -> CGFloat {
    let position = samples.count - (count - index)
    return position >= 0 && position < samples.count ? samples[position] : 0
  }
}
