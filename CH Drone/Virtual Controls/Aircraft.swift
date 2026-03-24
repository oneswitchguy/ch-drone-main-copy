//
//  Aircraft.swift
//  CH Drone
//
//  Created by Alex Robinson on 16/11/21.
//

import DJISDK
import Foundation

protocol Aircraft: AnyObject {
    var flightController: DJIFlightController? { get }
    var obstacleAvoidance: ObstacleAvoiding? { get }
    var landingAssistance: LandingAssisting? { get }
    var model: String? { get }
}

extension DJIAircraft: Aircraft {
    var obstacleAvoidance: ObstacleAvoiding? { flightController?.flightAssistant }
    var landingAssistance: LandingAssisting? { flightController?.flightAssistant }
}
