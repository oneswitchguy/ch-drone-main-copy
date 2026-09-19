//
//  ControlLinkSessionTests.swift
//  CHDroneTests
//

import XCTest

@testable import CH_Drone_2

/// Covers which baseline each axis is measured against when the control link turns the
/// app's command into stick deflection. The maths itself is in `MQTTPacketTests`, which also
/// runs on a Mac; this needs the app's own types, so it runs on the iPad.
final class ControlLinkSessionTests: XCTestCase {

    /// Christopher's test workflow for the joystick mover: Pitch Forward held at Medium for a
    /// fixed stick amount, while the on-screen joystick, on yaw at Medium, is pushed fully
    /// left. With the default Fastest of 2, both are half stick.
    func testHeldPitchForwardWithJoystickYaw() {
        let medium: Float = 1
        let state = VirtualControlsState(
            pitch: MovementType.pitchForward.baselineValue * medium,
            roll: 0,
            yaw: MovementType.yawLeft.baselineValue * medium,
            verticalThrottle: 0
        )

        XCTAssertEqual(
            ControlLinkSession.stickDeflection(for: state, fastestMultiplier: 2),
            VirtualControlsState(pitch: 0.5, roll: 0, yaw: -0.5, verticalThrottle: 0)
        )
    }

    /// Every movement at Fastest is full stick in its own direction, so each axis is scaled
    /// by its own baseline and keeps the Mode 2 sign in `docs/control-link-mqtt.md`.
    func testEachMovementAtFastestIsFullStickInItsDirection() {
        let fastest: Float = 2
        let cases: [(MovementType, VirtualControlsState)] = [
            (.pitchForward, VirtualControlsState(pitch: 1)),
            (.pitchBackward, VirtualControlsState(pitch: -1)),
            (.rollRight, VirtualControlsState(roll: 1)),
            (.rollLeft, VirtualControlsState(roll: -1)),
            (.yawRight, VirtualControlsState(yaw: 1)),
            (.yawLeft, VirtualControlsState(yaw: -1)),
            (.up, VirtualControlsState(verticalThrottle: 1)),
            (.down, VirtualControlsState(verticalThrottle: -1)),
        ]

        for (movement, expected) in cases {
            let command = movement.baselineValue * fastest
            let state: VirtualControlsState
            switch movement {
            case .pitchForward, .pitchBackward: state = VirtualControlsState(pitch: command)
            case .rollLeft, .rollRight: state = VirtualControlsState(roll: command)
            case .yawLeft, .yawRight: state = VirtualControlsState(yaw: command)
            case .up, .down: state = VirtualControlsState(verticalThrottle: command)
            }

            XCTAssertEqual(ControlLinkSession.stickDeflection(for: state, fastestMultiplier: fastest), expected, "\(movement)")
        }
    }

}
