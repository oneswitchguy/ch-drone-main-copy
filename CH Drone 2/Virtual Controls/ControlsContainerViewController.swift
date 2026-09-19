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
import UIKit.UIGestureRecognizerSubclass

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

        // Disengages the moment a finger lands anywhere on the flight screen, not when it lifts.
        // This is the pilot's stop gesture, so it must not wait for the tap to finish.
        disengageTouchGestureRecognizer.touchDownHandler = { [weak self] in
            self?.viewModel.disengageForScreenTouch()
        }
        disengageTouchGestureRecognizer.delegate = self
        view.addGestureRecognizer(disengageTouchGestureRecognizer)

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
    private let disengageTouchGestureRecognizer = TouchDownGestureRecognizer()

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

/// Calls ``touchDownHandler`` for every finger that lands, at the moment it lands, and otherwise
/// stays out of the way.
///
/// `UITapGestureRecognizer` waits for the finger to lift, and both it and a zero-duration
/// `UILongPressGestureRecognizer` fail outright when two fingers land together. This one never
/// recognises: it reports from `touchesBegan` and fails once the last finger lifts, so it never
/// cancels, delays or claims anything else's touches.
private final class TouchDownGestureRecognizer: UIGestureRecognizer {
    var touchDownHandler: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        touchesDown += touches.count
        touchDownHandler?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        touchesLifted(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)

        touchesLifted(touches.count)
    }

    override func reset() {
        super.reset()

        touchesDown = 0
    }

    // MARK: - Private

    private var touchesDown = 0

    private func touchesLifted(_ count: Int) {
        touchesDown -= count

        if touchesDown <= 0 {
            state = .failed
        }
    }
}
