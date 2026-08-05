//
//  JoystickControlsModelTests.swift
//  CHDroneTests
//
//  Created by Codex on 13/10/2025.
//

import XCTest

@testable import CH_Drone_2

final class JoystickControlsModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var model: JoystickControlsModel!

    override func setUp() async throws {
        defaults = UserDefaults.makeTestDefaults()
        model = JoystickControlsModel(userDefaults: defaults)
    }

    func testHeadphoneDisconnectInterruptsAirPodsControl() {
        model.joystickMoved(to: CGPoint(x: 0.4, y: -0.6), source: .airPods)

        model.handleHeadphoneConnectionChanged(isConnected: false)

        XCTAssertEqual(model.uiState, .idle)
        XCTAssertFalse(model.airPodsMotionState.isControlling)
        XCTAssertFalse(model.airPodsMotionState.isAvailable)
    }

    func testHeadphoneDisconnectCancelsAirPodsCountdown() {
        model.handleHeadphoneConnectionChanged(isConnected: true)
        model.engageAirPodsControl()

        XCTAssertTrue(model.airPodsMotionState.isCountingDown)

        model.handleHeadphoneConnectionChanged(isConnected: false)

        XCTAssertNil(model.airPodsMotionState.countdownValue)
        XCTAssertFalse(model.airPodsMotionState.isControlling)
        XCTAssertEqual(model.uiState, .idle)
    }

    func testHeadphoneMotionIgnoredAfterDisconnectUntilReengaged() {
        model.joystickMoved(to: CGPoint(x: 0.1, y: 0.2), source: .airPods)
        model.handleHeadphoneConnectionChanged(isConnected: false)

        model.handleHeadphoneMotion(CGPoint(x: 0.8, y: 0.8))

        XCTAssertEqual(model.uiState, .idle)
    }

    func testAirPodsMotionTimeoutInterruptsControl() {
        model.joystickMoved(to: CGPoint(x: 0.1, y: 0.2), source: .airPods)

        model.handleAirPodsMotionTimeout()

        XCTAssertEqual(model.uiState, .idle)
        XCTAssertFalse(model.airPodsMotionState.isControlling)
        XCTAssertFalse(model.airPodsMotionState.isAvailable)
    }

    func testAirPodsMotionTimeoutDoesNothingWhenAirPodsInactive() {
        model.joystickMoved(to: CGPoint(x: 0.2, y: 0.3), source: .screen)

        model.handleAirPodsMotionTimeout()

        XCTAssertEqual(model.uiState, .active(location: CGPoint(x: 0.2, y: 0.3), source: .screen))
    }

    func testHeadphoneMotionRestoresAvailabilityWithoutReengagingControl() {
        model.joystickMoved(to: CGPoint(x: 0.1, y: 0.2), source: .airPods)
        model.handleAirPodsMotionTimeout()

        model.handleHeadphoneMotion(CGPoint(x: 0.3, y: 0.4))

        XCTAssertTrue(model.airPodsMotionState.isAvailable)
        XCTAssertEqual(model.uiState, .idle)
        XCTAssertFalse(model.airPodsMotionState.isControlling)
    }

    func testScreenControlStillRequiresFreshTouchAfterDisconnect() {
        model.joystickMoved(to: CGPoint(x: 0.25, y: 0.25), source: .airPods)
        model.handleHeadphoneConnectionChanged(isConnected: false)

        model.joystickMoved(to: CGPoint(x: -0.5, y: 0.75), source: .screen)

        XCTAssertEqual(model.uiState, .active(location: CGPoint(x: -0.5, y: 0.75), source: .screen))
        XCTAssertFalse(model.airPodsMotionState.isControlling)
    }
}
