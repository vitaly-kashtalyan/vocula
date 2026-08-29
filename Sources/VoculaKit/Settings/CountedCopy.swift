import Foundation

public struct CountedCopy: Equatable, Sendable {
  public let key: String
  public let count: Int
  public let extra: [Int]

  public init(key: String, count: Int, extra: [Int] = []) {
    self.key = key
    self.count = count
    self.extra = extra
  }
}

public enum DiagnosticsCopy {
  public static func lastEvents(count: Int) -> CountedCopy {
    CountedCopy(key: "diagnostics.lastEvents", count: count)
  }
}

public enum HistoryCopy {
  public static func dictations(count: Int) -> CountedCopy {
    CountedCopy(key: "history.dictations", count: count)
  }

  public static func records(count: Int) -> CountedCopy {
    CountedCopy(key: "history.records", count: count)
  }

  public static func retentionDays(count: Int) -> CountedCopy {
    CountedCopy(key: "history.retentionDays", count: count)
  }

  public static func words(count: Int) -> CountedCopy {
    CountedCopy(key: "history.words", count: count)
  }

  public static func willBeDeleted(count: Int) -> CountedCopy {
    CountedCopy(key: "history.willBeDeleted", count: count)
  }
}

public enum LicenceCopy {
  public static func trialDaysLeft(count: Int) -> CountedCopy {
    CountedCopy(key: "licence.trialDaysLeft", count: count)
  }

  public static func dictationsLeftToday(count: Int, of limit: Int) -> CountedCopy {
    CountedCopy(key: "licence.dictationsLeftToday", count: count, extra: [limit])
  }

  public static func dictationsLeftNotice(count: Int) -> CountedCopy {
    CountedCopy(key: "licence.dictationsLeftNotice", count: count)
  }
}

public enum LanguageCopy {
  public static func enginesLanguages(count: Int) -> CountedCopy {
    CountedCopy(key: "languages.engineCount", count: count)
  }
}
