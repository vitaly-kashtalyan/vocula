import Carbon.HIToolbox
import Foundation

func installedLayoutData(_ inputSourceID: String) -> Data? {
  let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
  guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
    CFArrayGetCount(list) > 0
  else { return nil }
  let source = unsafeBitCast(CFArrayGetValueAtIndex(list, 0), to: TISInputSource.self)
  guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
  else { return nil }
  return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
}
