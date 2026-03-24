//
//  JoystickViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 7/6/2022.
//

import Combine
import Foundation
import UIKit

final class JoystickViewController: UIViewController {

    let viewModel: JoystickControlsModel
    let commands: JoystickCommands

    init(viewModel: JoystickControlsModel, commands: JoystickCommands) {
        self.viewModel = viewModel
        self.commands = commands

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TouchTransparentView().assigning(\.backgroundColor, to: .clear)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        commands.$horizontalAxis
            .combineLatest(commands.$verticalAxis)
            .map { $0.0 == nil && $0.1 == nil }
            .sink { [weak self] isJoystickDisabled in
                self?.thumb.isHidden = isJoystickDisabled
            }
            .store(in: &cancellables)

        viewModel.interruptionPublisher
            .receiveOnMain()
            .sink { [weak self] in
                // interrupt the gesture
                self?.panGestureRecognizer.isEnabled = false
                self?.panGestureRecognizer.isEnabled = true
            }
            .store(in: &cancellables)

        viewModel.$uiState
            .receiveOnMain()
            .sink { [weak self] state in
                guard let self, view.window != nil else { return }
                updateThumbPosition(with: state)
            }
            .store(in: &cancellables)

        viewModel.$airPodsMotionState
            .receiveOnMain()
            .sink { [weak self] state in
                self?.updateThumbAppearance(with: state)
            }
            .store(in: &cancellables)

        panGestureRecognizer.addTarget(self, action: #selector(handlePanGesture(_:)))
        thumb.addGestureRecognizer(panGestureRecognizer)

        airPodsTapGestureRecognizer.addTarget(self, action: #selector(handleAirPodsTap))
        thumb.addGestureRecognizer(airPodsTapGestureRecognizer)

        thumb.isUserInteractionEnabled = true
        thumb.accessibilityLabel = NSLocalizedString("Joystick control", comment: "AX label")
        thumb.accessibilityHint = NSLocalizedString("Tap to start a 3 second AirPods head tracking countdown and recenter. Drag to use touch joystick.", comment: "AX hint")
        thumb.isAccessibilityElement = true
        thumb.accessibilityTraits = [.button, .allowsDirectInteraction]
        thumb.accessibilityActivationHandler = { [weak self] in
            self?.handleAirPodsTap()
            return true
        }

        thumb.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumb)
        thumb.addSubview(airPodsIconView)
        thumb.addSubview(countdownLabel)

        NSLayoutConstraint.activate([
            thumb.widthAnchor.constraint(equalToConstant: 60),
            thumb.widthAnchor.constraint(equalTo: thumb.heightAnchor),
            thumbHorizontalConstraint,
            thumbVerticalConstraint,
            airPodsIconView.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
            airPodsIconView.centerYAnchor.constraint(equalTo: thumb.centerYAnchor),
            countdownLabel.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: thumb.centerYAnchor),
        ])

        updateThumbAppearance(with: viewModel.airPodsMotionState)
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        updateThumbPosition(with: viewModel.uiState)
    }

    // MARK: - Private

    private var cancellables: [AnyCancellable] = []

    private lazy var thumb: JoystickThumbView = JoystickThumbView(frame: .zero)
        .assigning(\.backgroundColor, to: .magenta.withAlphaComponent(0.5))
        .assigning(\.layer.borderColor, to: UIColor.white.cgColor)
        .assigning(\.layer.borderWidth, to: 5)
        .assigning(\.layer.cornerRadius, to: 30)

    private lazy var airPodsIconView: UIImageView = UIImageView(image: UIImage(systemName: "airpodsmax"))
        .assigning(\.translatesAutoresizingMaskIntoConstraints, to: false)
        .assigning(\.tintColor, to: .white)
        .assigning(\.preferredSymbolConfiguration, to: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        .assigning(\.isHidden, to: true)

    private lazy var countdownLabel: UILabel = UILabel()
        .assigning(\.translatesAutoresizingMaskIntoConstraints, to: false)
        .assigning(\.textColor, to: .white)
        .assigning(\.font, to: UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold))
        .assigning(\.textAlignment, to: .center)
        .assigning(\.isHidden, to: true)

    private lazy var thumbHorizontalConstraint = thumb.centerXAnchor.constraint(equalTo: view.centerXAnchor)
    private lazy var thumbVerticalConstraint = thumb.centerYAnchor.constraint(equalTo: view.centerYAnchor)

    private let panGestureRecognizer = UIPanGestureRecognizer()
    private let airPodsTapGestureRecognizer = UITapGestureRecognizer()

    private func updateThumbPosition(with state: JoystickUIState) {
        switch state {
        case .idle:
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                self.thumb.transform = .identity
            } completion: { _ in
                UIAccessibility.post(notification: .layoutChanged, argument: self.thumb)
            }
        case .active(let location, _):
            let translationX = location.x * view.frame.midX
            let translationY = location.y * view.frame.midY * -1 // un-flip the y-axis
            thumb.transform = CGAffineTransform(
                translationX: commands.horizontalAxis == nil ? 0 : translationX,
                y: commands.verticalAxis == nil ? 0 : translationY
            )
        }
    }

    private func updateThumbAppearance(with state: AirPodsMotionState) {
        thumb.backgroundColor = state.isAvailable ? UIColor.systemGreen.withAlphaComponent(0.75) : UIColor.magenta.withAlphaComponent(0.5)
        countdownLabel.text = state.countdownValue.map(String.init)
        countdownLabel.isHidden = state.countdownValue == nil
        airPodsIconView.isHidden = !state.isAvailable || state.countdownValue != nil
    }

    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .possible:
            break
        case .began:
            break
        case .changed:
            let translation = recognizer.translation(in: thumb)

            // The joystick coordinates are y-flipped compared to the view coordinates.
            //
            //         |+1
            //         |      +1
            // --------+--------
            // -1      |
            //       -1|
            let position = CGPoint(
                x: translation.x / view.frame.midX,
                y: translation.y / view.bounds.midY * -1 // flipped y-axis!
            )
            viewModel.joystickMoved(to: position, source: .screen)
        case .ended, .cancelled, .failed:
            viewModel.joystickReleased()
        @unknown default:
            break
        }
    }

    @objc private func handleAirPodsTap() {
        viewModel.engageAirPodsControl()
    }

    func isThumbView(_ candidateView: UIView?) -> Bool {
        guard let candidateView else {
            return false
        }

        return candidateView.isDescendant(of: thumb)
    }

    var accessibilityElementForOrdering: Any {
        thumb
    }

}

private final class JoystickThumbView: UIView {
    var accessibilityActivationHandler: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        accessibilityActivationHandler?() ?? super.accessibilityActivate()
    }
}
