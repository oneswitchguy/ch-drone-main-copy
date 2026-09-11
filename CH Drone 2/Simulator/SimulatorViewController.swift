//
//  SimulatorViewController.swift
//  CH Drone
//

import SwiftUI
import UIKit

/// Hosts ``SimulatorView`` behind the flight controls.
///
/// Stands in for `FlightViewController` when there is no aircraft, satisfying the same
/// `ControlsBackgroundViewController` contract so `ControlsContainerViewController` can lay
/// the switch grid and joystick out over either one without knowing which it has.
final class SimulatorViewController: UIViewController, ControlsBackgroundViewController {

    init(flightController: SimulatedFlightController, controlLinkSession: ControlLinkSession) {
        self.viewModel = SimulatorViewModel(flightController: flightController)
        self.controlLinkSession = controlLinkSession

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    /// Matches the height of the readout strip in ``SimulatorView``, so the controls stack
    /// below it rather than over the top of it.
    var topBarLayoutGuide: UILayoutGuide {
        loadViewIfNeeded()
        return topBarGuide
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let hostingController = UIHostingController(
            rootView: SimulatorView(viewModel: viewModel, controlLinkSession: controlLinkSession)
        )
        hostingController.view.backgroundColor = .clear
        embedChild(hostingController)

        view.addLayoutGuide(topBarGuide)

        NSLayoutConstraint.activate([
            topBarGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            topBarGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            topBarGuide.heightAnchor.constraint(equalToConstant: Self.topBarHeight),
        ])
    }

    // MARK: - Private

    private let viewModel: SimulatorViewModel
    private let controlLinkSession: ControlLinkSession
    private let topBarGuide = UILayoutGuide()

    private static let topBarHeight: CGFloat = 56

}
