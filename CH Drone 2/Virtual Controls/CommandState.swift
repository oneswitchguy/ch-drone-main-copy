//
//  CommandState.swift
//  CommandState
//
//  Created by Alex Robinson on 10/8/21.
//

import Foundation

enum CommandState: String, Equatable, Codable {
    case inactive
    case pending
    case active
    case disabled
}

extension CommandState {

    func activeValue(_ value: Float) -> Float {
        switch self {
        case .inactive, .pending, .disabled:
            return 0
        case .active:
            return value
        }
    }

    mutating func togglePendingOrInactive() {
        switch self {
        case .pending, .active, .disabled:
            self = .inactive
        case .inactive:
            self = .pending
        }
    }

}

extension CommandState {

    func value(for movementType: MovementType) -> Float {
        activeValue(movementType.baselineValue)
    }

}
