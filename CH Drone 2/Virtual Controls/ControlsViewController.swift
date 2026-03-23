//
//  ControlsViewController.swift
//  CH Drone
//
//  Created by Alex Robinson on 16/11/21.
//

import Combine
import DJIUXSDKBeta
import UIKit

/// A grid of controls accessibility-grouped by row.
///
/// Two methods of input are posible on each row:
///
/// 1. Game control / hardware keyboard mapping.
/// 2. On-screen button presses.
///
/// 1's events come through from the view model. The view model should be told
/// which row has focus so it can action the appropriate command for a key/
/// button press.
///
/// While no commands are active, AX focus should alternate between rows.
/// While commands are active, AX focus should stick to the current row.
///
/// 2's events come from the view controller. Touch down and touch up events
/// on each button should be sent to the view model.
///
final class ControlsViewController: UIViewController {

    let viewModel: FlightViewModel

    var focusedRow: CommandPair.Position? {
        children
            .map(\.viewIfLoaded)
            .enumerated()
            .map { offset, element -> (CommandPair.Position, UIView?) in
                (offset == 0 ? \.upper : \.lower, element)
            }
            .first { position, element in element?.accessibilityElementIsFocused() == true }
            .map { position, _ in position }
    }

    init(viewModel: FlightViewModel) {
        self.viewModel = viewModel

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    // MARK: - UIViewController

    override func loadView() {
        view = UIView()

        view.addSubview(stackView)

        view.addSubview(controlSettingsStack)
        controlSettingsStack.translatesAutoresizingMaskIntoConstraints = false
        controlSettingsStack.axis = .horizontal

        NSLayoutConstraint.activate([
            view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: stackView.topAnchor),
            view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            view.safeAreaLayoutGuide.centerXAnchor.constraint(equalTo: stackView.centerXAnchor),
            virtualControlsStack.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 16),

            view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: controlSettingsStack.trailingAnchor, constant: 16),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: controlSettingsStack.bottomAnchor, constant: 16),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let viewModel = viewModel

        setupFlightStatePanel()

        let rowVCs = [upperRowVC, lowerRowVC]
        rowVCs.forEach { rowVC in
            let wrapper = UIView()
            stackView.addArrangedSubview(wrapper)
            embedChild(rowVC, in: wrapper)
        }

