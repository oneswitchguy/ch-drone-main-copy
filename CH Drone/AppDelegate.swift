//
//  AppDelegate.swift
//  DroneSwitchControl
//
//  Created by Alex Robinson on 1/8/21.
//

import UIKit
import Sentry
import Logging

final class AppDelegate: UIResponder, UIApplicationDelegate {

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

        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window

        self.coordinator = AppCoordinator(window: window)
        coordinator?.activate()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        logResignActiveDiagnostic()
    }

    private func logResignActiveDiagnostic() {
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: "Resign Active")
        SentrySDK.capture(event: event)
    }

}
