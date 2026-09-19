//
//  main.swift
//  CH Drone
//
//  Created by Alex Robinson on 5/5/2022.
//

import Foundation
import UIKit

private let isXCTestRunning: Bool = NSClassFromString("XCTest") != nil

private class TestAppDelegate: NSObject, UIApplicationDelegate, WindowSceneConnecting {
    var window: UIWindow?

    func windowSceneDidConnect(window: UIWindow) {
        let vc = UIViewController(nibName: nil, bundle: nil)
        vc.title = "Running Tests…"
        vc.view.backgroundColor = .white

        self.window = window
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
    }
}

private let appDelegateClassName = isXCTestRunning
    ? NSStringFromClass(TestAppDelegate.self)
    : NSStringFromClass(AppDelegate.self)

_ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, appDelegateClassName)
