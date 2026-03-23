//
//  DroneMovement.swift
//  DroneMovement
//
//  Created by Alex Robinson on 10/8/21.
//

import Foundation

enum MovementType: String, Codable, CaseIterable {
    case up
    case down
    case pitchForward
    case pitchBackward
    case rollLeft
    case rollRight
    case yawLeft
    case yawRight

    var isVerticalThrottle: Bool { [.up, .down].contains(self) }
    var isPitch: Bool { [.pitchForward, .pitchBackward].contains(self) }
    var isRoll: Bool { [.rollLeft, .rollRight].contains(self) }
    var isYaw: Bool { [.yawLeft, .yawRight].contains(self) }

    func isEquivalent(to axisOption: JoystickCommands.AxisOption) -> Bool {
        switch self {
        case .up, .down:
            return axisOption == .verticalThrottle
        case .pitchForward, .pitchBackward:
            return axisOption == .pitch
        case .rollLeft, .rollRight:
            return axisOption == .roll
        case .yawLeft, .yawRight:
            return axisOption == .yaw
        }
    }

}

extension MovementType {
    /// Baseline value for the given movement type, attempted to match DJI default controls.
    /// These values get multiplied according to user-defined speed steps or joystick transformations before being sent as command data.
    var baselineValue: Float {
        switch self {
        case .up:
            return 0.25
        case .down:
            return -0.25
        case .pitchForward:
            return 0.01
        case .pitchBackward:
            return -0.01
        case .rollLeft:
            return -0.01
        case .rollRight:
            return 0.01
        case .yawLeft:
            return -0.25
        case .yawRight:
            return 0.25
        }
    }
}

extension MovementType {
    var localizedName: String {
        switch self {
        case .up:
            return NSLocalizedString("Up", comment: "")
        case .down:
            return NSLocalizedString("Down", comment: "")
        case .pitchForward:
            return NSLocalizedString("Pitch Forward", comment: "")
        case .pitchBackward:
            return NSLocalizedString("Pitch Backward", comment: "")
        case .rollLeft:
            return NSLocalizedString("Roll Left", comment: "")
        case .rollRight:
            return NSLocalizedString("Roll Right", comment: "")
        case .yawLeft:
            return NSLocalizedString("Yaw Left", comment: "")
        case .yawRight:
            return NSLocalizedString("Yaw Right", comment: "")

        }
    }
}
