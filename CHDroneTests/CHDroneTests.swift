//
//  CHDroneTests.swift
//  CHDroneTests
//
//  Created by Alex Robinson on 7/8/21.
//

import XCTest
import DJISDK

@testable import CH_Drone

class CHDroneTests: XCTestCase {

    func testVirtualControlsStateConversion() {
        var controlsState = VirtualControlsState()

        // lower bounds
        controlsState.pitch = -1
        controlsState.roll = -1
        controlsState.yaw = -1
        controlsState.verticalThrottle = -1
        XCTAssertEqual(controlsState.controlData.pitch, -100)
        XCTAssertEqual(controlsState.controlData.roll, -100)
        XCTAssertEqual(controlsState.controlData.yaw, -100)
        XCTAssertEqual(controlsState.controlData.verticalThrottle, -4)

        // upper bounds
        controlsState.pitch = 1
        controlsState.roll = 1
        controlsState.yaw = 1
        controlsState.verticalThrottle = 1
        XCTAssertEqual(controlsState.controlData.pitch, 100)
        XCTAssertEqual(controlsState.controlData.roll, 100)
        XCTAssertEqual(controlsState.controlData.yaw, 100)
        XCTAssertEqual(controlsState.controlData.verticalThrottle, 4)

        // out of bounds (clamp to min/max)
        controlsState.pitch = -100
        controlsState.roll = 10000
        controlsState.yaw = 1.5
        controlsState.verticalThrottle = -1.5
        XCTAssertEqual(controlsState.controlData.pitch, 100) // intentionally backwards!
        XCTAssertEqual(controlsState.controlData.roll, -100) // intentionally backwards!
        XCTAssertEqual(controlsState.controlData.yaw, 100)
        XCTAssertEqual(controlsState.controlData.verticalThrottle, -4)
    }

    func testControlEvents() {
        let button = UIButton(type: .system)

        let receivedAction = expectation(description: "received action")

        button.addAction(UIAction { action in
            receivedAction.fulfill()
        }, for: .touchUpInside)

        button.sendActions(for: .touchUpInside)

        waitForExpectations(timeout: 1) { error in
            if let error = error {
                XCTFail("Timed out: \(error)")
            }
        }
    }

    func testForcingNonZeroValuesUponControlsState() {
        let gridState = VirtualControlsState(pitch: 50)
        let joystickState = VirtualControlsState(pitch: 100, roll: 100, yaw: 0, verticalThrottle: 4)

        XCTAssertEqual(gridState.forcingNonZeroValuesUpon(joystickState), VirtualControlsState(pitch: 50, roll: 100, yaw: 0, verticalThrottle: 4))
        XCTAssertEqual(joystickState.forcingNonZeroValuesUpon(gridState), VirtualControlsState(pitch: 100, roll: 100, yaw: 0, verticalThrottle: 4))
    }

    func testVirtualControlsStateAddition() {
        let gridState = VirtualControlsState(pitch: 45, roll: 35, yaw: 25, verticalThrottle: -1)
        let joystickState = VirtualControlsState(pitch: 50, roll: 40, yaw: 30, verticalThrottle: 4)

        XCTAssertEqual(gridState + joystickState, VirtualControlsState(pitch: 95, roll: 75, yaw: 55, verticalThrottle: 3))
    }

}

class TestAircraft: Aircraft {
    var model: String?
    var flightController: DJIFlightController?
    var obstacleAvoidance: ObstacleAvoiding?
    var landingAssistance: LandingAssisting?
}
