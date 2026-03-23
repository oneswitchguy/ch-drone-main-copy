//
//  JoystickCommands.swift
//  CH Drone
//
//  Created by Alex Robinson on 7/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation

final class JoystickCommands {

    enum AxisOption: String, Equatable, Encodable {
        case verticalThrottle
        case pitch
        case roll
        case yaw

        func isEquivalent(to movementType: MovementType) -> Bool {
            switch movementType {
            case .up, .down:
                return self == .verticalThrottle
            case .pitchForward, .pitchBackward:
                return self == .pitch
            case .rollLeft, .rollRight:
                return self == .roll
            case .yawLeft, .yawRight:
                return self == .yaw
            }
        }
    }

    let userDefaults: UserDefaults
    let userDefaultsKeyPrefix: String

    @ValueSubject var horizontalAxis: AxisOption? {
        didSet {
            userDefaults.set(horizontalAxis?.rawValue, forKey: Self.horizontalUserDefaultsKey(prefix: userDefaultsKeyPrefix))

            if horizontalAxis != nil && horizontalAxis == verticalAxis {
                verticalAxis = nil
            }
        }
    }

    @ValueSubject var verticalAxis: AxisOption? {
        didSet {
            userDefaults.set(verticalAxis?.rawValue, forKey: Self.verticalUserDefaultsKey(prefix: userDefaultsKeyPrefix))

            if verticalAxis != nil && verticalAxis == horizontalAxis {
                horizontalAxis = nil
            }
        }
    }

    init(userDefaults: UserDefaults = .standard, userDefaultsKeyPrefix: String = "CHDJoystickAxis") {
        self.horizontalAxis = AxisOption(rawValue: userDefaults.string(forKey: Self.horizontalUserDefaultsKey(prefix: userDefaultsKeyPrefix)) ?? "")
        self.verticalAxis = AxisOption(rawValue: userDefaults.string(forKey: Self.verticalUserDefaultsKey(prefix: userDefaultsKeyPrefix)) ?? "")

        self.userDefaults = userDefaults
        self.userDefaultsKeyPrefix = userDefaultsKeyPrefix

        self.initialized = true // hack to make extra sure `didSet` isn't called on `horizontalAxis` and `verticalAxis` until after initialization.
    }

    func controlsState(joystickState: JoystickUIState, movementMultipliers: MovementMultipliers) -> VirtualControlsState {
        switch joystickState {
        case .idle:
            return VirtualControlsState()
        case .active(let location, _):
            let horizontal = horizontalAxis?.virtualControlsState(axisValue: location.x, movementMultipliers: movementMultipliers) ?? VirtualControlsState()
            let vertical = verticalAxis?.virtualControlsState(axisValue: location.y, movementMultipliers: movementMultipliers) ?? VirtualControlsState()
            return horizontal + vertical
        }
    }

    // MARK: - Private

    private static func horizontalUserDefaultsKey(prefix: String) -> String { "\(prefix)Horizontal" }
    private static func verticalUserDefaultsKey(prefix: String) -> String { "\(prefix)Vertical" }

    private let initialized: Bool

}

extension JoystickCommands.AxisOption {

    func movementType(isPositive: Bool) -> MovementType {
        return isPositive ? positiveMovementType : negativeMovementType
    }

    func virtualControlsState(axisValue: CGFloat, movementMultipliers: MovementMultipliers) -> VirtualControlsState {
        let movementType = movementType(isPositive: axisValue > 0)
        let commandValue = movementType.baselineValue * Float(axisValue.magnitude)

        switch movementType {
        case .up, .down:
            return VirtualControlsState(verticalThrottle: commandValue * movementMultipliers.verticalThrottleValue)
        case .pitchForward, .pitchBackward:
            return VirtualControlsState(pitch: commandValue * movementMultipliers.pitchValue)
        case .rollLeft, .rollRight:
            return VirtualControlsState(roll: commandValue * movementMultipliers.rollValue)
        case .yawLeft, .yawRight:
            return VirtualControlsState(yaw: commandValue * movementMultipliers.yawValue)
        }
    }


    private var positiveMovementType: MovementType { movementTypes.0 }
    private var negativeMovementType: MovementType { movementTypes.1 }

    private var movementTypes: (MovementType, MovementType) {
        switch self {
        case .pitch: return (.pitchForward, .pitchBackward)
        case .roll: return (.rollRight, .rollLeft)
        case .yaw: return (.yawRight, .yawLeft)
        case .verticalThrottle: return (.up, .down)
        }
    }

}
