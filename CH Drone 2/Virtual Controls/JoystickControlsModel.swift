//
//  JoystickControlsModel.swift
//  CH Drone
//
//  Created by Alex Robinson on 12/10/2025.
//  Copyright © 2025 Astrocode Pty Ltd. All rights reserved.
//

import Combine
import CoreMotion

final class JoystickControlsModel {

    @ValueSubject private(set) var uiState: JoystickUIState  = .idle
    @ValueSubject private(set) var airPodsMotionState = AirPodsMotionState()

    var interruptionPublisher: AnyPublisher<Void, Never> { interruptionDriver.eraseToAnyPublisher() }
    private let interruptionDriver = PassthroughSubject<Void, Never>()

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        observeHeadphoneMotion()
        headphoneMotionManager.start()
    }

    deinit {
        headphoneMotionManager.stop()
    }

    func joystickMoved(to location: CGPoint, source: JoystickUIState.ControlSource) {
        cancelAirPodsCountdown()

        // Activate if necessary
        if uiState == .idle {
            joystickActivated(source: source)
        }

        // Make sure we're not interfering with an existing joystick input
        guard case .active(_, source) = uiState else {
            return
        }

        // value is regularly sent when the command timer fires
        uiState = .active(location: location, source: source)

        // We can't immediately detect when a physical joystick is released like we can with an on-screen view, so have to use a timer to detect when it's been resting at zero for a period of time.
        if source.isJoystick && location == .zero {
            startGamepadJoystickReleaseTimer()
        } else {
            // Invalidate active gamepad joystick release timer (if any) since we've got a new movement
            releaseGamepadJoystickCancellable = nil
        }
    }

    func joystickReleased() {
        cancelAirPodsCountdown()
        cancelAirPodsMotionTimeout()
        uiState = .idle
        setAirPodsControlling(false)
    }

    func interrupt() {
        cancelAirPodsCountdown()
        cancelAirPodsMotionTimeout()
        interruptionDriver.send()
        uiState = .idle
        setAirPodsControlling(false)
    }

    func engageAirPodsControl() {
        guard airPodsMotionState.isAvailable else {
            return
        }

        guard !airPodsMotionState.isControlling, !airPodsMotionState.isCountingDown else {
            return
        }

        startAirPodsCountdown()
    }

    func interruptNonJoystickControl() {
        guard let source = uiState.source, !source.isJoystick else {
            return
        }

        interrupt()
    }

    func interruptScreenControl() {
        guard uiState.source == .screen else {
            return
        }

        interrupt()
    }

    // MARK: - Private

    private let userDefaults: UserDefaults
    private let airPodsMotionTimeout: TimeInterval = 0.75
    private lazy var headphoneMotionManager = HeadphoneMotionManager(userDefaults: userDefaults)
    private var releaseGamepadJoystickCancellable: AnyCancellable?
    private var airPodsCountdownCancellable: AnyCancellable?
    private var airPodsMotionTimeoutCancellable: AnyCancellable?
    private var cancellables: [AnyCancellable] = []

    private func joystickActivated(source: JoystickUIState.ControlSource) {
        setAirPodsControlling(source == .airPods)
        uiState = .active(location: .zero, source: source)
    }

    private func startGamepadJoystickReleaseTimer() {
        releaseGamepadJoystickCancellable = Timer.publish(every: userDefaults.gamepadJoystickReleaseRestingPeriod, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                guard let self else { return }
                guard let source = uiState.source else { return }
                guard source.isJoystick else { return }
                joystickReleased()
            }
    }

    private func startAirPodsCountdown() {
        var countdownValue = 3
        setAirPodsCountdownValue(countdownValue)

        airPodsCountdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                countdownValue -= 1

                guard countdownValue > 0 else {
                    self.airPodsCountdownCancellable = nil
                    self.setAirPodsCountdownValue(nil)
                    self.headphoneMotionManager.recenter()
                    self.setAirPodsControlling(true)
                    self.uiState = .active(location: .zero, source: .airPods)
                    self.resetAirPodsMotionTimeout()
                    return
                }

                self.setAirPodsCountdownValue(countdownValue)
            }
    }

    private func cancelAirPodsCountdown() {
        airPodsCountdownCancellable = nil
        setAirPodsCountdownValue(nil)
    }

    private func resetAirPodsMotionTimeout() {
        airPodsMotionTimeoutCancellable = Timer.publish(every: airPodsMotionTimeout, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                self?.handleAirPodsMotionTimeout()
            }
    }

    private func cancelAirPodsMotionTimeout() {
        airPodsMotionTimeoutCancellable = nil
    }

    private func setAirPodsCountdownValue(_ countdownValue: Int?) {
        var state = airPodsMotionState
        state.countdownValue = countdownValue
        airPodsMotionState = state
    }

    private func observeHeadphoneMotion() {
        headphoneMotionManager.$isDeviceConnected
            .receiveOnMain()
            .sink { [weak self] isConnected in
                self?.handleHeadphoneConnectionChanged(isConnected: isConnected)
            }
            .store(in: &cancellables)

        headphoneMotionManager.motionPublisher
            .receiveOnMain()
            .sink { [weak self] location in
                self?.handleHeadphoneMotion(location)
            }
            .store(in: &cancellables)
    }

    private func setAirPodsControlling(_ isControlling: Bool) {
        var state = airPodsMotionState
        state.isControlling = isControlling
        airPodsMotionState = state
    }

    private func setAirPodsAvailable(_ isAvailable: Bool) {
        var state = airPodsMotionState
        state.isAvailable = isAvailable
        airPodsMotionState = state
    }

}

