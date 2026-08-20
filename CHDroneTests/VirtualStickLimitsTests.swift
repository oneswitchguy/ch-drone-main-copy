//
//  VirtualStickLimitsTests.swift
//  CHDroneTests
//

import XCTest

@testable import CH_Drone_2

/// Covers the two guards added for `docs/virtual-stick-command-scaling.md`: the command
/// clamp in `VirtualControlsState.controlData`, and the bound on the speed multipliers.
final class VirtualStickLimitsTests: XCTestCase {

    private static let multiplierKeys = [
        "CHDSlowestMultiplier",
        "CHDSlowMultiplier",
        "CHDMediumMultiplier",
        "CHDFastMultiplier",
        "CHDFastestMultiplier",
    ]

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.makeTestDefaults()
    }

    override func tearDown() {
        // `makeTestDefaults()` hands back the standard suite, so anything written here
        // would otherwise persist on the device and follow the next run around.
        for key in Self.multiplierKeys {
            defaults.removeObject(forKey: key)
        }
        defaults = nil
        super.tearDown()
    }

    // MARK: - Command clamping

    /// Normal input is well inside the envelope and must pass through untouched. The whole
    /// point of the clamp is that it never fires in ordinary use.
    func testTypicalCommandIsUnchangedByTheClamp() {
        // A full joystick deflection at the Medium multiplier: 0.01 × 1.0 × 1.0.
        let state = VirtualControlsState(pitch: 0.01, roll: 0, yaw: 0, verticalThrottle: 0)

        // `pitch` travels in the `roll` field — see the comment in `controlData`.
        XCTAssertEqual(state.controlData.roll, 1, accuracy: 1e-5)
    }

    func testHorizontalCommandIsClampedToTheSDKCeiling() {
        // Reachable today by typing a large multiplier into the iOS Settings app.
        let state = VirtualControlsState(pitch: 1, roll: 1, yaw: 0, verticalThrottle: 0)

        XCTAssertEqual(state.controlData.roll, VirtualStickLimits.horizontalSpeed)
        XCTAssertEqual(state.controlData.pitch, VirtualStickLimits.horizontalSpeed)
    }

    func testNegativeHorizontalCommandIsClamped() {
        let state = VirtualControlsState(pitch: -1, roll: -1, yaw: 0, verticalThrottle: 0)

        XCTAssertEqual(state.controlData.roll, -VirtualStickLimits.horizontalSpeed)
        XCTAssertEqual(state.controlData.pitch, -VirtualStickLimits.horizontalSpeed)
    }

    func testYawCommandIsClampedToTheSDKCeiling() {
        let state = VirtualControlsState(pitch: 0, roll: 0, yaw: 1, verticalThrottle: 0)

        XCTAssertEqual(state.controlData.yaw, VirtualStickLimits.yawRate)
    }

    /// The vertical range is already the SDK ceiling, so this asserts the clamp did not
    /// change behaviour that was correct.
    func testVerticalCommandStillReachesItsCeiling() {
        let state = VirtualControlsState(pitch: 0, roll: 0, yaw: 0, verticalThrottle: 1)

        XCTAssertEqual(state.controlData.verticalThrottle, VirtualStickLimits.verticalSpeed)
    }

    func testStoppedStateCommandsNothing() {
        let controlData = VirtualControlsState.stopped.controlData

        XCTAssertEqual(controlData.pitch, 0)
        XCTAssertEqual(controlData.roll, 0)
        XCTAssertEqual(controlData.yaw, 0)
        XCTAssertEqual(controlData.verticalThrottle, 0)
    }

    // MARK: - Multiplier bounds

    func testDefaultMultipliersAreUnaffectedByTheBound() {
        XCTAssertEqual(defaults.slowestMultiplier, 0.5)
        XCTAssertEqual(defaults.slowMultiplier, 0.75)
        XCTAssertEqual(defaults.mediumMultiplier, 1)
        XCTAssertEqual(defaults.fastMultiplier, 1.5)
        XCTAssertEqual(defaults.fastestMultiplier, 2)
    }

    func testExcessiveMultiplierIsClampedOnRead() {
        defaults.set(Float(500), forKey: "CHDFastestMultiplier")

        XCTAssertEqual(defaults.fastestMultiplier, MovementMultipliers.allowedRange.upperBound)
    }

    /// The safety-relevant one. A negative multiplier inverts its axis, so "forward" would
    /// fly the aircraft backwards — and the Settings keyboard accepts a minus sign.
    func testNegativeMultiplierIsClampedOnRead() {
        defaults.set(Float(-2), forKey: "CHDFastestMultiplier")

        XCTAssertEqual(defaults.fastestMultiplier, MovementMultipliers.allowedRange.lowerBound)
        XCTAssertGreaterThan(defaults.fastestMultiplier, 0)
    }

    func testZeroMultiplierIsRaisedToTheFloor() {
        defaults.set(Float(0), forKey: "CHDSlowestMultiplier")

        // A speed step that does nothing at all is its own hazard.
        XCTAssertEqual(defaults.slowestMultiplier, MovementMultipliers.allowedRange.lowerBound)
    }

    // MARK: - The two guards together

    /// The end-to-end case the report describes: a large multiplier typed into Settings
    /// must not produce a command the aircraft will refuse.
    func testLargeMultiplierCannotCommandBeyondTheEnvelope() {
        defaults.set(Float(500), forKey: "CHDFastestMultiplier")

        let multiplier = defaults.fastestMultiplier
        let commanded = MovementType.pitchForward.baselineValue * multiplier
        let controlData = VirtualControlsState(pitch: commanded).controlData

        XCTAssertLessThanOrEqual(abs(controlData.roll), VirtualStickLimits.horizontalSpeed)
    }

}
