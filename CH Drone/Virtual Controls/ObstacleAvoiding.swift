//
//  ObstacleAvoiding.swift
//  CH Drone
//
//  Created by Alex Robinson on 6/2/2022.
//

import DJISDK
import Foundation

protocol ObstacleAvoiding: AnyObject {
    func setUpwardObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?)
    func getUpwardObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void)
    func setHorizontalObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?)
    func getHorizontalObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void)
}

extension DJIRadar: ObstacleAvoiding {

    func setUpwardObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        setUpwardRadarObstacleAvoidanceEnabled(enabled, withCompletion: completion)
    }

    func getUpwardObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        getUpwardRadarObstacleAvoidanceEnabled(completion: completion)
    }

    func setHorizontalObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        setHorizontalRadarObstacleAvoidanceEnabled(enabled, withCompletion: completion)
    }

    func getHorizontalObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        getHorizontalRadarObstacleAvoidanceEnabled(completion: completion)
    }

}

extension DJIFlightAssistant: ObstacleAvoiding {

    func setUpwardObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        setUpwardVisionObstacleAvoidanceEnabled(enabled, withCompletion: completion)
    }

    func getUpwardObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        getUpwardVisionObstacleAvoidanceEnabled(completion: completion)
    }

    func setHorizontalObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        setHorizontalVisionObstacleAvoidanceEnabled(enabled, withCompletion: completion)
    }

    func getHorizontalObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        getHorizontalVisionObstacleAvoidanceEnabled(completion: completion)
    }

}

#if DEBUG
class SimulatedObstacleAvoidance: ObstacleAvoiding {

    func setUpwardObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        completion?(nil)
    }

    func getUpwardObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        completion(true, nil)
    }

    func setHorizontalObstacleAvoidanceEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        completion?(nil)
    }

    func getHorizontalObstacleAvoidanceEnabled(completion: @escaping (Bool, Error?) -> Void) {
        completion(true, nil)
    }

}
#endif