extension JoystickControlsModel {
    func handleHeadphoneConnectionChanged(isConnected: Bool) {
        setAirPodsAvailable(isConnected)

        guard !isConnected else {
            return
        }

        cancelAirPodsCountdown()
        cancelAirPodsMotionTimeout()

        if uiState.source == .airPods {
            interrupt()
        }
    }

    func handleHeadphoneMotion(_ location: CGPoint) {
        setAirPodsAvailable(true)

        guard airPodsMotionState.isControlling else {
            return
        }

        resetAirPodsMotionTimeout()
        uiState = .active(location: location, source: .airPods)
    }

    func handleAirPodsMotionTimeout() {
        guard uiState.source == .airPods else {
            return
        }

        setAirPodsAvailable(false)
        interrupt()
    }
}

private final class HeadphoneMotionManager: ObservableObject {
    private let userDefaults: UserDefaults
    private let motionManager = CMHeadphoneMotionManager()
    private var availabilityTimer: Timer?

    @Published private(set) var isDeviceConnected = false

    let motionPublisher = PassthroughSubject<CGPoint, Never>()

    private var neutralPitch: Double?
    private var neutralYaw: Double?

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func start() {
        immediateConnectionAttempt()

        availabilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDeviceAvailability()
        }
    }

    func stop() {
        availabilityTimer?.invalidate()
        availabilityTimer = nil

        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }

        isDeviceConnected = false
    }

    func recenter() {
        neutralPitch = nil
        neutralYaw = nil
    }

    private func immediateConnectionAttempt() {
        guard motionManager.isDeviceMotionAvailable else {
            isDeviceConnected = false
            return
        }

        startMotionUpdates()
    }

    private func checkDeviceAvailability() {
        if motionManager.isDeviceMotionAvailable {
            if !motionManager.isDeviceMotionActive {
                startMotionUpdates()
            }
        } else {
            isDeviceConnected = false
        }
    }

    private func startMotionUpdates() {
        guard !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }

            if error != nil {
                self.isDeviceConnected = false
                return
            }

            guard let motion else {
                return
            }

            self.isDeviceConnected = true
            self.motionPublisher.send(self.makeJoystickLocation(from: motion))
        }
    }

    private func makeJoystickLocation(from motion: CMDeviceMotion) -> CGPoint {
        let currentPitch = motion.attitude.pitch * 180 / .pi
        let currentYaw = motion.attitude.yaw * 180 / .pi

        if neutralPitch == nil {
            neutralPitch = currentPitch
        }

        if neutralYaw == nil {
            neutralYaw = currentYaw
        }

        let pitch = currentPitch - (neutralPitch ?? 0)
        let yaw = currentYaw - (neutralYaw ?? 0)

        let maxDegrees = 35.0
        let x = CGFloat(max(min(((-yaw) * userDefaults.airPodsYawSensitivity) / maxDegrees, 1), -1))
        let y = CGFloat(max(min((pitch * userDefaults.airPodsPitchSensitivity) / maxDegrees, 1), -1))
        return CGPoint(x: x, y: y)
    }
}
