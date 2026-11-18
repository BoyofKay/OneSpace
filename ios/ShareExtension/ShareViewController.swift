import Foundation
import Social
import UIKit
import UniformTypeIdentifiers

/// OneSpace's iPhone share sheet entry. Shares are staged on this device only;
/// no Supabase call is made here and nothing is sent to the other partner.
final class ShareViewController: SLComposeServiceViewController {
  private let maximumBytes = 10 * 1024 * 1024
  private var submitting = false

  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    guard !submitting else { return }
    submitting = true
    let userNote = String((contentText ?? "").prefix(5000))
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }

    // Prefer one supported photo or PDF; avoid silently importing a whole
    // photo library, multiple attachments, or an unknown document type.
    let supported: [(UTType, String)] = [
      (.pdf, "application/pdf"), (.jpeg, "image/jpeg"),
      (.png, "image/png"), (.heic, "image/heic"), (.webP, "image/webp"),
      (.image, "image/jpeg"),
    ]
    if let selected = providers.compactMap({ provider -> (NSItemProvider, UTType, String)? in
      for (type, mime) in supported where provider.hasItemConformingToTypeIdentifier(type.identifier) {
        return (provider, type, mime)
      }
      return nil
    }).first {
      let (provider, type, mime) = selected
      provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
        guard let self = self else { return }
        if let url = url, let bytes = try? Data(contentsOf: url) {
          let name = url.lastPathComponent.isEmpty ? "Shared file" : url.lastPathComponent
          self.save(text: userNote, subject: "", bytes: bytes, name: name, mime: mime)
        } else {
          // Some Photos providers return UIImage but not a file URL.
          provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            if let image = item as? UIImage, let jpeg = image.jpegData(compressionQuality: 0.88) {
              self.save(text: userNote, subject: "", bytes: jpeg,
                        name: "Shared photo.jpg", mime: "image/jpeg")
            } else if let data = item as? Data {
              self.save(text: userNote, subject: "", bytes: data,
                        name: "Shared file", mime: mime)
            } else {
              self.fail("This attachment could not be opened.")
            }
          }
        }
      }
      return
    }

    // Safari and other applications offer a URL or plain text provider.
    if let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
    }) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
        guard let self = self else { return }
        let link = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
        self.save(text: [userNote, link].filter { !$0.isEmpty }.joined(separator: "\n"),
                  subject: "", bytes: nil, name: "", mime: "")
      }
      return
    }
    if let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
        guard let self = self else { return }
        let value = (item as? String) ?? (item as? URL)?.absoluteString ?? ""
        self.save(text: [userNote, value].filter { !$0.isEmpty }.joined(separator: "\n"),
                  subject: "", bytes: nil, name: "", mime: "")
      }
      return
    }
    if !userNote.isEmpty {
      save(text: userNote, subject: "", bytes: nil, name: "", mime: "")
    } else {
      fail("Share a link, text, photo or PDF to OneSpace.")
    }
  }

  private func save(text: String, subject: String, bytes: Data?,
                    name: String, mime: String) {
    do {
      guard !text.isEmpty || bytes != nil else { throw InboxError.invalid }
      if let bytes = bytes, (bytes.isEmpty || bytes.count > maximumBytes) {
        throw InboxError.tooLarge
      }
      guard let group = Bundle.main.object(forInfoDictionaryKey: "OneSpaceShareGroup") as? String,
            let root = FileManager.default.containerURL(
              forSecurityApplicationGroupIdentifier: group) else {
        throw InboxError.unavailable
      }
      let inbox = root.appendingPathComponent("Incoming", isDirectory: true)
      try FileManager.default.createDirectory(at: inbox,
                                             withIntermediateDirectories: true)
      // Bound the inbox so malicious or unattended shares cannot fill storage.
      let existing = try FileManager.default.contentsOfDirectory(
        at: inbox, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
      guard existing.count < 20 else { throw InboxError.full }
      let identifier = UUID().uuidString
      let metadata: [String: String] = [
        "id": identifier, "text": String(text.prefix(8000)),
        "subject": String(subject.prefix(120)),
        "fileName": String(name.prefix(240)), "fileMime": mime
      ]
      if let bytes = bytes {
        try bytes.write(to: inbox.appendingPathComponent(identifier + ".blob"),
                        options: [.atomic, .completeFileProtection])
      }
      let json = try JSONSerialization.data(withJSONObject: metadata)
      // Write metadata last: the host app only picks complete entries.
      try json.write(to: inbox.appendingPathComponent(identifier + ".json"),
                     options: [.atomic, .completeFileProtection])
      DispatchQueue.main.async { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
      }
    } catch InboxError.tooLarge {
      fail("OneSpace accepts photos and PDFs up to 10 MB.")
    } catch InboxError.full {
      fail("Open OneSpace to sort your previous shares before adding more.")
    } catch {
      fail("Could not prepare this share. Please try again.")
    }
  }

  private func fail(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.submitting = false
      let alert = UIAlertController(title: "OneSpace", message: message, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      self.present(alert, animated: true)
    }
  }

  private enum InboxError: Error {
    case invalid, tooLarge, unavailable, full
  }
}
