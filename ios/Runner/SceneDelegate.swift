import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    for context in connectionOptions.urlContexts {
      if !ReadingWidgetOpenInbox.shared.offer(context.url, notify: false) {
        BookOpenInbox.shared.offer(context.url)
      }
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = URLContexts.filter {
      !ReadingWidgetOpenInbox.shared.offer($0.url) && !BookOpenInbox.shared.offer($0.url)
    }
    if !remaining.isEmpty { super.scene(scene, openURLContexts: Set(remaining)) }
  }
}
