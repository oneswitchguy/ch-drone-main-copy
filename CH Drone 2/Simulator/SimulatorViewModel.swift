//
//  SimulatorViewModel.swift
//  CH Drone
//

import Combine
import Foundation

/// Bridges ``SimulatedFlightController`` to the simulator's scene and readouts.
///
/// The scene is driven straight from the Combine sink at the display rate, while the
/// readouts are throttled — SwiftUI has no reason to lay out a row of numbers sixty times
/// a second, and doing so on an older iPad costs more than the flying does.
@MainActor
final class SimulatorViewModel: ObservableObject {

    let scene = SimulatorScene()

    /// The state the readouts show. Deliberately coarser than the scene's.
    @Published private(set) var displayState: FlightModel.State = .landed

    init(flightController: SimulatedFlightController) {
        self.flightController = flightController

        flightController.$state
            .sink { [weak self] state in
                self?.scene.update(with: state)
            }
            .store(in: &cancellables)

        flightController.$state
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .assign(to: &$displayState)
    }

    // MARK: - Pilot actions

    /// One button, because take-off and landing are never both available.
    var primaryActionTitle: String {
        switch displayState.phase {
        case .landed:
            return NSLocalizedString("simulator-take-off", value: "Take Off", comment: "")
        case .takingOff:
            return NSLocalizedString("simulator-taking-off", value: "Taking Off…", comment: "")
        case .flying:
            return NSLocalizedString("simulator-land", value: "Land", comment: "")
        case .landing:
            return NSLocalizedString("simulator-landing", value: "Landing…", comment: "")
        }
    }

    var isPrimaryActionEnabled: Bool {
        displayState.phase == .landed || displayState.phase == .flying
    }

    func performPrimaryAction() {
        switch displayState.phase {
        case .landed:
            flightController.takeOff()
        case .flying:
            flightController.land()
        case .takingOff, .landing:
            break
        }
    }

    func reset() {
        flightController.reset()
        scene.recentre(on: flightController.state)
    }

    // MARK: - Private

    private let flightController: SimulatedFlightController
    private var cancellables: [AnyCancellable] = []

}
