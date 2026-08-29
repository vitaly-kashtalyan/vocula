import Foundation

public enum ModelStatus: Equatable, Sendable {
  case missing
  case incomplete(bytes: Int64)
  case corrupted
  case ready
}

public enum SpaceVerdict: Equatable, Sendable {
  case enough
  case short(byBytes: Int64)
  case unknown

  public var humanReadable: String {
    switch self {
    case .enough:
      return String(
        localized: "models.space.enough", defaultValue: "there is enough room", bundle: .module,
        comment: "Disk-space verdict, shown inside a longer sentence.")
    case .short(let bytes):
      let gigabytes = (Double(bytes) / 1_073_741_824)
        .formatted(.number.precision(.fractionLength(1)))
      return String(
        localized: "models.space.short", defaultValue: "\(gigabytes) GB short", bundle: .module,
        comment: "Disk-space verdict; the argument is an already-formatted number of gigabytes.")
    case .unknown:
      return String(
        localized: "models.space.unknown", defaultValue: "free disk space could not be determined",
        bundle: .module,
        comment: "Disk-space verdict, shown inside a longer sentence.")
    }
  }
}

public protocol ModelFileSystem: Sendable {
  func fileExists(at url: URL) -> Bool
  func size(of url: URL) -> Int64?
  func availableCapacity(at url: URL) -> Int64?
  func sha256(of url: URL) throws -> String
}

public struct ModelStore: Sendable {
  public let directory: URL
  private let fileSystem: ModelFileSystem
  public let descriptors: [ModelDescriptor]

  public init(
    directory: URL, fileSystem: ModelFileSystem,
    manifest: [ModelDescriptor] = ModelManifest.current
  ) {
    self.directory = directory
    self.fileSystem = fileSystem
    self.descriptors = manifest
  }

  public func url(for id: ModelID) -> URL {
    directory.appendingPathComponent(descriptor(for: id).fileName)
  }

  public func status(of id: ModelID) -> ModelStatus {
    let model = descriptor(for: id)
    let location = url(for: id)
    guard fileSystem.fileExists(at: location), let size = fileSystem.size(of: location) else {
      return .missing
    }
    if size < model.byteSize { return .incomplete(bytes: size) }
    guard let digest = try? fileSystem.sha256(of: location), digest == model.sha256 else {
      return .corrupted
    }
    return .ready
  }

  public func missingBytes(for ids: [ModelID]) -> Int64 {
    Self.missingBytes(over: statuses(for: ids))
  }

  public func spaceVerdict(for ids: [ModelID]) -> SpaceVerdict {
    let statuses = statuses(for: ids)
    let needed = Self.missingBytes(over: statuses)
    guard let available = fileSystem.availableCapacity(at: directory) else { return .unknown }
    let reclaimable = statuses.reduce(Int64(0)) { total, entry in
      guard entry.status == .corrupted else { return total }
      return total + max(fileSystem.size(of: url(for: entry.model.id)) ?? 0, 0)
    }
    let effectiveAvailable = max(available, 0).addingReportingOverflow(reclaimable)
    let capacity = effectiveAvailable.overflow ? Int64.max : effectiveAvailable.partialValue
    return capacity >= needed ? .enough : .short(byBytes: needed - capacity)
  }

  private func statuses(for ids: [ModelID]) -> [(model: ModelDescriptor, status: ModelStatus)] {
    ids.map { (descriptor(for: $0), status(of: $0)) }
  }

  private static func missingBytes(over statuses: [(model: ModelDescriptor, status: ModelStatus)])
    -> Int64
  {
    statuses.reduce(Int64(0)) { total, entry in
      switch entry.status {
      case .ready: return total
      case .incomplete(let bytes): return total + (entry.model.byteSize - bytes)
      case .missing, .corrupted: return total + entry.model.byteSize
      }
    }
  }

  public func isReady(_ ids: [ModelID]) -> Bool {
    ids.allSatisfy { status(of: $0) == .ready }
  }

  public func descriptor(for id: ModelID) -> ModelDescriptor {
    guard let model = descriptors.first(where: { $0.id == id }) else {
      preconditionFailure("manifest is missing \(id)")
    }
    return model
  }
}
