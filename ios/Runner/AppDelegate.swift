import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var documentResult: FlutterResult?
  private let maximumDocumentSize = 10 * 1024 * 1024

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
