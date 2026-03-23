//
//  Command.swift
//  Command
//
//  Created by Alex Robinson on 10/8/21.
//

import Foundation

struct Command: Codable {

    let type: MovementType
    var state: CommandState = .inactive

    var pitch: Float {
        if [.pitchForward, .pitchBackward].contains(type) {
            return state.value(for: type)
        } else {
            return 0
        }
    }

    var roll: Float {
        if [.rollLeft, .rollRight].contains(type) {
            return state.value(for: type)
        } else {
            return 0
        }
    }

    var yaw: Float {
        if [.yawLeft, .yawRight].contains(type) {
            return state.value(for: type)
        } else {
            return 0
        }
    }

    var verticalThrottle: Float {
        if [.up, .down].contains(type) {
            return state.value(for: type)
        } else {
            return 0
        }
    }

}
