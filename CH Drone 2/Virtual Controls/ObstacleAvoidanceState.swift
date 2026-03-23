//
//  RadarState.swift
//  CH Drone
//
//  Created by Alex Robinson on 16/5/2022.
//

import Combine
import Foundation

final class ObstacleAvoidanceState {

    @ValueSubject private(set) var upwardObstacleAvoidanceEnabled: AsyncSetting<Bool> = .value(false)
    @ValueSubject private(set) var horizontalObstacleAvoidanceEnabled: AsyncSetting<Bool> = .value(false)
    @ValueSubject private(set) var landingAssistanceEnabled: AsyncSetting<Bool> = .value(false)

    let obstacleAvoiding: ObstacleAvoiding
    let landingAssisting: LandingAssisting

    init(obstacleAvoiding: ObstacleAvoiding, landingAssisting: LandingAssisting) {
        self.obstacleAvoiding = obstacleAvoiding
        self.landingAssisting = landingAssisting
    }

    /// Asynchronously set whether horizontal radar obstacle avoidance is enabled. Observe `$horizontalObstacleAvoidanceEnabled` for status changes.
    func setHorizontalObstacleAvoidanceEnabled(_ enabled: Bool) {
        horizontalObstacleAvoidanceEnabled.setPendingValue(newValue: enabled)
        obstacleAvoiding.setHorizontalObstacleAvoidanceEnabled(enabled) { [weak self] error in
            if let error = error {
                self?.horizontalObstacleAvoidanceEnabled.setFailed(failedValue: enabled, error: error)
            } else {
                self?.horizontalObstacleAvoidanceEnabled.setValue(enabled)
            }
        }
    }

    /// Asynchronously set whether upward radar obstacle avoidance is enabled. Observe `$upwardObstacleAvoidanceEnabled` for status changes.
    func setUpwardObstacleAvoidanceEnabled(_ enabled: Bool) {
        upwardObstacleAvoidanceEnabled.setPendingValue(newValue: enabled)
        obstacleAvoiding.setUpwardObstacleAvoidanceEnabled(enabled) { [weak self] error in
            if let error = error {
                self?.upwardObstacleAvoidanceEnabled.setFailed(failedValue: enabled, error: error)
            } else {
                self?.upwardObstacleAvoidanceEnabled.setValue(enabled)
            }
        }
    }

    /// Asynchronously set whether landing assistance is enabled. Observe `$landingAssistanceEnabled` for status changes.
    func setLandingAssistanceEnabled(_ enabled: Bool) {
        landingAssistanceEnabled.setPendingValue(newValue: enabled)
        landingAssisting.setLandingProtectionEnabled(enabled, withCompletion: { [weak self] error in
            if let error = error {
                self?.landingAssistanceEnabled.setFailed(failedValue: enabled, error: error)
            } else {
                self?.landingAssistanceEnabled.setValue(enabled)
            }
        })
    }

    func reload() {
        obstacleAvoiding.getHorizontalObstacleAvoidanceEnabled { [weak self] horizontalAvoidanceEnabled, error in
            if let error = error {
                self?.horizontalObstacleAvoidanceEnabled.setFailed(failedValue: horizontalAvoidanceEnabled, error: error)
            } else {
                self?.horizontalObstacleAvoidanceEnabled.setValue(horizontalAvoidanceEnabled)
            }
        }

        obstacleAvoiding.getUpwardObstacleAvoidanceEnabled { [weak self] upwardAvoidanceEnabled, error in
            if let error = error {
                self?.upwardObstacleAvoidanceEnabled.setFailed(failedValue: upwardAvoidanceEnabled, error: error)
            } else {
                self?.upwardObstacleAvoidanceEnabled.setValue(upwardAvoidanceEnabled)
            }
        }

        landingAssisting.getLandingProtectionEnabled { [weak self] landingAssistanceEnabled, error in
            if let error = error {
                self?.landingAssistanceEnabled.setFailed(failedValue: landingAssistanceEnabled, error: error)
            } else {
                self?.landingAssistanceEnabled.setValue(landingAssistanceEnabled)
            }
        }
    }

}
