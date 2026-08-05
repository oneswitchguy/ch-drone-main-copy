//
//  FlightControlling.swift
//  CH Drone
//

import DJISDK
import Foundation

/// The part of `DJIFlightController` that this app actually uses.
///
/// The SDK only ever constructs a `DJIFlightController` for a connected product, so
/// anything standing in for one — a simulated aircraft, a test double — has to go
/// through a protocol. Mirrors `ObstacleAvoiding` and `LandingAssisting`.
protocol FlightControlling: AnyObject {

    var delegate: DJIFlightControllerDelegate? { get set }
    var flightAssistant: DJIFlightAssistant? { get }

    // MARK: - Virtual stick

    var rollPitchControlMode: DJIVirtualStickRollPitchControlMode { get set }
    var rollPitchCoordinateSystem: DJIVirtualStickFlightCoordinateSystem { get set }
    var yawControlMode: DJIVirtualStickYawControlMode { get set }
    var verticalControlMode: DJIVirtualStickVerticalControlMode { get set }

    func setVirtualStickModeEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?)
    func send(_ controlData: DJIVirtualStickFlightControlData, withCompletion completion: DJICompletionBlock?)

    // MARK: - Return to home

    func confirmSmartReturn(toHomeRequest confirmed: Bool, withCompletion completion: DJICompletionBlock?)

}

extension DJIFlightController: FlightControlling {}
