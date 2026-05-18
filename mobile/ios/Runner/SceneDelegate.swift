import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var engine: FlutterEngine?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let engine = FlutterEngine(name: "main")
        engine.run()
        GeneratedPluginRegistrant.register(with: engine)
        self.engine = engine

        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }
}