        let multipliersRowWrapper = UIView()
        stackView.addArrangedSubview(multipliersRowWrapper)
        embedChild(multipliersRowVC, in: multipliersRowWrapper, margins: NSDirectionalEdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))

        stackView.addArrangedSubview(joystickAxisAssignmentRowContainer)

        viewModel.$accessibilityFocus
            .receiveOnMain()
            .sink { [weak self] position in
                self?.focus(position: position)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.updateAccessibilityConfiguration()
            }
            .store(in: &cancellables)

        viewModel.userDefaults.publisher(for: \.isCustomScanningEnabled)
            .dropFirst()
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.updateAccessibilityConfiguration()
            }
            .store(in: &cancellables)

        viewModel.$isGamePadConnected
            .dropFirst()
            .receiveOnMain()
            .sink { [weak self] _ in
                self?.updateAccessibilityConfiguration()
            }
            .store(in: &cancellables)

        viewModel.joystickCommands.$verticalAxis.removeDuplicates()
            .merge(with: viewModel.joystickCommands.$horizontalAxis.removeDuplicates())
            .replaceOutputWithVoid()
            .receiveOnMain()
            .sink { [weak self] in
                guard let self else { return }
                self.joystickAxisAssignmentRowContainer.subviews.forEach { $0.removeFromSuperview() }
                self.joystickAxisAssignmentRowContainer.embedSubview(self.makeJoystickAxisAssignmentRow())
                UIAccessibility.post(notification: .layoutChanged, argument: nil)
            }
            .store(in: &cancellables)

        viewModel.isAutomaticReturnToHomeCountdownActiveDriver
            .sink { [weak self] isCountDownActive in
                if isCountDownActive {
                    self?.presentAutomaticReturnToHomeCountdown()
                } else {
                    self?.dismissAutomaticReturnToHomeCountdown()
                }
            }
            .store(in: &cancellables)

        viewModel.$automaticReturnToHomeCountdownTime
            .compactMap { $0 }
            .sink { [weak self] timeRemaining in
                self?.updateAutomaticReturnHomeCountdownAlert(timeRemaining: timeRemaining)
            }
            .store(in: &cancellables)

        virtualControlsStack.spacing = 16
        virtualControlsLabel.text = NSLocalizedString("App Control", comment: "")
        virtualControlsSwitch.onTintColor = .systemGreen
        virtualControlsSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.viewModel.setVirtalStickModeEnabled(self.virtualControlsSwitch.isOn)
        }, for: .valueChanged)

        viewModel.$isVirtualStickModeEnabled
            .receiveOnMain()
            .sink { [weak self] setting in
                switch setting {
                case .value(let enabled):
                    self?.virtualControlsSwitch.isEnabled = true
                    self?.virtualControlsSwitch.setOn(enabled, animated: true)
                    
                case .pendingValue(_, let newValue):
                    self?.virtualControlsSwitch.isEnabled = false
                    self?.virtualControlsSwitch.setOn(newValue, animated: true)
                    
                case .failed(let oldValue, _, _):
                    self?.virtualControlsSwitch.isEnabled = true
                    self?.virtualControlsSwitch.setOn(oldValue, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.async {
            self.updateAccessibilityConfiguration()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled: Bool

        if let key = presses.first?.key {
            handled = activate(key: key)
        } else {
            handled = false
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled: Bool

        if let key = presses.first?.key {
            handled = deactivate(key: key)
        } else {
            handled = false
        }

        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled: Bool

        if let key = presses.first?.key {
            handled = deactivate(key: key)
        } else {
            handled = false
        }

        if !handled {
            super.pressesCancelled(presses, with: event)
        }
    }

    // MARK: - Private stored properties

    private lazy var upperRowVC = makeRowViewController(position: \.upper)
    private lazy var lowerRowVC = makeRowViewController(position: \.lower)
    private lazy var multipliersRowVC = makeMultipliersRowViewController()
    private lazy var joystickAxisAssignmentRowContainer = UIView()

    private lazy var virtualControlsLabel = UILabel()
    private lazy var virtualControlsSwitch = UISwitch(frame: .zero)
    private lazy var virtualControlsStack = UIStackView(arrangedSubviews: [virtualControlsLabel, virtualControlsSwitch])

    private lazy var controlSettingsStack = UIStackView(arrangedSubviews: [virtualControlsStack])
        .assigning(\.spacing, to: 20)
        .assigning(\.distribution, to: .equalSpacing)

    private var cancellables: [AnyCancellable] = []

    private lazy var stackView = UIStackView(arrangedSubviews: [])
        .configure { stackView in
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.distribution = .fill
            stackView.spacing = 0
            stackView.axis = .vertical
        }

    private lazy var aircraftStateControlsStackView: UIStackView = {
        let stack = UIStackView()
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.isAccessibilityElement = false
        stack.accessibilityContainerType = .semanticGroup
        return stack
    }()

    private weak var cancelAutomaticReturnHomeAlert: UIAlertController?

    let returnHomeCountdownFormatter = DateComponentsFormatter()
        .assigning(\.allowedUnits, to: .second)
        .assigning(\.unitsStyle, to: .short)

}

// MARK: - Private

private extension ControlsViewController {

    func setupFlightStatePanel() {
        let wrapper = UIView()
        stackView.addArrangedSubview(wrapper)

        let configuration = DUXBetaPanelWidgetConfiguration(type: .freeform, variant: .freeform)
            .configureColors(background: .uxsdk_clear())

        let panelWidget = DUXBetaFreeformPanelWidget()
        _ = panelWidget.configure(configuration)

        panelWidget.install(in: self, insideSubview: wrapper)
        wrapper.embedSubview(panelWidget.view, margins: NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

        NSLayoutConstraint.activate([
            panelWidget.view.heightAnchor.constraint(equalToConstant: 44)
        ])

        let visionWidget = CHDBetaVisionWidget().configure {
            // Hack this widget into something slightly accessible
            $0.view.isAccessibilityElement = true
            $0.view.accessibilityTraits.insert(.button)
            // and make it present our UI on tap
            $0.tapGestureRecognizer.addTarget(self, action: #selector(showObstacleAvoidanceSettings(gesture:)))
        }

        let widgets = [
            StartStopMotorsWidget(),
            TakeOffWidget(),
            ReturnHomeWidget(),
            visionWidget,
        ]

        let newPanes = panelWidget.splitPane(panelWidget.rootPane(), along: .horizontal, proportions: Array(repeating: 1 / Double(widgets.count + 2), count: widgets.count + 2))

        widgets.enumerated().forEach { i, widget in
            widget.install(in: panelWidget, pane: newPanes[i + 1], position: .centered)
        }
    }

    @objc func showObstacleAvoidanceSettings(gesture: UITapGestureRecognizer) {
        guard let avoidanceState = viewModel.avoidanceState else {
            return
        }

        guard let sourceView = gesture.view else {
            return
        }

        let vc = ObstacleAvoidanceStateViewController(avoidanceState: avoidanceState)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .popover
        nav.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        nav.popoverPresentationController?.sourceView = sourceView
        nav.popoverPresentationController?.sourceRect = sourceView.bounds
        present(nav, animated: true, completion: nil)
    }

}

// MARK: - Private: Keyboard Handling

private extension ControlsViewController {

    func handleKeyboardEvent(key: UIKey, active: Bool) -> Bool {
        switch key.keyCode {
        case .keyboardA:
            viewModel.setKeyState(keyDown: active, column: 0)
            return true
        case .keyboardS:
            viewModel.setKeyState(keyDown: active, column: 1)
            return true
        case .keyboardD:
            viewModel.setKeyState(keyDown: active, column: 2)
            return true
        case .keyboardF:
            viewModel.setKeyState(keyDown: active, column: 3)
            return true
        default:
            return false
        }
    }

    func activate(key: UIKey) -> Bool {
        handleKeyboardEvent(key: key, active: true)
    }

    func deactivate(key: UIKey) -> Bool {
        handleKeyboardEvent(key: key, active: false)
    }

}

// MARK: - Private: Control Rows

private extension ControlsViewController {

    func makeRowViewController(position: CommandPair.Position) -> ControlRowViewController {
        let commands = viewModel.commandGrid.pairs.map { $0[keyPath: position] }

        let cells = commands.enumerated().map { column, command in
            ControlRowViewController.ControlCell(
                command: command,
                driver: viewModel.commandStateDriver(
                    position: position,
                    column: column
                )
            ) { [weak self] cellActive in
                self?.viewModel.setKeyState(keyDown: cellActive, position: position, column: column)
            }
        }

        let rowVC = ControlRowViewController(row: .init(
            accessibilityID: position.description,
            accessibilityLabel: "\(position) Control Row",
            cells: cells
        ))

        return rowVC
    }

    func makeMultipliersRowViewController() -> StackViewController {
        let viewModel = viewModel
        let vc = StackViewController(axis: .horizontal, spacing: 10, distribution: .fillEqually, margins: .init(top: 0, leading: 10, bottom: 0, trailing: 10))

        let cells = [
            MultiplierCellViewController(driver: Just(viewModel.movementMultipliers).map(\.verticalThrottle).eraseToAnyPublisher(), changeHandler: { verticalThrottle in
                viewModel.movementMultipliers.verticalThrottle = verticalThrottle
            }),
            MultiplierCellViewController(driver: Just(viewModel.movementMultipliers).map(\.pitch).eraseToAnyPublisher(), changeHandler: { pitch in
                viewModel.movementMultipliers.pitch = pitch
            }),
            MultiplierCellViewController(driver: Just(viewModel.movementMultipliers).map(\.roll).eraseToAnyPublisher(), changeHandler: { roll in
                viewModel.movementMultipliers.roll = roll
            }),
            MultiplierCellViewController(driver: Just(viewModel.movementMultipliers).map(\.yaw).eraseToAnyPublisher(), changeHandler: { yaw in
                viewModel.movementMultipliers.yaw = yaw
            }),
        ]

        cells.forEach(vc.addArrangedChild(_:))

        vc.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        return vc
    }

    func makeJoystickAxisAssignmentRow() -> UIView {
        let viewModel = viewModel

        let options: [JoystickCommands.AxisOption] = [.verticalThrottle, .pitch, .roll, .yaw]

        struct CommandTypeViewState {
            var option: JoystickCommands.AxisOption
            var axis: KeyPath<JoystickCommands, JoystickCommands.AxisOption?>?
            var onSelection: ((ReferenceWritableKeyPath<JoystickCommands, JoystickCommands.AxisOption?>) -> Void)?
        }

        let currentHorizontalAxis = viewModel.joystickCommands.horizontalAxis
        let currentVerticalAxis = viewModel.joystickCommands.verticalAxis

        func axisKeyPath(for option: JoystickCommands.AxisOption) -> KeyPath<JoystickCommands, JoystickCommands.AxisOption?>? {
            if currentHorizontalAxis == option {
                return \.horizontalAxis
            } else if currentVerticalAxis == option {
                return \.verticalAxis
            } else {
                return nil
            }
        }

        let states: [CommandTypeViewState] = options.map { option in
            let keyPath = axisKeyPath(for: option)
            return CommandTypeViewState(option: option, axis: keyPath, onSelection: { axisOption in
                if viewModel.joystickCommands[keyPath: axisOption] == option {
                    viewModel.joystickCommands[keyPath: axisOption] = nil
                } else {
                    viewModel.joystickCommands[keyPath: axisOption] = option
                }
            })
        }

        let buttons: [UIButton] = states.map { viewState in
            var title: String {
                if let activeAxis = viewState.axis {
                    if activeAxis == \.horizontalAxis {
                        return NSLocalizedString("Horizontal", comment: "")
                    } else {
                        return NSLocalizedString("Vertical", comment: "")
                    }
                } else {
                    return NSLocalizedString("Unassigned", comment: "")
                }
            }

            var image: UIImage? {
                if let activeAxis = viewState.axis {
                    if activeAxis == \.horizontalAxis {
                        return UIImage(systemName: "arrow.left.and.right")
                    } else {
                        return UIImage(systemName: "arrow.up.and.down")
                    }
                } else {
                    return UIImage(systemName: "circle.inset.filled")
                }
            }

            let menu = UIMenu(title: NSLocalizedString("Joystick Axis", comment: ""), image: nil, identifier: nil, options: .displayInline, children: [
                UIAction(title: NSLocalizedString("Horizontal", comment: ""), image: UIImage(systemName: "arrow.left.and.right"), identifier: nil, discoverabilityTitle: nil, attributes: [], state: viewState.axis == \.horizontalAxis ? .on : .off, handler: { action in
                    viewState.onSelection?(\.horizontalAxis)
                }),
                UIAction(title: NSLocalizedString("Vertical", comment: ""), image: UIImage(systemName: "arrow.up.and.down"), identifier: nil, discoverabilityTitle: nil, attributes: [], state: viewState.axis == \.verticalAxis ? .on : .off, handler: { action in
                    viewState.onSelection?(\.verticalAxis)
                }),
            ])

            let isActive = viewState.axis != nil

            var configuration = UIButton.Configuration.filled()
            configuration.title = title
            configuration.image = image
            configuration.imagePadding = 8
            configuration.baseBackgroundColor = isActive ? .systemBlue : .lightGray
            configuration.baseForegroundColor = isActive ? .white : .black

            let button = UIButton(configuration: configuration)
            button.menu = menu
            button.showsMenuAsPrimaryAction = true
            return button
        }

        let stackView = UIStackView(arrangedSubviews: buttons)
            .assigning(\.axis, to: .horizontal)
            .assigning(\.spacing, to: 10)
            .assigning(\.distribution, to: .fillEqually)
            .configure {
                $0.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            }

        let container = UIView()
        container.embedSubview(stackView, usingSafeArea: false, margins: NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        return container
    }

    func updateAccessibilityConfiguration() {
        let isCustomScanningEnabled = viewModel.userDefaults.isCustomScanningEnabled
        let isSwitchControlRunning = viewModel.isSwitchControlRunning

        let shouldUseCustomFocus = isSwitchControlRunning && isCustomScanningEnabled && viewModel.isGamePadConnected

        // disable switch control / voice over buttons when we're using custom focus
        upperRowVC.view.accessibilityElementsHidden = shouldUseCustomFocus
        lowerRowVC.view.accessibilityElementsHidden = shouldUseCustomFocus

        if shouldUseCustomFocus {
            viewModel.enableCustomFocus()
        } else {
            viewModel.disableCustomFocus()
        }

        if !isSwitchControlRunning || !isCustomScanningEnabled || !viewModel.isGamePadConnected {
            focus(position: nil)
        }

        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    func focus(position: CommandPair.Position?) {
        guard let position = position, UIAccessibility.isSwitchControlRunning else {
            upperRowVC.view.backgroundColor = .clear
            lowerRowVC.view.backgroundColor = .clear
            return
        }

        switch position {
        case \.upper:
            upperRowVC.isCustomAccessibilityFocused = true
            lowerRowVC.isCustomAccessibilityFocused = false
        case \.lower:
            upperRowVC.isCustomAccessibilityFocused = false
            lowerRowVC.isCustomAccessibilityFocused = true
        default:
            break
        }

    }

}

// MARK: - Private: Automatic Return To Home

private extension ControlsViewController {

    func presentAutomaticReturnToHomeCountdown() {
        if let cancelAutomaticReturnHomeAlert = cancelAutomaticReturnHomeAlert, cancelAutomaticReturnHomeAlert.isBeingPresented {
            return
        }

        let cancelAutomaticReturnHomeAlert = UIAlertController(
            title: NSLocalizedString("Automatic Return Home Activated", comment: ""),
            message: nil,
            preferredStyle: .alert
        )

        self.cancelAutomaticReturnHomeAlert = cancelAutomaticReturnHomeAlert

        cancelAutomaticReturnHomeAlert.addAction(
            UIAlertAction(
                title: NSLocalizedString("Cancel Auto-RTH", comment: ""),
                style: .default
            ) { [viewModel] action in
                viewModel.cancelAutomaticReturnToHome()
            }
        )

        if let timeRemaining = viewModel.automaticReturnToHomeCountdownTime {
            updateAutomaticReturnHomeCountdownAlert(timeRemaining: timeRemaining)
        }

        present(cancelAutomaticReturnHomeAlert, animated: true)
    }

    func updateAutomaticReturnHomeCountdownAlert(timeRemaining: Int) {
        let localizedFormat = NSLocalizedString(
            "auto-rth-time-remaining",
            value: "Returning home in %@.",
            comment: ""
        )

        let formattedTimeRemaining = returnHomeCountdownFormatter.string(from: DateComponents(second: timeRemaining)) ?? "<unknown>"

        cancelAutomaticReturnHomeAlert?.message = String.localizedStringWithFormat(
            localizedFormat,
            formattedTimeRemaining
        )
    }

    func dismissAutomaticReturnToHomeCountdown() {
        guard let cancelAutomaticReturnHomeAlert = cancelAutomaticReturnHomeAlert else {
            return
        }

        guard !cancelAutomaticReturnHomeAlert.isBeingDismissed else {
            return
        }

        cancelAutomaticReturnHomeAlert.dismiss(animated: true)
    }

}
