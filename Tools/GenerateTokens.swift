#!/usr/bin/env swift
import Foundation

// MARK: - Colour maths

struct RGB {
  var r, g, b: Double
  var clipped: Bool
}

func oklabToRGB(_ L: Double, _ A: Double, _ B: Double) -> RGB {
  let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
  let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
  let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
  var lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ]
  let clipped = lin.contains { $0 < -0.0008 || $0 > 1.0008 }
  lin = lin.map { min(1, max(0, $0)) }
  return RGB(r: lin[0], g: lin[1], b: lin[2], clipped: clipped)
}

func oklchToRGB(_ L: Double, _ C: Double, _ hDeg: Double) -> RGB {
  let h = hDeg * .pi / 180
  return oklabToRGB(L, C * cos(h), C * sin(h))
}

func rgbToOklab(_ hex: String) -> (L: Double, A: Double, B: Double) {
  let v = UInt32(hex.dropFirst(), radix: 16)!
  let c = [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF].map { ch -> Double in
    let d = Double(ch) / 255
    return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
  }
  let l = cbrt(0.4122214708 * c[0] + 0.5363325363 * c[1] + 0.0514459929 * c[2])
  let m = cbrt(0.2119034982 * c[0] + 0.6806995451 * c[1] + 0.1073969566 * c[2])
  let s = cbrt(0.0883024619 * c[0] + 0.2817188376 * c[1] + 0.6299787005 * c[2])
  return (
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  )
}

func hex(_ c: RGB) -> String {
  let enc = [c.r, c.g, c.b].map { v -> Int in
    let s = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    return Int((s * 255).rounded())
  }
  return "#" + enc.map { String(format: "%02X", $0) }.joined()
}

func resolve(_ value: String) -> (hex: String, clipped: Bool) {
  if value.hasPrefix("#") { return (value.uppercased(), false) }
  guard value.hasPrefix("oklch(") else { fatalError("unparsable colour: \(value)") }
  let nums = value.dropFirst(6).dropLast()
    .split(whereSeparator: { $0 == " " || $0 == "," })
    .compactMap { Double($0) }
  guard nums.count == 3 else { fatalError("oklch needs 3 numbers: \(value)") }
  let c = oklchToRGB(nums[0], nums[1], nums[2])
  return (hex(c), c.clipped)
}

// MARK: - Load

let root = FileManager.default.currentDirectoryPath
let check = CommandLine.arguments.contains("--check")

guard let data = FileManager.default.contents(atPath: "\(root)/Design/tokens.json"),
  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
  let rawTokens = json["tokens"] as? [[String: Any]]
else {
  FileHandle.standardError.write(
    "cannot read Design/tokens.json — run from the repository root\n".data(using: .utf8)!)
  exit(1)
}

struct Token {
  let name: String, scope: String
  let light: String?, dark: String?, flat: String?
  var note: String?
}

let tokens: [Token] = rawTokens.map {
  Token(
    name: $0["name"] as! String,
    scope: $0["scope"] as! String,
    light: $0["light"] as? String,
    dark: $0["dark"] as? String,
    flat: $0["value"] as? String,
    note: $0["note"] as? String)
}

var flat: [String: String] = [:]
for t in tokens where t.flat != nil { flat[t.name] = resolve(t.flat!).hex }

if let ramp = json["iconRamp"] as? [String: Any],
  let stops = ramp["stops"] as? [Double],
  let fromName = ramp["from"] as? String, let toName = ramp["to"] as? String,
  let from = flat[fromName], let to = flat[toName]
{
  let a = rgbToOklab(from)
  let b = rgbToOklab(to)
  for (i, t) in stops.enumerated() {
    let c = oklabToRGB(a.L + (b.L - a.L) * t, a.A + (b.A - a.A) * t, a.B + (b.B - a.B) * t)
    flat["mark.ramp.\(i + 1)"] = hex(c)
  }
}

// MARK: - Emit

var written: [String] = []
var drifted: [String] = []

