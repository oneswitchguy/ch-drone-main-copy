//
//  AppDelegate.swift
//  DroneSwitchControl
//
//  Created by Alex Robinson on 1/8/21.
//

import UIKit
import Sentry
import Logging

final class AppDelegate: UIResponder, UIApplicationDelegate, WindowSceneConnecting {

    var window: UIWindow?
    var coordinator: AppCoordinator?

    private let logger = Logger(label: "app")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        SentrySDK.start { options in
            options.dsn = "https://e2d486aa88c447ad8661c7323d2535cb@o1252098.ingest.sentry.io/6418035"
            options.debug = false
            options.tracesSampleRate = 0
            options.tracesSampler = nil

            #if DEBUG
            options.environment = "debug"
            #else
            #endif
        }

        LoggingSystem.bootstrap { label in
            MultiplexLogHandler([
                StreamLogHandler.standardOutput(label: label),
                SentryLogHandler(label: label),
            ])
        }

        UserDefaults.standard.registerSettingsDefaults()

        return true
    }

    func windowSceneDidConnect(window: UIWindow) {
        // Still held here as well as by the scene delegate, for anything that reaches for the
        // app delegate's window.
        self.window = window

        self.coordinator = AppCoordinator(window: window)
        coordinator?.activate()
    }

    func windowSceneWillResignActive() {
        logResignActiveDiagnostic()
    }

    private func logResignActiveDiagnostic() {
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: "Resign Active")
        SentrySDK.capture(event: event)
    }

}

// MARK: - Scene life cycle

/// The app delegate's side of the scene life cycle, implemented by whichever delegate
/// `main.swift` installs — ``AppDelegate``, or the test host's stand-in.
protocol WindowSceneConnecting {
    func windowSceneDidConnect(window: UIWindow)
    func windowSceneWillResignActive()
}

extension WindowSceneConnecting {
    func windowSceneWillResignActive() {}
}

/// Creates the app's one window when its scene connects, and hands it to the app delegate.
///
/// Apps built with the iOS 27 SDK must adopt the scene life cycle or UIKit terminates them at
/// launch (`_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`). Under it the window
/// can no longer be made in `application(_:didFinishLaunchingWithOptions:)`, and UIKit calls
/// `sceneWillResignActive(_:)` in place of `applicationWillResignActive(_:)`. The
/// `UIApplication` notifications that `AXWatchdog` and `FlightViewModel` observe are still
/// posted.
///
/// Named by `UIApplicationSceneManifest` in Info.plist. Multiple scenes are off, so there is
/// only ever one.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        appDelegate?.windowSceneDidConnect(window: window)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        appDelegate?.windowSceneWillResignActive()
    }

    private var appDelegate: WindowSceneConnecting? {
        UIApplication.shared.delegate as? WindowSceneConnecting
    }

}
