//
//  CommandGrid.swift
//  CH Drone
//
//  Created by Alex Robinson on 17/11/21.
//

import Foundation

struct CommandGrid {

    var pairs: [CommandPair]

    var activeCommands: [Command] {
        pairs.flatMap(\.commands).filter { $0.state == .active }
    }

    mutating func setActivesToPending() {
        for i in pairs.indices {
            pairs[i].setActivesToPending()
        }
    }

    mutating func setPendingsToActive() {
        for i in pairs.indices {
            pairs[i].setPendingsToActive()
        }
    }

    mutating func setEnabledToInactive() {
        for i in pairs.indices {
            pairs[i].setEnabledToInactive()
        }
    }

    mutating func setDisabledOrInactive(shouldDisable: (Command) -> Bool) {
        for i in pairs.indices {
            pairs[i].setDisabledOrInactive(shouldDisable: shouldDisable)
        }
    }

    func controlsState(multipliers: MovementMultipliers) -> VirtualControlsState {
        let commands = pairs.flatMap(\.commands)

        return VirtualControlsState(
            pitch: commands.map(\.pitch).reduce(0, +) * multipliers.pitchValue,
            roll: commands.map(\.roll).reduce(0, +) * multipliers.rollValue,
            yaw: commands.map(\.yaw).reduce(0, +) * multipliers.yawValue,
            verticalThrottle: commands.map(\.verticalThrottle).reduce(0, +) * multipliers.verticalThrottleValue
        )
    }

}
