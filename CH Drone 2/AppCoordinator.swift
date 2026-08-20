//
//  AppCoordinator.swift
//  AppCoordinator
//
//  Created by Alex Robinson on 1/8/21.
//

import Combine
import DJISDK
import Foundation
import UIKit

final class AppCoordinator {

    let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func activate() {
        window.rootViewController = containerViewController
        window.makeKeyAndVisible()

        connectionManager.$registrationState
            .receiveOnMain()
            .sink { state in
                self.handleRegistrationState(state)
            }
            .store(in: &activeObservations)

        connectionManager.$connectionState
            .receiveOnMain()
            .sink { state in
                self.handleConnectionState(state)
            }
            .store(in: &activeObservations)

        state = .registration
        connectionManager.register()
    }

    // MARK: - Private stored properties

    private let containerViewController = ContainerViewController()

    private let connectionManager = ConnectionManager()

    private var activeObservations: [AnyCancellable] = []
    private var stateCancellables: [AnyCancellable] = []

    private var state: State = .initial {
        didSet { transition(to: state, oldState: oldValue) }
    }

}

// MARK: - State

private extension AppCoordinator {

    enum State {
        case initial
        case registration
        case connection
        case controls(Aircraft)

        var isControls: Bool {
            if case .controls = self { return true } else { return false }
        }

        func isSameCase(as other: State) -> Bool {
            switch (self, other) {
            case (.initial, .initial):
                return true
            case (.registration, .registration):
                return true
            case (.connection, .connection):
                return true
            case (.controls, .controls):
                return true
            default:
                return false
            }
        }
    }

    func transition(to state: State, oldState: State) {
        guard !state.isSameCase(as: oldState) else {
            return
        }

        // stop observing any old states
        stateCancellables = []

        switch state {
        case .initial:
            containerViewController.content = ColorViewController(color: .systemBackground)

        case .registration:
            let registrationVC = SetupViewController(nibName: nil, bundle: nil)

            let mergedStatePublisher = Publishers.Merge(
                connectionManager.$registrationState.map(\.setupStatus).compactMap { $0 },
                connectionManager.$downloadState.map(\.setupStatus).compactMap { $0 }
            )

            mergedStatePublisher
                .receiveOnMain()
                .assign(to: \.status, on: registrationVC)
                .store(in: &stateCancellables)

            registrationVC.action = UIAction(title: "Retry", handler: { action in
                self.connectionManager.register()
            })

            containerViewController.content = registrationVC

        case .connection:
            let connectionVC = SetupViewController(nibName: nil, bundle: nil)

            connectionManager.$connectionState
                .receiveOnMain()
                .sink { connectionState in

                    if let status = connectionState.setupStatus {
                        connectionVC.status = status
                    }

                    connectionVC.documentation = connectionState.setupDocumentation

                    switch connectionState {
                    case .disconnected, .unsupported:
                        connectionVC.action = UIAction(title: "Retry", handler: { action in
                            self.connectionManager.connect()
                        })
                    default:
                        connectionVC.action = nil
                    }

                    // Offered while there is no aircraft, which is exactly when someone
                    // would want to practise instead of waiting.
                    connectionVC.secondaryAction = UIAction(
                        title: NSLocalizedString(
                            "practise-without-a-drone",
                            value: "Practise Without a Drone",
                            comment: "Enters the flight simulator from the connection screen"
                        ),
                        handler: { action in
                            self.connectionManager.startSimulation()
                        }
                    )

                }
                .store(in: &stateCancellables)

            containerViewController.content = connectionVC

        case .controls(let product):
            let viewModel = FlightViewModel(product: product)
            containerViewController.content = ControlsContainerViewController(viewModel: viewModel)
        }
    }

    func handleRegistrationState(_ registrationState: ConnectionManager.RegistrationState) {
        switch registrationState {
        case .initial, .failed:
            break
        case .registered:
            // proceed to connection
            state = .connection
            connectionManager.connect()
        }
    }

    func handleConnectionState(_ connectionState: ConnectionManager.ConnectionState) {
        switch connectionState {
        case .initial, .disconnected, .unsupported, .connecting:
            if state.isControls {
                state = .registration
                connectionManager.register()
            }
        case .connected(let aircraft):
            // proceed to controls
            state = .controls(aircraft)
        }
    }

}

private extension ConnectionManager.RegistrationState {

    var setupStatus: String? {
        switch self {
        case .initial:
            return NSLocalizedString("registering", value: "Checking registration…", comment: "")

        case .failed(let error):
            let format = NSLocalizedString(
                "registration-failed",
                value: "Registration Failed: %@",
                comment: ""
            )
            return String.localizedStringWithFormat(format, "\(error)")

        case .registered:
            return nil
        }
    }

}

private extension ConnectionManager.DatabaseDownloadState {

    var setupStatus: String? {
        switch self {
        case .initial:
            return nil

        case .changed(let progress):
            let format = NSLocalizedString(
                "downloading-db",
                value: "Downloading Database Update\n%@",
                comment: ""
            )
            return String.localizedStringWithFormat(format, progress.localizedDescription)
        }
    }

}

private extension ConnectionManager.ConnectionState {

    var setupStatus: String? {
        switch self {
        case .initial:
            return nil

        case .connecting:
            return NSLocalizedString(
                "connecting",
                value: "Waiting for a connection…",
                comment: ""
            )

        case .disconnected:
            return NSLocalizedString(
                "not-connected",
                value: "Not Connected",
                comment: ""
            )

        case .unsupported(let product):
            let format = NSLocalizedString(
                "non-aircraft-connected",
                value: "Non-Aircraft Connected: %@",
                comment: ""
            )
            return String.localizedStringWithFormat(format, product.model ?? "<unknown model>")

        case .connected(let aircraft):
            return NSLocalizedString(
                "aircraft-connected",
                value: "Aircraft Connected: \(aircraft.model ?? "<unknown model>")",
                comment: ""
            )
        }
    }

    var setupDocumentation: String? {
        switch self {
        case .connecting:
            return NSLocalizedString(
                "connection-help",
                value: """
                Connect your obscenely old DJI drone (anything that is compatible with DJI GO 4) and power on the remote controller to enter the flight controls screen.

                Use the command buttons for takeoff, landing, return to home, and directional movement once the aircraft is connected. On screen, the purple joystick supports touch control. If Apple AirPods are connected, a tap starts AirPods head tracking.
                """,
                comment: ""
            )

        case .initial, .disconnected, .unsupported, .connected:
            return nil
        }
    }

}
