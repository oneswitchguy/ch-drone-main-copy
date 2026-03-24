//
//  LandingAssisting.swift
//  CH Drone
//
//  Created by Alex Robinson on 6/2/2022.
//

import DJISDK
import Foundation

protocol LandingAssisting: AnyObject {
    func setLandingProtectionEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?)
    func getLandingProtectionEnabled(completion: @escaping (Bool, Error?) -> Void)
}

extension DJIFlightAssistant: LandingAssisting {}

#if DEBUG
class SimulatedLandingAssistance: LandingAssisting {

    private var landingProtectionEnabled: Bool = true

    func setLandingProtectionEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        landingProtectionEnabled = enabled
        completion?(nil)
    }

    func getLandingProtectionEnabled(completion: @escaping (Bool, Error?) -> Void) {
        completion(landingProtectionEnabled, nil)
    }

}
#endif
