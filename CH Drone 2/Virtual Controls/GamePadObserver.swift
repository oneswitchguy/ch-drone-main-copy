//
//  GamePadObserver.swift
//  GamePadObserver
//
//  Created by Alex Robinson on 12/9/21.
//

import Combine
import Foundation
import GameController

final class GamePadObserver {

    enum ConnectionState {
        case notConnected
        case notSupported(GCController)
        case connected(GCController)

        var isConnected: Bool {
            if case .connected = self { return true } else { return false }
        }

        var controller: GCController? {
            switch self {
            case .notConnected, .notSupported:
                return nil
            case .connected(let controller):
                return controller
            }
        }
    }

    @ValueSubject private(set) var connectionState: ConnectionState = .notConnected

    @ValueSubject private(set) var upActive = false
    @ValueSubject private(set) var downActive = false
    @ValueSubject private(set) var leftActive = false
    @ValueSubject private(set) var rightActive = false

    @ValueSubject private(set) var leftThumbstickPosition: CGPoint = .zero
    @ValueSubject private(set) var rightThumbstickPosition: CGPoint = .zero

    var isDirectionActive: AnyPublisher<Bool, Never> {
        $upActive.combineLatest($downActive, $leftActive, $rightActive).map {
            $0.0 || $0.1 || $0.2 || $0.3
        }
        .eraseToAnyPublisher()
    }

    init() {
        updateForConnectedGamePad(GCController.current)

        NotificationCenter.default.publisher(for: .GCControllerDidBecomeCurrent, object: nil)
            .receiveOnMain()
            .sink { [weak self] notification in
                self?.updateForConnectedGamePad(notification.object as? GCController)
            }
            .store(in: &connectionCancellables)


        NotificationCenter.default.publisher(for: .GCControllerDidStopBeingCurrent, object: nil)
            .receiveOnMain()
            .sink { [weak self] notification in
                self?.updateForConnectedGamePad(nil)
            }
            .store(in: &connectionCancellables)

    }

    // MARK: - Private

    private var connectionCancellables: [AnyCancellable] = []

    private func updateForConnectedGamePad(_ controller: GCController?) {
        if let controller = controller {
            if controller.extendedGamepad == nil {
                connectionState = .notSupported(controller)
            } else {
                connectionState = .connected(controller)
            }
        } else {
            connectionState = .notConnected
        }

        updateControlObservers()
    }

    private func updateControlObservers() {
        guard let controller = connectionState.controller, let extendedGamepad = controller.extendedGamepad else {
            upActive = false
            downActive = false
            leftActive = false
            rightActive = false
            leftThumbstickPosition = .zero
            rightThumbstickPosition = .zero
            return
        }

        extendedGamepad.leftThumbstick.valueChangedHandler = { [weak self] dpad, x, y in
            self?.leftThumbstickPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }

        extendedGamepad.rightThumbstick.valueChangedHandler = { [weak self] dpad, x, y in
            self?.rightThumbstickPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }

        // Dpads that aren't the left or right thumbstick
        let buttonPads = extendedGamepad.allDpads.filter {
            $0 != extendedGamepad.leftThumbstick && $0 != extendedGamepad.rightThumbstick
        }

        let perform = { [weak self] (keyPath: WritableKeyPath<GamePadObserver, Bool>, isPressed: Bool) in
            self?[keyPath: keyPath] = isPressed
        }

        for buttonPad in buttonPads {
            buttonPad.up.pressedChangedHandler = { _, _, pressed in perform(\.upActive, pressed) }
            buttonPad.down.pressedChangedHandler = { _, _, pressed in perform(\.downActive, pressed) }
            buttonPad.left.pressedChangedHandler = { _, _, pressed in perform(\.leftActive, pressed) }
            buttonPad.right.pressedChangedHandler = { _, _, pressed in perform(\.rightActive, pressed) }
        }
    }

}
