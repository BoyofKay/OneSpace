import Flutter
import UIKit
import UniformTypeIdentifiers
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var documentResult: FlutterResult?
  private let maximumDocumentSize = 10 * 1024 * 1024
  private let checklistSpeech = AVSpeechSynthesizer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "onespace/travel_documents",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickDocument" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.selectDocument(result: result)
    }

    let speech = FlutterMethodChannel(
      name: "onespace/checklist_speech",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    speech.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code:"VOICE_UNAVAILABLE",message:"Speech service missing",details:nil))
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
          result(FlutterError(code:"INVALID_TEXT",message:"Invalid checklist text",details:nil))
          return
        }
        let language = arguments["language"] as? String ?? "en"
        let speed = min(max(arguments["rate"] as? Double ?? 1.0, 0.7), 1.4)
        self.checklistSpeech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language) ??
                          AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        self.checklistSpeech.speak(utterance)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    checklistSpeech.stopSpeaking(at: .immediate)
    super.applicationWillResignActive(application)
  }

  private func selectDocument(result: @escaping FlutterResult) {
    guard documentResult == nil else {
      result(FlutterError(code: "ALREADY_PICKING", message: "Picker already open", details: nil))
      return
    }
    let types: [UTType] = [.pdf, .jpeg, .png, .webP]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    // UIScene owns the key window on current iOS versions.
    let activeWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
    guard let viewController = (activeWindow ?? window)?.rootViewController else {
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
        throw NSError(domain: "OneSpace", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Document exceeds 10 MB"])
      }
      let data = try Data(contentsOf: url)
      guard data.count <= maximumDocumentSize else {
        throw NSError(domain: "OneSpace", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Document exceeds 10 MB"])
      }
      result(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)])
    } catch {
      result(FlutterError(code: "DOCUMENT_READ_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}
