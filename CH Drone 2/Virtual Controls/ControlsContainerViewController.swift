//
//  ControlsContainerViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 13/1/2022.
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// The layer the flight controls are laid out over — either the live camera feed and DJI
/// widgets, or the simulator.
///
/// The controls stack below `topBarLayoutGuide` in both cases, which is all
/// ``ControlsContainerViewController`` needs to know about what is behind them.
protocol ControlsBackgroundViewController: UIViewController {
    var topBarLayoutGuide: UILayoutGuide { get }
}

final class ControlsContainerViewController: UIViewController, UIGestureRecognizerDelegate {

    let viewModel: FlightViewModel

    init(viewModel: FlightViewModel) {
        self.viewModel = viewModel

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        disengageTapGestureRecognizer.addTarget(self, action: #selector(handleDisengageTap))
        disengageTapGestureRecognizer.cancelsTouchesInView = false
        disengageTapGestureRecognizer.delegate = self
        view.addGestureRecognizer(disengageTapGestureRecognizer)

        // Rebuild the controls UI when a relevant setting changes
        UserDefaults.standard
            .publisher(for: \.videoFeedEnabled)
            .removeDuplicates()
            .receiveOnMain()
            .sink { [weak self] videoFeedEnabled in
                self?.embedChildren(videoFeedEnabled: videoFeedEnabled)
            }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private var cancellables: [AnyCancellable] = []
    private weak var joystickViewController: JoystickViewController?
    private let disengageTapGestureRecognizer = UITapGestureRecognizer()

    private lazy var controlsContainer = UIView()
        .assigning(\.translatesAutoresizingMaskIntoConstraints, to: false)
        .assigning(\.accessibilityContainerType, to: .semanticGroup)

    private lazy var cameraControlsContainer = UIView()
        .assigning(\.translatesAutoresizingMaskIntoConstraints, to: false)
        .assigning(\.accessibilityContainerType, to: .semanticGroup)

    private func embedChildren(videoFeedEnabled: Bool) {
        let flightVC: ControlsBackgroundViewController
        if let simulatedFlightController = viewModel.simulatedFlightController {
            flightVC = SimulatorViewController(
                flightController: simulatedFlightController,
                controlLinkSession: viewModel.controlLinkSession
            )
        } else {
            flightVC = FlightViewController(videoFeedEnabled: videoFeedEnabled)
        }

        let controlsVC = ControlsViewController(viewModel: viewModel)
        let joystickVC = JoystickViewController(viewModel: viewModel.joystickControlsModel, commands: viewModel.joystickCommands)
        joystickViewController = joystickVC

        embedChild(flightVC, in: view)

        setupGimbalOverlay()

        view.addSubview(controlsContainer)
        embedChild(controlsVC, in: controlsContainer)

        embedChild(joystickVC, in: view)

        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            controlsContainer.topAnchor.constraint(equalTo: flightVC.topBarLayoutGuide.bottomAnchor),
        ])

        view.accessibilityElements = [
            joystickVC.accessibilityElementForOrdering,
            controlsContainer as Any,
            cameraControlsContainer as Any,
            flightVC.view as Any,
        ]
    }

    func setupGimbalOverlay() {
        view.addSubview(cameraControlsContainer)

        let stepper = GimbalPitchStepper(
            onTiltUp: { [weak self] in
                self?.viewModel.rotateGimbalPitch(byDegrees: 5)
            },
            onTiltDown: { [weak self] in
                self?.viewModel.rotateGimbalPitch(byDegrees: -5)
            }
        )
        let hostingVC = UIHostingController(rootView: stepper)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        hostingVC.view.backgroundColor = .clear

        addChild(hostingVC)
        cameraControlsContainer.addSubview(hostingVC.view)
        hostingVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            cameraControlsContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cameraControlsContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hostingVC.view.topAnchor.constraint(equalTo: cameraControlsContainer.topAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: cameraControlsContainer.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: cameraControlsContainer.trailingAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: cameraControlsContainer.bottomAnchor),
        ])
    }

    @objc private func handleDisengageTap() {
        viewModel.disengageOnScreenJoystickControl()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let joystickViewController else {
            return true
        }

        return !joystickViewController.isThumbView(touch.view)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

}
