//
//  Aircraft.swift
//  CH Drone
//
//  Created by Alex Robinson on 16/11/21.
//

import DJISDK
import Foundation

protocol Aircraft: AnyObject {
    /// Named to avoid colliding with `DJIAircraft`'s own concrete `flightController`,
    /// which this cannot be a covariant witness for.
    var flightControl: FlightControlling? { get }
    var gimbal: DJIGimbal? { get }
    var obstacleAvoidance: ObstacleAvoiding? { get }
    var landingAssistance: LandingAssisting? { get }
    var model: String? { get }
}

extension DJIAircraft: Aircraft {
    var flightControl: FlightControlling? { flightController }
    var obstacleAvoidance: ObstacleAvoiding? { flightController?.flightAssistant }
    var landingAssistance: LandingAssisting? { flightController?.flightAssistant }
}
