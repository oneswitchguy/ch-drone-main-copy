//
//  CommandPair.swift
//  CH Drone
//
//  Created by Alex Robinson on 26/11/21.
//

import Foundation

extension CommandPair.Position: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case \.upper: return "Upper"
        case \.lower: return "Lower"
        default:
            return "Unknown"
        }
    }

    func next() -> CommandPair.Position {
        switch self {
        case \.upper: return \.lower
        case \.lower: return \.upper
        default:
            return self
        }
    }
}

struct CommandPair {

    typealias WritablePosition = WritableKeyPath<Self, Command>
    typealias Position = KeyPath<Self, Command>

    static let upper: Position = \.upper
    static let lower: Position = \.lower

    // Note: if other positions are added, make sure any instances of `switch position { …` are handled.
    private(set) var upper: Command
    private(set) var lower: Command

    var positions: [WritablePosition] { [\.upper, \.lower] }
    var commands: [Command] { [upper, lower] }

    init(a: Command, b: Command) {
        self.upper = a
        self.lower = b
    }

    init(upper: MovementType, lower: MovementType) {
        self.upper = .init(type: upper)
        self.lower = .init(type: lower)
    }

    func firstPosition(matching predicate: (Command) -> Bool) -> Position? {
        positions.first { keyPath in
            predicate(self[keyPath: keyPath])
        }
    }

    func commandState(for position: Position) -> CommandState {
        switch position {
        case \.upper:
            return upper.state
        case \.lower:
            return lower.state
        default:
            fatalError("Unhandled position: \(position)")
        }
    }

    func movementType(for position: Position) -> MovementType {
        switch position {
        case \.upper:
            return upper.type
        case \.lower:
            return lower.type
        default:
            fatalError("Unhandled position: \(position)")
        }
    }

    mutating func setCommandState(for position: Position, state: CommandState) {
        switch position {
        case \.upper:
            upper.state = state
            deactivateIfNeeded(\.lower, newSiblingState: state)
        case \.lower:
            lower.state = state
            deactivateIfNeeded(\.upper, newSiblingState: state)
        default:
            fatalError("Unhandled position: \(position)")
        }
    }

    mutating func togglePendingOrInactiveIfEnabled(position: Position) {
        var state = self[keyPath: position].state

        guard state != .disabled else {
            return
        }

        state.togglePendingOrInactive()
        setCommandState(for: position, state: state)
    }

    mutating func setDisabledOrInactive(shouldDisable: (Command) -> Bool) {
        upper.state = shouldDisable(upper) ? .disabled : .inactive
        lower.state = shouldDisable(lower) ? .disabled : .inactive
    }

    mutating func setActivesToPending() {
        positions
            .filter { self[keyPath: $0].state == .active }
            .forEach {
                self[keyPath: $0].state = .pending
            }
    }

    mutating func setPendingsToActive() {
        positions
            .filter { self[keyPath: $0].state == .pending }
            .forEach {
                self[keyPath: $0].state = .active
            }
    }

    mutating func setEnabledToInactive() {
        if upper.state != .disabled {
            upper.state = .inactive
        }
        if lower.state != .disabled {
            lower.state = .inactive
        }
    }

    mutating func setAllToDisabled() {
        upper.state = .disabled
        lower.state = .disabled
    }

    var controlsState: VirtualControlsState {
        VirtualControlsState(
            pitch: commands.map(\.pitch).reduce(0, +),
            roll: commands.map(\.roll).reduce(0, +),
            yaw: commands.map(\.yaw).reduce(0, +),
            verticalThrottle: commands.map(\.verticalThrottle).reduce(0, +)
        )
    }


    // MARK: - Private

    private mutating func deactivateIfNeeded(_ keyPath: WritableKeyPath<Self, Command>, newSiblingState: CommandState) {
        switch newSiblingState {
        case .pending, .active:
            // a command became active; deactivate the other one.
            self[keyPath: keyPath].state = .inactive
        case .inactive:
            // a command became inactive; leave the other one as-is.
            break
        case .disabled:
            // a command became disabled; leave the other one as-is.
            break
        }
    }

}
