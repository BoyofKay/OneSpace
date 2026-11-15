import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Cold start from the "Voice command" quick action (long-press the icon).
    if connectionOptions.shortcutItem?.type == AppDelegate.voiceShortcutType {
      AppDelegate.shared?.handleVoiceShortcut()
    }
  }

  override func windowScene(_ windowScene: UIWindowScene,
                            performActionFor shortcutItem: UIApplicationShortcutItem,
                            completionHandler: @escaping (Bool) -> Void) {
    if shortcutItem.type == AppDelegate.voiceShortcutType {
      AppDelegate.shared?.handleVoiceShortcut()
      completionHandler(true)
      return
    }
    super.windowScene(windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }
}
