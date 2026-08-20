//
//  FlightModelTests.swift
//  CHDroneTests
//

import XCTest

@testable import CH_Drone_2

final class FlightModelTests: XCTestCase {

    // MARK: - Helpers

    /// Runs the model forward, defaulting to the 10 Hz rate `FlightViewModel` sends at.
    private func advance(
        _ model: inout FlightModel,
        seconds: TimeInterval,
        step: TimeInterval = 0.1,
        command: FlightModel.Command = .hover
    ) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds - 1e-9 {
            model.advance(by: step, command: command)
            elapsed += step
        }
    }

    private func flying(
        position: SIMD3<Double> = .zero,
        velocity: SIMD3<Double> = .zero,
        heading: Double = 0
    ) -> FlightModel {
        FlightModel(state: .init(position: position, velocity: velocity, heading: heading, phase: .flying))
    }

    // MARK: - Ground

    func testLandedAircraftIgnoresCommands() {
        var model = FlightModel()

        advance(&model, seconds: 5, command: .init(forward: 10, right: 10, up: 10, yawRate: 50))

        XCTAssertEqual(model.state.position, .zero)
        XCTAssertEqual(model.state.heading, 0)
        XCTAssertEqual(model.state.phase, .landed)
    }

    // MARK: - Take-off and landing

    func testTakeOffClimbsToTakeOffAltitudeThenHandsOver() {
        var model = FlightModel()

        model.takeOff()
        XCTAssertEqual(model.state.phase, .takingOff)

        advance(&model, seconds: 5)

        XCTAssertEqual(model.state.phase, .flying)
        XCTAssertEqual(model.state.altitude, model.limits.takeOffAltitude, accuracy: 1e-9)
    }

    func testLandingReturnsToTheGround() {
        var model = flying(position: SIMD3(0, 0, 20))

        model.land()
        advance(&model, seconds: 60)

        XCTAssertEqual(model.state.phase, .landed)
        XCTAssertEqual(model.state.altitude, 0, accuracy: 1e-9)
        XCTAssertEqual(model.state.velocity, .zero)
    }

    func testTakeOffIsIgnoredWhileAlreadyFlying() {
        var model = flying(position: SIMD3(0, 0, 30))

        model.takeOff()

        XCTAssertEqual(model.state.phase, .flying)
    }

    // MARK: - Body frame to world frame

    func testForwardAtNorthHeadingMovesNorth() {
        var model = flying()

        advance(&model, seconds: 20, command: .init(forward: 5))

        XCTAssertGreaterThan(model.state.position.y, 0)
        XCTAssertEqual(model.state.position.x, 0, accuracy: 1e-9)
        XCTAssertEqual(model.state.velocity.y, 5, accuracy: 1e-3)
    }

    func testForwardAtEastHeadingMovesEast() {
        var model = flying(heading: 90)

        advance(&model, seconds: 20, command: .init(forward: 5))

        XCTAssertGreaterThan(model.state.position.x, 0)
        XCTAssertEqual(model.state.position.y, 0, accuracy: 1e-9)
    }

    func testRightAtNorthHeadingMovesEast() {
        var model = flying()

        advance(&model, seconds: 20, command: .init(right: 5))

        XCTAssertGreaterThan(model.state.position.x, 0)
        XCTAssertEqual(model.state.position.y, 0, accuracy: 1e-9)
    }

    func testForwardAtWestHeadingMovesWest() {
        var model = flying(heading: -90)

        advance(&model, seconds: 20, command: .init(forward: 5))

        XCTAssertLessThan(model.state.position.x, 0)
    }

    // MARK: - Envelope

    /// The behaviour the ±15 m/s open question is about: the app can ask for 100 m/s, and
    /// the aircraft gives 15. See `docs/dji-virtual-stick-sport-mode.md`.
    func testHorizontalCommandClampsToTheSDKCeiling() {
        var model = flying()

        advance(&model, seconds: 30, command: .init(forward: 100))

        XCTAssertEqual(model.state.groundSpeed, 15, accuracy: 1e-3)
    }

    func testDiagonalCommandClampsTotalSpeedRatherThanEachAxis() {
        var model = flying()

        advance(&model, seconds: 30, command: .init(forward: 15, right: 15))

        XCTAssertEqual(model.state.groundSpeed, 15, accuracy: 1e-3)
    }

    func testVerticalCommandClampsToTheSDKCeiling() {
        var model = flying()

        advance(&model, seconds: 20, command: .init(up: 50))

        XCTAssertEqual(model.state.verticalSpeed, 4, accuracy: 1e-3)
    }

    func testYawCommandClampsToTheSDKCeiling() {
        var model = flying()

        advance(&model, seconds: 10, command: .init(yawRate: 500))

        XCTAssertEqual(model.state.yawRate, 100, accuracy: 1e-3)
    }

    func testClimbStopsAtTheGeofenceCeiling() {
        var model = flying(position: SIMD3(0, 0, 100))

        advance(&model, seconds: 60, command: .init(up: 4))

        XCTAssertEqual(model.state.altitude, model.limits.maximumAltitude, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(model.state.velocity.z, 0)
    }

    func testDescentStopsAtTheGround() {
        var model = flying(position: SIMD3(0, 0, 5))

        advance(&model, seconds: 60, command: .init(up: -4))

        XCTAssertEqual(model.state.altitude, 0, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(model.state.velocity.z, 0)
    }

    // MARK: - Response

    func testVelocityReachesSixtyThreePercentAfterOneTimeConstant() {
        var model = flying()

        advance(&model, seconds: model.limits.horizontalResponse, step: 0.001, command: .init(forward: 10))

        XCTAssertEqual(model.state.velocity.y, 10 * (1 - exp(-1)), accuracy: 1e-3)
    }

    /// Releasing the stick coasts `v · τ` metres, which is where the 1.5 s time constant
    /// comes from — roughly 30 m of braking from Sport-mode top speed.
    func testCoastDistanceMatchesTheTimeConstant() {
        var model = flying(velocity: SIMD3(0, 15, 0))

        advance(&model, seconds: 60, step: 0.001)

        XCTAssertEqual(model.state.position.y, 15 * model.limits.horizontalResponse, accuracy: 0.05)
    }

    /// The send timer is nominally 10 Hz but is not guaranteed to be, so the integration
    /// must not depend on the step size.
    func testVelocityIsIndependentOfStepSize() {
        var coarse = flying()
        var fine = flying()

        coarse.advance(by: 1, command: .init(forward: 10))
        advance(&fine, seconds: 1, step: 0.01, command: .init(forward: 10))

        XCTAssertEqual(coarse.state.velocity.y, fine.state.velocity.y, accuracy: 1e-9)
    }

    func testNonPositiveIntervalsAreIgnored() {
        var model = flying()
        let before = model.state

        model.advance(by: 0, command: .init(forward: 10))
        XCTAssertEqual(model.state, before)

        model.advance(by: -1, command: .init(forward: 10))
        XCTAssertEqual(model.state, before)
    }

    // MARK: - Yaw

    func testHeadingStaysWrapped() {
        var model = flying(heading: 170)

        advance(&model, seconds: 5, step: 0.001, command: .init(yawRate: 90))

        XCTAssertLessThanOrEqual(model.state.heading, 180)
        XCTAssertGreaterThanOrEqual(model.state.heading, -180)
        XCTAssertLessThan(model.state.heading, 0, "should have wrapped past 180 into negative")
    }

    // MARK: - Attitude

    func testAcceleratingForwardPitchesNoseDown() {
        var model = flying()

        model.advance(by: 0.1, command: .init(forward: 15))

        XCTAssertLessThan(model.state.pitch, 0)
        XCTAssertLessThanOrEqual(abs(model.state.pitch), model.limits.maximumTilt)
    }

    func testAcceleratingRightRollsRight() {
        var model = flying()

        model.advance(by: 0.1, command: .init(right: 15))

        XCTAssertGreaterThan(model.state.roll, 0)
        XCTAssertLessThanOrEqual(abs(model.state.roll), model.limits.maximumTilt)
    }

    func testAttitudeLevelsOffAtSteadySpeed() {
        var model = flying()

        advance(&model, seconds: 30, command: .init(forward: 15))

        XCTAssertEqual(model.state.pitch, 0, accuracy: 0.5)
        XCTAssertEqual(model.state.roll, 0, accuracy: 0.5)
    }

    // MARK: - Saturation

    func testSaturationIsFlaggedForOutOfRangeCommands() {
        var model = flying()

        model.noteSaturation(of: .init(forward: 100))
        XCTAssertTrue(model.state.isCommandSaturated)

        model.noteSaturation(of: .init(forward: 10))
        XCTAssertFalse(model.state.isCommandSaturated)
    }

    // MARK: - Reset

    func testResetReturnsToTheTakeOffPoint() {
        var model = flying(position: SIMD3(50, 50, 50), heading: 90)

        model.reset()

        XCTAssertEqual(model.state, .landed)
    }

}
