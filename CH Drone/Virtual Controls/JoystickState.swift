//
//  JoystickState.swift
//  CH Drone
//
//  Created by Alex Robinson on 7/6/2022.
//  Copyright © 2022 Astrocode Pty Ltd. All rights reserved.
//

import Foundation

enum JoystickUIState: Equatable {
    enum ControlSource: Equatable {
        case screen, leftJoystick, rightJoystick, airPods

        var isJoystick: Bool {
            switch self {
            case .screen, .airPods: false
            case .leftJoystick, .rightJoystick: true
            }
        }
    }

    case idle, active(location: CGPoint, source: ControlSource)

    var isActive: Bool { if case .active = self { true } else { false } }

    var source: ControlSource? {
        switch self {
        case .idle: nil
        case .active(_, let source): source
        }
    }
}

struct AirPodsMotionState: Equatable {
    var isAvailable = false
    var isControlling = false
    var countdownValue: Int?

    var isCountingDown: Bool {
        countdownValue != nil
    }
}
