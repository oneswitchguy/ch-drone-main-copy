//
//  AXWatchdog.swift
//  CH Drone
//
//  Created by Alex Robinson on 8/2/2022.
//

import Combine
import Foundation
import Logging
import UIKit

private let axLogger = Logger(label: "accessibility")

/// Checks that Switch Control focus is happening regularly, and if not posts a `layoutChanged` notification.
final class AXWatchdog {

    let interval: TimeInterval

    init(interval: TimeInterval = 3) {
        self.interval = interval

        NotificationCenter.default
            .publisher(for: UIAccessibility.switchControlStatusDidChangeNotification, object: nil)
            .map { _ in UIAccessibility.isSwitchControlRunning }
            .receiveOnMain()
            .sink { [weak self] isSwitchControlRunning in
                guard let self else { return }
                self.isSwitchControlRunning ? self.start() : self.stop()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIAccessibility.elementFocusedNotification, object: nil)
            .receiveOnMain()
            .sink { [weak self] notification in
                guard let self else { return }
                self.lastFocusedElement = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey]
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification, object: nil)
            .receiveOnMain()
            .sink { [weak self] notification in
                self?.stop()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification, object: nil)
            .receiveOnMain()
            .sink { [weak self] notification in
                self?.start()
            }
            .store(in: &cancellables)

        if UIApplication.shared.applicationState == .active {
            start()
        }
    }

    // MARK: - Private

    private func start() {
        guard UIAccessibility.isSwitchControlRunning else { return }

        timerCancellable = Timer.publish(every: interval, tolerance: 0.2, on: .main, in: .common, options: nil)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                if date.timeIntervalSince(self.lastFocusedElementAt) > self.interval {
                    axLogger.info("AX focus not changed recently; posting layoutChanged")
                    UIAccessibility.post(notification: .layoutChanged, argument: nil)
                }
            }
    }

    private func stop() {
        timerCancellable = nil
    }

    private var cancellables: [AnyCancellable] = []
    private var lastFocusedElement: Any? {
        didSet {
            if lastFocusedElement != nil {
                lastFocusedElementAt = Date()
            }
        }
    }

    private var isSwitchControlRunning: Bool = UIAccessibility.isSwitchControlRunning
    private var lastFocusedElementAt: Date = .distantPast

    private var timerCancellable: AnyCancellable?

}
