//
//  main.swift
//  CH Drone
//
//  Created by Alex Robinson on 5/5/2022.
//

import Foundation
import UIKit

private let isXCTestRunning: Bool = NSClassFromString("XCTest") != nil

private class TestAppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let vc = UIViewController(nibName: nil, bundle: nil)
        vc.title = "Running Tests…"
        vc.view.backgroundColor = .white

        self.window = UIWindow()
        window?.rootViewController = UINavigationController(rootViewController: vc)
        self.window?.makeKeyAndVisible()

        return true
    }
}

private let appDelegateClassName = isXCTestRunning
    ? NSStringFromClass(TestAppDelegate.self)
    : NSStringFromClass(AppDelegate.self)

_ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, appDelegateClassName)