func put(_ path: String, _ body: String) {
  let full = "\(root)/\(path)"
  let existing = (try? String(contentsOfFile: full, encoding: .utf8)) ?? ""
  if existing == body { return }
  if check {
    drifted.append(path)
    return
  }
  try? FileManager.default.createDirectory(
    atPath: (full as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true)
  try! body.write(toFile: full, atomically: true, encoding: .utf8)
  written.append(path)
}

func swiftIdentifier(_ name: String) -> String {
  let parts = name.split(separator: ".")
  return parts.enumerated().map {
    $0.offset == 0
      ? String($0.element)
      : $0.element.prefix(1).uppercased() + $0.element.dropFirst()
  }.joined()
}

var sw = """
  // GENERATED from Design/tokens.json by Tools/GenerateTokens.swift. Do not edit.

  import Foundation

  extension Theme {
      enum Tokens {\n
  """
for t in tokens where t.scope != "web" {
  if let note = t.note { sw += "        /// \(note)\n" }
  let id = swiftIdentifier(t.name)
  if let v = t.flat {
    let r = resolve(v)
    sw += "        static let \(id): UInt32 = 0x\(r.hex.dropFirst())"
    sw += r.clipped ? "  // clipped to sRGB\n\n" : "\n\n"
  } else {
    if let l = t.light {
      sw += "        static let \(id)Light: UInt32 = 0x\(resolve(l).hex.dropFirst())\n"
    }
    if let d = t.dark {
      sw += "        static let \(id)Dark: UInt32 = 0x\(resolve(d).hex.dropFirst())\n"
    }
    sw += "\n"
  }
}
sw += "    }\n}\n"
put("App/Vocula/UI/ThemeTokens.swift", sw)

var css = """
  /* Design/build/tokens.css
   *
   * GENERATED by Tools/GenerateTokens.swift from Design/tokens.json.
   * Do not edit. Copy into the website as src/styles/tokens.generated.css.
   *
   * Only tokens scoped `both` or `web` appear — the app's greys and the mark's
   * exaggerated orange are deliberately absent.
   *
   * Values are the SOURCE values, OKLCH where the token is authored in OKLCH.
   * Browsers take oklch() natively, and the website takes the SOURCE values
   * rather than the sRGB conversion the Swift side needs: converting here would
   * throw away precision the browser can use, and would clip on this machine
   * what the reader's wide-gamut display could have shown. */

  :root {\n
  """
func cssVar(_ n: String) -> String { "--" + n.replacingOccurrences(of: ".", with: "-") }
for t in tokens where t.scope != "app" {
  if let note = t.note { css += "  /* \(note) */\n" }
  if let v = t.flat {
    css += "  \(cssVar(t.name)): \(v);\n"
  } else if let l = t.light {
    css += "  \(cssVar(t.name)): \(l);\n"
  }
}
css += "}\n\n@media (prefers-color-scheme: dark) {\n  :root {\n"
for t in tokens where t.scope != "app" {
  if let d = t.dark { css += "    \(cssVar(t.name)): \(d);\n" }
}
css += "  }\n}\n\n:root[data-theme=\"light\"] {\n"
for t in tokens where t.scope != "app" {
  if let l = t.light { css += "  \(cssVar(t.name)): \(l);\n" }
}
css += "}\n\n:root[data-theme=\"dark\"] {\n"
for t in tokens where t.scope != "app" {
  if let d = t.dark { css += "  \(cssVar(t.name)): \(d);\n" }
}
css += "}\n"
put("Design/build/tokens.css", css)

for file in ["Icon/vocula-icon.svg", "Icon/vocula-icon-small.svg", "Icon/vocula-icon-32.svg"] {
  guard var svg = try? String(contentsOfFile: "\(root)/\(file)", encoding: .utf8) else {
    FileHandle.standardError.write(
      "tokens: cannot read \(file) — nothing was checked for it\n".data(using: .utf8)!)
    exit(1)
  }
  for (name, value) in flat {
    for attr in ["fill", "stop-color"] {
      let pattern =
        "\(attr)=\"#[0-9A-Fa-f]{6}\"( data-token=\"\(NSRegularExpression.escapedPattern(for: name))\")"
      let re = try! NSRegularExpression(pattern: pattern)
      svg = re.stringByReplacingMatches(
        in: svg, range: NSRange(svg.startIndex..., in: svg),
        withTemplate: "\(attr)=\"\(value)\"$1")
    }
  }
  put(file, svg)
}

// MARK: - Report

if check {
  if drifted.isEmpty {
    print("tokens: all generated files match Design/tokens.json")
  } else {
    FileHandle.standardError.write(
      ("tokens: DRIFT in \(drifted.count) file(s)\n"
        + drifted.map { "  \($0)\n" }.joined()
        + "run: swift Tools/GenerateTokens.swift\n").data(using: .utf8)!)
    exit(1)
  }
} else if written.isEmpty {
  print("tokens: nothing to do, everything already matches")
} else {
  written.forEach { print("wrote \($0)") }
  print(
    "\nIcon PNGs are NOT rebuilt here — run Tools/GenerateAppIcon.swift if a mark colour changed.")
}
