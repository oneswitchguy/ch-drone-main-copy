//
//  JoystickCommandsTests.swift
//  CHDroneTests
//
//  Created by Alex Robinson on 9/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import XCTest

@testable import CH_Drone

class JoystickCommandsTests: XCTestCase {

    var prefix: String = "Test"
    var defaults: UserDefaults!
    var movementMultipliers: MovementMultipliers!

    override func setUp() async throws {
        defaults = UserDefaults.makeTestDefaults()
        movementMultipliers = MovementMultipliers(persistence: defaults, key: "TestMultipliers")
    }

    func testJoystickCommandsPersistence() throws {
        let defaults = UserDefaults.makeTestDefaults()
        let prefix = "Test"

        // initialize with fresh user defaults and make some changes
        let commands1 = JoystickCommands(userDefaults: defaults, userDefaultsKeyPrefix: prefix)
        commands1.horizontalAxis = .pitch
        commands1.verticalAxis = .pitch
        commands1.horizontalAxis = .yaw
        XCTAssertEqual(commands1.horizontalAxis, .yaw)
        XCTAssertEqual(commands1.verticalAxis, .pitch)

        // initialize with the same user defaults and make sure values are restored correctly.
        let commands2 = JoystickCommands(userDefaults: defaults, userDefaultsKeyPrefix: prefix)
        XCTAssertEqual(commands2.horizontalAxis, .yaw)
        XCTAssertEqual(commands2.verticalAxis, .pitch)
    }

    func testJoystickControlsState() throws {
        let commands = JoystickCommands(userDefaults: defaults, userDefaultsKeyPrefix: prefix)
        commands.horizontalAxis = .pitch
        commands.verticalAxis = .verticalThrottle

        XCTAssertEqual(controlsState(commands: commands, location: .zero), .stopped)
        XCTAssertNotEqual(controlsState(commands: commands, location: CGPoint(x: 1, y: 1)), .stopped)

        XCTAssertGreaterThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: 1, y: 0),
                property: \.pitch),
            0
        )
        XCTAssertLessThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: -1, y: 0),
                property: \.pitch),
            0
        )

        XCTAssertGreaterThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: 0, y: 1),
                property: \.verticalThrottle),
            0
        )
        XCTAssertLessThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: 0, y: -1),
                property: \.verticalThrottle),
            0
        )
    }

    func testRollControlsState() throws {
        let commands = JoystickCommands(userDefaults: defaults, userDefaultsKeyPrefix: prefix)
        commands.horizontalAxis = .roll
        commands.verticalAxis = .yaw

        XCTAssertGreaterThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: 0, y: 1),
                property: \.yaw),
            0
        )
        XCTAssertLessThan(
            controlsStateValue(
                commands: commands,
                location: CGPoint(x: 0, y: -1),
                property: \.yaw),
            0
        )
    }

}

private extension JoystickCommandsTests {
    func controlsState(commands: JoystickCommands, location: CGPoint) -> VirtualControlsState {
        commands.controlsState(
            joystickState: .active(location: location, source: .screen),
            movementMultipliers: movementMultipliers
        )
    }

    func controlsStateValue(commands: JoystickCommands, location: CGPoint, property: KeyPath<VirtualControlsState, Float>) -> Float {
        commands.controlsState(
            joystickState: .active(location: location, source: .screen),
            movementMultipliers: movementMultipliers
        )[keyPath: property]
    }
}
