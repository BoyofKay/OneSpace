import Flutter
import UIKit
import MessageUI
import UniformTypeIdentifiers
import AVFoundation
import Speech
import Contacts
import ContactsUI

/// R63: iOS counterparts of every Android platform channel.
///  - onespace/travel_documents  pick a PDF/image (≤10 MB)
///  - onespace/checklist_speech  speak / stop (reports "onSpeechDone" on onespace/voice)
///  - onespace/voice             in-app speech recognition with live words + app-icon shortcut
///  - onespace/data_export       save a file through the share sheet ("Save to Files")
///  - onespace/scrapbook_export  share/save a PNG page
///  - onespace/device_contacts   pick a contact, add a contact (user confirms in Contacts UI)
///  - onespace/incoming_share    nothing pending on iOS yet (needs a Share Extension)
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate,
  AVSpeechSynthesizerDelegate, CNContactPickerDelegate, CNContactViewControllerDelegate {

  static weak var shared: AppDelegate?
  static let voiceShortcutType = "com.onespace.onespace.VOICE"
  /// R64: voice is hidden until it is mature (matches Voice.enabled in Dart).
  static let voiceEnabled = false

  private var documentResult: FlutterResult?
  private let maximumDocumentSize = 10 * 1024 * 1024
  private let checklistSpeech = AVSpeechSynthesizer()

  // Voice
  private var voiceChannel: FlutterMethodChannel?
  private var pendingVoiceLaunch = false
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var lastTranscript = ""
  private var silenceTimer: Timer?
  private var finished = true
  private var lastLevelSent = Date.distantPast

  // Contacts
  private var contactResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.shared = self
    checklistSpeech.delegate = self
    let title = Locale.preferredLanguages.first?.hasPrefix("ar") == true ? "أمر صوتي" : "Voice command"
    application.shortcutItems = !AppDelegate.voiceEnabled ? [] : [UIApplicationShortcutItem(
      type: AppDelegate.voiceShortcutType, localizedTitle: title, localizedSubtitle: nil,
      icon: UIApplicationShortcutIcon(systemImageName: "mic.fill"), userInfo: nil)]
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Called by SceneDelegate when the app is opened from the "Voice command" quick action.
  func handleVoiceShortcut() {
    if let channel = voiceChannel {
      channel.invokeMethod("launchVoice", arguments: nil)
    } else {
      pendingVoiceLaunch = true
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    FlutterMethodChannel(name: "onespace/travel_documents", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "pickDocument" else { result(FlutterMethodNotImplemented); return }
        self?.selectDocument(result: result)
      }

    let voice = FlutterMethodChannel(name: "onespace/voice", binaryMessenger: messenger)
    voiceChannel = voice
    voice.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "available":
        result(SFSpeechRecognizer()?.isAvailable ?? false)
      case "takeLaunch":
        let pending = self.pendingVoiceLaunch
        self.pendingVoiceLaunch = false
        result(pending)
      case "start":
        let args = call.arguments as? [String: Any]
        self.startListening(language: args?["language"] as? String ?? "en-US")
        result(true)
      case "stop":
        self.finishListening()
        result(nil)
      case "cancel":
        self.cancelListening()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(name: "onespace/checklist_speech", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "VOICE_UNAVAILABLE", message: "Speech service missing", details: nil))
          return
        }
        switch call.method {
        case "stop":
          self.checklistSpeech.stopSpeaking(at: .immediate)
          result(nil)
        case "speak":
          guard let arguments = call.arguments as? [String: Any],
                let text = arguments["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                text.count <= 60000 else {
            result(FlutterError(code: "INVALID_TEXT", message: "Invalid text", details: nil))
            return
          }
          let language = arguments["language"] as? String ?? "en"
          let speed = min(max(arguments["rate"] as? Double ?? 1.0, 0.7), 1.4)
          self.checklistSpeech.stopSpeaking(at: .immediate)
          try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
          try? AVAudioSession.sharedInstance().setActive(true)
          let utterance = AVSpeechUtterance(string: text)
          utterance.voice = AVSpeechSynthesisVoice(language: language == "ar" ? "ar-SA" : (language == "en" ? "en-US" : language))
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
          utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
          self.checklistSpeech.speak(utterance)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "onespace/data_export", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "saveToDownloads",
              let args = call.arguments as? [String: Any],
              let name = args["name"] as? String,
              let bytes = args["bytes"] as? FlutterStandardTypedData else {
          result(FlutterMethodNotImplemented); return
        }
        self?.shareFile(name: name, data: bytes.data, result: result, doneLabel: "Files")
      }

    FlutterMethodChannel(name: "onespace/scrapbook_export", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        if call.method == "sharePdf",
           let args = call.arguments as? [String: Any],
           let bytes = args["bytes"] as? FlutterStandardTypedData {
          // R70: memories, selfies and scrapbooks as PDF (share sheet or Mail).
          let raw = (args["name"] as? String) ?? "OneSpace-Memory"
          let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
          let file = String(safe.prefix(80)) + ".pdf"
          if (args["email"] as? Bool) == true, MFMailComposeViewController.canSendMail(), let top = self?.topViewController() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setSubject((args["subject"] as? String) ?? raw)
            mail.addAttachmentData(bytes.data, mimeType: "application/pdf", fileName: file)
            top.present(mail, animated: true)
            result(true)
          } else {
            self?.shareFile(name: file, data: bytes.data, result: result, doneLabel: nil)
          }
          return
        }
        guard call.method == "saveAndShare",
              let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData else {
          result(FlutterMethodNotImplemented); return
        }
        let raw = (args["name"] as? String) ?? "OneSpace-Scrapbook"
        let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        self?.shareFile(name: String(safe.prefix(80)) + ".png", data: bytes.data, result: result, doneLabel: nil)
      }

    FlutterMethodChannel(name: "onespace/device_contacts", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(nil); return }
        switch call.method {
        case "pickContact": self.pickContact(result: result)
        case "saveToPhone": self.saveContact(call.arguments as? [String: Any] ?? [:], result: result)
        case "takePendingVcard": result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }

    FlutterMethodChannel(name: "onespace/incoming_share", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "takePendingShare" { result(nil) } else { result(FlutterMethodNotImplemented) }
      }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    checklistSpeech.stopSpeaking(at: .immediate)
    cancelListening()
    super.applicationWillResignActive(application)
  }

  // MARK: - Helpers

  private func topViewController() -> UIViewController? {
    let activeWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
    var top = (activeWindow ?? window)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Speech output

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    voiceChannel?.invokeMethod("onSpeechDone", arguments: nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    voiceChannel?.invokeMethod("onSpeechDone", arguments: nil)
  }

  // MARK: - Speech recognition (on-device where the phone supports it)

  private func sendVoice(_ method: String, _ value: Any?) {
    DispatchQueue.main.async { self.voiceChannel?.invokeMethod(method, arguments: value) }
  }

  private func startListening(language: String) {
    cancelListening()
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else { self.sendVoice("onError", "permission"); return }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async {
            guard granted else { self.sendVoice("onError", "permission"); return }
            self.beginRecognition(language: language)
          }
        }
      }
    }
  }

  private func beginRecognition(language: String) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
      sendVoice("onError", "unavailable"); return
    }
    checklistSpeech.stopSpeaking(at: .immediate)
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      sendVoice("onError", "unavailable"); return
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
    recognitionRequest = request
    lastTranscript = ""
    finished = false

    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
      self?.reportLevel(buffer)
    }
    audioEngine.prepare()
    do { try audioEngine.start() } catch {
      cleanUpAudio(); sendVoice("onError", "unavailable"); return
    }
    sendVoice("onReady", nil)
    restartSilenceTimer(seconds: 7)

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self = self else { return }
      if let result = result {
        let text = result.bestTranscription.formattedString
        DispatchQueue.main.async {
          guard !self.finished else { return }
          if !text.isEmpty {
            self.lastTranscript = text
            self.sendVoice("onPartial", text)
            self.restartSilenceTimer(seconds: 1.6)
          }
          if result.isFinal { self.complete() }
        }
      } else if error != nil {
        DispatchQueue.main.async {
          guard !self.finished else { return }
          if self.lastTranscript.isEmpty {
            self.finished = true
            self.cleanUpAudio()
            self.sendVoice("onEnd", nil)
            self.sendVoice("onError", "nothing")
          } else {
            self.complete()
          }
        }
      }
    }
  }

  private func reportLevel(_ buffer: AVAudioPCMBuffer) {
    guard let channel = buffer.floatChannelData?[0] else { return }
    let count = Int(buffer.frameLength)
    if count == 0 { return }
    var sum: Float = 0
    for i in 0..<count { sum += channel[i] * channel[i] }
    let rms = sqrt(sum / Float(count))
    let db = 20 * log10(max(rms, 0.000_01))           // about -100 … 0
    let scaled = Double(min(max((db + 50) / 4, -2), 10)) // Android-like -2 … 10
    let now = Date()
    if now.timeIntervalSince(lastLevelSent) > 0.08 {
      lastLevelSent = now
      sendVoice("onLevel", scaled)
    }
  }

  private func restartSilenceTimer(seconds: TimeInterval) {
    silenceTimer?.invalidate()
    silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
      self?.finishListening()
    }
  }

  /// "Tap when you're done" or a pause after speaking.
  private func finishListening() {
    guard !finished else { return }
    if lastTranscript.isEmpty {
      finished = true
      cleanUpAudio()
      sendVoice("onEnd", nil)
      sendVoice("onError", "nothing")
    } else {
      complete()
    }
  }

  private func complete() {
    guard !finished else { return }
    finished = true
    let text = lastTranscript
    cleanUpAudio()
    sendVoice("onEnd", nil)
    sendVoice("onFinal", text)
  }

  private func cancelListening() {
    finished = true
    cleanUpAudio()
  }

  private func cleanUpAudio() {
    silenceTimer?.invalidate()
    silenceTimer = nil
    if audioEngine.isRunning { audioEngine.stop() }
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionRequest = nil
    recognitionTask = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Files

  private func shareFile(name: String, data: Data, result: @escaping FlutterResult, doneLabel: String?) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    do { try data.write(to: url, options: .atomic) } catch {
      result(FlutterError(code: "WRITE_FAILED", message: "Could not save the file.", details: nil)); return
    }
    guard let top = topViewController() else {
      result(FlutterError(code: "NO_SCREEN", message: "Could not save the file.", details: nil)); return
    }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = top.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
    sheet.completionWithItemsHandler = { _, completed, _, error in
      if let error = error {
        result(FlutterError(code: "SHARE_FAILED", message: error.localizedDescription, details: nil))
      } else if completed {
        result(doneLabel ?? name)
      } else {
        result(FlutterError(code: "CANCELLED", message: "Not saved.", details: nil))
      }
    }
    top.present(sheet, animated: true)
  }

  // MARK: - Travel documents

  private func selectDocument(result: @escaping FlutterResult) {
    guard documentResult == nil else {
      result(FlutterError(code: "ALREADY_PICKING", message: "Picker already open", details: nil))
      return
    }
    let types: [UTType] = [.pdf, .jpeg, .png, .webP]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    guard let viewController = topViewController() else {
      result(FlutterError(code: "PICKER_UNAVAILABLE", message: "Cannot open document picker", details: nil))
      return
    }
    documentResult = result
    viewController.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentResult?(nil)
    documentResult = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = documentResult else { return }
    documentResult = nil
    guard let url = urls.first else { result(nil); return }
    let secured = url.startAccessingSecurityScopedResource()
    defer { if secured { url.stopAccessingSecurityScopedResource() } }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if (values.fileSize ?? 0) > maximumDocumentSize {
        throw NSError(domain: "OneSpace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document exceeds 10 MB"])
      }
      let data = try Data(contentsOf: url)
      guard data.count <= maximumDocumentSize else {
        throw NSError(domain: "OneSpace", code: 2, userInfo: [NSLocalizedDescriptionKey: "Document exceeds 10 MB"])
      }
      result(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)])
    } catch {
      result(FlutterError(code: "DOCUMENT_READ_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  // MARK: - Contacts (no Contacts permission needed: the person picks/confirms in Apple's UI)

  private func pickContact(result: @escaping FlutterResult) {
    guard contactResult == nil, let top = topViewController() else {
      result(FlutterError(code: "PICKER_UNAVAILABLE", message: "Contact picker unavailable", details: nil)); return
    }
    contactResult = result
    let picker = CNContactPickerViewController()
    picker.delegate = self
    top.present(picker, animated: true)
  }

  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    contactResult?(nil)
    contactResult = nil
  }

  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    guard let result = contactResult else { return }
    contactResult = nil
    let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
    var fields: [String: String] = ["person": String(name.prefix(180))]
    if let phone = contact.phoneNumbers.first?.value.stringValue { fields["phone"] = phone }
    if let email = contact.emailAddresses.first?.value as String? { fields["email"] = email }
    if let postal = contact.postalAddresses.first?.value {
      fields["address"] = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
        .replacingOccurrences(of: "\n", with: ", ")
    }
    if !contact.organizationName.isEmpty { fields["company"] = contact.organizationName }
    if !contact.jobTitle.isEmpty { fields["role"] = contact.jobTitle }
    if let site = contact.urlAddresses.first?.value as String? { fields["website"] = site }
    result(fields)
  }

  private func saveContact(_ f: [String: Any], result: @escaping FlutterResult) {
    guard let top = topViewController() else {
      result(FlutterError(code: "UNAVAILABLE", message: "Contacts unavailable", details: nil)); return
    }
    func s(_ k: String) -> String { (f[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    let c = CNMutableContact()
    let parts = s("person").split(separator: " ", maxSplits: 1).map(String.init)
    c.givenName = parts.first ?? ""
    if parts.count > 1 { c.familyName = parts[1] }
    if !s("phone").isEmpty { c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: s("phone")))] }
    if !s("email").isEmpty { c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: s("email") as NSString)] }
    if !s("address").isEmpty {
      let a = CNMutablePostalAddress(); a.street = s("address")
      c.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: a)]
    }
    c.organizationName = s("company")
    c.jobTitle = s("role")
    if !s("website").isEmpty { c.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: s("website") as NSString)] }
    let editor = CNContactViewController(forNewContact: c)
    editor.contactStore = CNContactStore()
    editor.delegate = self
    let nav = UINavigationController(rootViewController: editor)
    top.present(nav, animated: true)
    result(true)
  }

  func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
    viewController.dismiss(animated: true)
  }
}


// R70: closes the Mail composer opened for "Send by email".
extension AppDelegate: MFMailComposeViewControllerDelegate {
  func mailComposeController(_ controller: MFMailComposeViewController,
                             didFinishWith result: MFMailComposeResult, error: Error?) {
    controller.dismiss(animated: true)
  }
}
