import Foundation
import Flutter

/// Reads at most one explicitly submitted share from the App Group.
enum OneSpaceShareInbox {
  static func takeNext() -> [String: Any]? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "OneSpaceShareGroup") as? String,
          let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group) else { return nil }
    let inbox = root.appendingPathComponent("Incoming", isDirectory: true)
    let manager = FileManager.default
    guard let files = try? manager.contentsOfDirectory(
      at: inbox, includingPropertiesForKeys: [.creationDateKey]) else { return nil }
    let manifests = files.filter { $0.pathExtension == "json" }
      .sorted {
        let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return a < b
      }
    for manifest in manifests {
      guard let data = try? Data(contentsOf: manifest),
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
            let id = payload["id"], UUID(uuidString: id) != nil,
            manifest.lastPathComponent == id + ".json" else {
        try? manager.removeItem(at: manifest)
        continue
      }
      var result: [String: Any] = [
        "text": String((payload["text"] ?? "").prefix(8000)),
        "subject": String((payload["subject"] ?? "").prefix(120)),
      ]
      let mime = payload["fileMime"] ?? ""
      let supported = ["application/pdf", "image/jpeg", "image/png",
                       "image/webp", "image/heic"]
      let blob = inbox.appendingPathComponent(id + ".blob")
      if !mime.isEmpty {
        guard supported.contains(mime),
              let size = try? blob.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0 && size <= 10 * 1024 * 1024,
              let bytes = try? Data(contentsOf: blob) else {
          try? manager.removeItem(at: manifest)
          try? manager.removeItem(at: blob)
          return ["fileError": "The shared file could not be opened or exceeds 10 MB."]
        }
        result["fileMime"] = mime
        result["fileName"] = String((payload["fileName"] ?? "").prefix(240))
        result["fileBytes"] = FlutterStandardTypedData(bytes: bytes)
      }
      try? manager.removeItem(at: manifest)
      try? manager.removeItem(at: blob)
      return result
    }
    return nil
  }
}
