//
//  FlightViewModel.swift
//  CH Drone
//
//  Created by Alex Robinson on 16/11/21.
//

import Combine
import DJISDK
import Foundation
import UXSDKCore
import Logging

private let logger = Logger(label: #fileID)

enum ControlsError: Error {
    case flightControllerUnavailable
}

@objc class ConnectionWatcher: DUXBetaBaseWidgetModel {

    @ValueSubject private(set) var isConnected: Bool = false

    override init() {
        super.init()

        publisher(for: \.isProductConnected).assign(to: &$isConnected)
    }

}

final class FlightViewModel: NSObject {

    let userDefaults: UserDefaults
    let joystickControlsModel: JoystickControlsModel

    @ValueSubject private(set) var error: Error? {
        didSet {
            if error == nil {
                clearErrorCancellable = nil
            } else {
                clearErrorAfterDelay()
            }
        }
    }

    @ValueSubject private(set) var isGamePadConnected = false
    @ValueSubject private(set) var isVirtualStickModeEnabled: AsyncSetting<Bool> = .value(false)
    @ValueSubject private(set) var commandGrid: CommandGrid
    @ValueSubject private(set) var joystickCommands: JoystickCommands
    @ValueSubject private(set) var accessibilityFocus: CommandPair.Position?
    @ValueSubject private(set) var isSwitchControlRunning: Bool = UIAccessibility.isSwitchControlRunning
    @ValueSubject private(set) var avoidanceState: ObstacleAvoidanceState?

    let movementMultipliers: MovementMultipliers

    init(product: Aircraft, userDefaults: UserDefaults = .standard) {
        self.product = product
        self.userDefaults = userDefaults

        self.joystickControlsModel = JoystickControlsModel(userDefaults: userDefaults)

        self.commandGrid = CommandGrid(pairs: [
            .init(upper: .up, lower: .down),
            .init(upper: .pitchForward, lower: .pitchBackward),
            .init(upper: .rollLeft, lower: .rollRight),
            .init(upper: .yawLeft, lower: .yawRight),
        ])

        let joystickCommands = JoystickCommands()
        self.joystickCommands = joystickCommands

        let movementMultipliers = MovementMultipliers(persistence: .standard, key: "CHControlsViewModelMovementMultipliers")
        self.movementMultipliers = movementMultipliers

        self.telemetryLogger = TelemetryLogger(joystickCommands: joystickCommands, movementMultipliers: movementMultipliers)

        super.init()

        observeAircraftConnection(product: product)
        observeGamePad()
        observeJoystickAxisSelection()
        observeJoystickControlsModel()
        observeSwitchControlRunning()
        observeApplicationLifecycle()
    }

    // MARK: - Settings

    /// Async. Observe $isVirtualStickModeEnabled for pending/success/error.
    func setVirtalStickModeEnabled(_ enabled: Bool) {
        guard let flightController = flightController else {
            isVirtualStickModeEnabled.setFailed(failedValue: enabled, error: ControlsError.flightControllerUnavailable)
            return
        }

        isVirtualStickModeEnabled.setPendingValue(newValue: enabled)

        flightController.setVirtualStickModeEnabled(enabled) { [weak self] error in
            if let error = error {
                self?.isVirtualStickModeEnabled.setFailed(failedValue: enabled, error: error)
                self?.error = error
            } else {
                self?.isVirtualStickModeEnabled.setValue(enabled)
            }
        }
    }

    // MARK: - Automatic Return To Home

    @ValueSubject private(set) var automaticReturnToHomeCountdownTime: Int? {
        didSet {
            if automaticReturnToHomeCountdownTime != nil {
                interruptJoystick()
            }
        }
    }

    var isAutomaticReturnToHomeCountdownActive: Bool { automaticReturnToHomeCountdownTime != nil }

    var isAutomaticReturnToHomeCountdownActiveDriver: AnyPublisher<Bool, Never> {
        $automaticReturnToHomeCountdownTime
            .map { $0 != nil }
            .removeDuplicates()
            .receiveOnMain()
            .eraseToAnyPublisher()
    }

    func cancelAutomaticReturnToHome() {
        flightController?.confirmSmartReturn(toHomeRequest: false)
    }

    // MARK: - Accessibility Focus

    func enableCustomFocus() {
        isFocusTimerEnabled = true
        startFocusTimer()
    }

    func disableCustomFocus() {
        isFocusTimerEnabled = false
        stopFocusTimer()
    }

    func disengageOnScreenJoystickControl() {
        joystickControlsModel.interruptScreenControl()
    }

    // MARK: - Button Controls

    // On activation:
    // 1. start an activation threshold timer (e.g. 0.2s)
    // 2. on timer fire, activate the selected command

    // On deactivation:
    // 1. stop the command type.
    // 2. if the activation timer is still running, toggle the control between pending/inactive states.
    // 3. cancel the relevant activation timer.
    func setKeyState(keyDown: Bool, position: CommandPair.Position, column: Int) {
        joystickControlsModel.interrupt()

        if isAutomaticReturnToHomeCountdownActive {
            return
        }

        let isCommandEnabled = commandGrid.pairs[column].commandState(for: position) != .disabled
        let commandTypes = commandGrid.pairs[column]

        let isAssignedToHorizontalJoystick: Bool = {
            if let joystickHorizontalAxis = joystickCommands.horizontalAxis {
                return commandTypes.movementType(for: position).isEquivalent(to: joystickHorizontalAxis)
            } else {
                return false
            }
        }()

        let isAssignedToVerticalJoystick: Bool = {
            if let joystickVerticalAxis = joystickCommands.verticalAxis {
                return commandTypes.movementType(for: position).isEquivalent(to: joystickVerticalAxis)
            } else {
                return false
            }
        }()

        if keyDown {
            // start a timer and wait and see if it's a short/long press
            activationTimerCancellable = Timer.publish(every: userDefaults.minimumLongPressDuration, tolerance: 0.05, on: .main, in: .common, options: nil)
                .autoconnect()
                .first()
                .sink { [weak self] _ in
                    guard let self else { return }

                    self.isCommandTimerActive = false

                    // clear out equivalent joystick controls if we get a long press on something that's assigned to the joystick
                    if isAssignedToHorizontalJoystick {
                        self.joystickCommands.horizontalAxis = nil
                    }

                    if isAssignedToVerticalJoystick {
                        self.joystickCommands.verticalAxis = nil
                    }

                    if isCommandEnabled {
                        self.commandGrid.pairs[column].setCommandState(for: position, state: .active)
                        self.setCommandsActive(active: true)
                    }
                }
        } else if isCommandTimerActive && isCommandEnabled {
            // register short press
            commandGrid.pairs[column].togglePendingOrInactiveIfEnabled(position: position)
            isCommandTimerActive = false
            setCommandsActive(active: false)
        } else {
            // end long press
            releaseCommands()
        }
    }

    /// Iterate through states for the given column
    func setKeyState(keyDown: Bool, column: Int) {
        func nextPosition(after currentPosition: CommandPair.Position?) -> CommandPair.Position? {
            switch currentPosition {
            case \.upper:
                return \.lower
            case \.lower:
                return nil
            default:
                return \.upper
            }
        }

        // Find the current active position
        let currentPosition = commandGrid.pairs[column].firstPosition { command in
            [.pending, .active].contains(command.state)
        }

        if joystickControlsModel.uiState.isActive {
            joystickControlsModel.interrupt()
            return
        }

        if isAutomaticReturnToHomeCountdownActive {
            return
        }

        if let currentPosition = currentPosition, commandGrid.pairs[column].commandState(for: currentPosition) == .disabled {
            return
        }

        if keyDown {
            // start a timer and wait and see if it's a short/long press
            activationTimerCancellable = Timer.publish(every: userDefaults.minimumLongPressDuration, tolerance: 0, on: .main, in: .common, options: nil)
                .autoconnect()
                .first()
                .sink { [weak self] _ in
                    guard let self else { return }
                    if let currentPosition = currentPosition {
                        self.commandGrid.pairs[column].setCommandState(for: currentPosition, state: .active)
                    }
                    self.isCommandTimerActive = false
                    self.setCommandsActive(active: true)
                }
        } else if isCommandTimerActive {
            // register short press
            if let position = nextPosition(after: currentPosition) {
                commandGrid.pairs[column].togglePendingOrInactiveIfEnabled(position: position)
            } else {
                commandGrid.pairs[column].setEnabledToInactive()
            }

            isCommandTimerActive = false
            setCommandsActive(active: false)
        } else {
            // end long press
            releaseCommands()
        }
    }

    private func releaseCommands() {
        isCommandTimerActive = false

        if userDefaults.clearCommandsOnRelease {
            commandGrid.setEnabledToInactive()
            stopSendTimer()
        } else {
            setCommandsActive(active: false)
        }
    }

    private func interruptJoystick() {
        joystickControlsModel.interrupt()
        releaseCommands()
    }

    // MARK: - View State Publisher

    func commandStateDriver(position: CommandPair.Position, column: Int) -> AnyPublisher<CommandState, Never> {
        $commandGrid.map { grid in
            grid.pairs[column][keyPath: position].state
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Private properties

    // monitor AX focus and give it a kick if it might be needed
    private let axWatchdog = AXWatchdog()

    private let product: Aircraft
    private let connectionWatcher = ConnectionWatcher()
    private let gamePad = GamePadObserver()

    private let telemetryLogger: TelemetryLogger

    private var isCommandTimerActive: Bool {
        get { activationTimerCancellable != nil }
        set { activationTimerCancellable = nil }
    }

    private var isFocusTimerEnabled = false

    private var activationTimerCancellable: AnyCancellable?

    private let sendQueue = DispatchQueue(label: "Send Command", qos: .userInteractive)
    private var sendTimerCancellable: AnyCancellable?

    private var focusTimerCancellable: AnyCancellable?
    private var clearErrorCancellable: AnyCancellable?

    private var cancellables: [AnyCancellable] = []

    private var flightController: DJIFlightController? { product.flightController }
    private var obstacleAvoidance: ObstacleAvoiding? { Config.simulatedRadar ?? product.obstacleAvoidance }
    private var landingAssistance: LandingAssisting? { Config.simulatedLandingAssistance ?? product.landingAssistance }

}

// MARK: - DJIFlightControllerDelegate

extension FlightViewModel: DJIFlightControllerDelegate {

    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        let goHomeAssessment = state.goHomeAssessment
        if goHomeAssessment.smartRTHState == .countingDown {
            automaticReturnToHomeCountdownTime = goHomeAssessment.smartRTHCountdown
        } else {
            automaticReturnToHomeCountdownTime = nil
        }
    }

    func flightController(_ fc: DJIFlightController, didUpdate imuState: DJIIMUState) {}

    func flightController(_ fc: DJIFlightController, didUpdate information: DJIAirSenseSystemInformation) {}

    func flightController(_ fc: DJIFlightController, didUpdate gravityCenterState: DJIGravityCenterState) {}

}

// MARK: - DJIFlightAssistantDelegate

extension FlightViewModel: DJIFlightAssistantDelegate {

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdate state: DJIVisionDetectionState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdate state: DJIVisionControlState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdate state: DJIVisionFaceAwareState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdate state: DJIVisionPalmControlState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdate state: DJIFlightAssistantObstacleAvoidanceSensorState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdateVisionSmartCaptureState state: DJISmartCaptureState) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["state": "\(state)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdateVisualPerceptionInformation information: DJIFlightAssistantPerceptionInformation) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["information": "\(information)"])
    }

    func flightAssistant(_ assistant: DJIFlightAssistant, didUpdateToFPerceptionInformation information: DJIFlightAssistantPerceptionInformation) {
        logger.info("DJIFlightAssistantDelegate", metadata: ["information": "\(information)"])
    }

}

// MARK: - Private

// MARK: Accessibility Focus

private extension FlightViewModel {

    func startFocusTimer() {
        focusTimerCancellable = Timer.publish(every: userDefaults.customAutoScanningTime, tolerance: 0, on: .main, in: .common, options: nil)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.accessibilityFocus = self.accessibilityFocus?.next() ?? \.upper
            }
    }

    func stopFocusTimer() {
        focusTimerCancellable = nil
    }

}

// MARK: State

private extension FlightViewModel {

    func clearErrorAfterDelay() {
        clearErrorCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.error = nil
            }
    }

    func updateObstacleAvoidanceState() {
        guard let obstacleAvoidance = obstacleAvoidance, let landingAssistance = landingAssistance else {
            avoidanceState = nil
            return
        }

        // make a new RadarState if the old one isn't right anymore
        if obstacleAvoidance !== avoidanceState?.obstacleAvoiding || landingAssistance !== avoidanceState?.landingAssisting {
            avoidanceState = ObstacleAvoidanceState(obstacleAvoiding: obstacleAvoidance, landingAssisting: landingAssistance)
        }

        // reload it
        avoidanceState?.reload()
    }

}

// MARK: Actions

private extension FlightViewModel {

    func setCommandsActive(active: Bool) {
        if active {
            commandGrid.setPendingsToActive()
            startSendTimerIfNeeded()
        } else {
            commandGrid.setActivesToPending()
            stopSendTimer()
        }
    }

}

// MARK: Continuous controls

private extension FlightViewModel {

    var currentControlsState: VirtualControlsState {
        let commandGridControlsState = commandGrid.controlsState(multipliers: movementMultipliers)
        let joystickControlsState = joystickCommands.controlsState(joystickState: joystickControlsModel.uiState, movementMultipliers: movementMultipliers)
        return joystickControlsState.forcingNonZeroValuesUpon(commandGridControlsState)
    }

    func sendControlsData() {
        let currentControlsState = currentControlsState

        // print("currentControlsState", currentControlsState)

        guard let flightController = flightController else { return }

        // Just making super sure these values are right before sending each control command.
        // The docs say that these values are reset on reconnection but disconnection handling is currently not working, so I'm worried about a drone reconnecting without us knowing about it.
        flightController.rollPitchControlMode = .velocity
        flightController.rollPitchCoordinateSystem = .body // i.e. north = drone goes forward, not literally north.
        flightController.yawControlMode = .angularVelocity
        flightController.verticalControlMode = .velocity

        flightController.send(currentControlsState.controlData) { [weak self] error in
            if let error = error {
                self?.error = error
            }
        }
    }

    func startSendTimerIfNeeded() {
        guard sendTimerCancellable == nil else {
            return
        }

        // repeatedly send whatever state we've got
        sendTimerCancellable = Timer.publish(every: 0.1, tolerance: 0, on: .main, in: .common)
            .autoconnect()
            .receive(on: sendQueue)
            .sink { [weak self] _ in
                self?.sendControlsData()
            }
    }

    func stopSendTimer() {
        // immediately send a zeroed-out value and stop the timer.
        sendTimerCancellable = nil
        sendControlsData()
    }

}

// MARK: - Observations

private extension FlightViewModel {

    func observeAircraftConnection(product: Aircraft) {
        connectionWatcher.$isConnected
            .receiveOnMain()
            .sink { [weak self] isConnected in
                if isConnected {
                    product.flightController?.delegate = self
                    product.flightController?.flightAssistant?.delegate = self
                }

                self?.updateObstacleAvoidanceState()
            }
            .store(in: &cancellables)
    }

    func observeApplicationLifecycle() {
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification, object: nil)
            .receiveOnMain()
            .sink { [weak self] _ in
                // 1. cancel any in-progress long press timers
                self?.isCommandTimerActive = false
                // 2. clear out active controls
                self?.setCommandsActive(active: false)
            }
            .store(in: &cancellables)
    }

    func observeSwitchControlRunning() {
        NotificationCenter.default
            .publisher(for: UIAccessibility.switchControlStatusDidChangeNotification, object: nil)
            .receiveOnMain()
            .map { _ in UIAccessibility.isSwitchControlRunning }
            .sink { [weak self] isSwitchControlRunning in
                guard let self else { return }

                let oldValue = self.isSwitchControlRunning

                guard isSwitchControlRunning != oldValue else {
                    return
                }

                self.isSwitchControlRunning = isSwitchControlRunning
                self.joystickControlsModel.interruptScreenControl()

                if !self.joystickControlsModel.uiState.isActive {
                    self.setCommandsActive(active: false)
                }

                if !isSwitchControlRunning {
                    self.accessibilityFocus = nil
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIAccessibility.elementFocusedNotification, object: nil)
            .receiveOnMain()
            .sink { [weak self] _ in
                guard UIAccessibility.isSwitchControlRunning else {
                    return
                }

                self?.joystickControlsModel.interruptScreenControl()
            }
            .store(in: &cancellables)
    }

    func observeJoystickAxisSelection() {
        joystickCommands.$verticalAxis.combineLatest(joystickCommands.$horizontalAxis)
            .receiveOnMain()
            .sink { [weak self] in
                guard let self else { return }

                let axisOptions = [$0.0, $0.1]

                self.commandGrid.setDisabledOrInactive(shouldDisable: { command in
                    axisOptions.contains(.verticalThrottle) && command.type.isVerticalThrottle
                    || axisOptions.contains(.pitch) && command.type.isPitch
                    || axisOptions.contains(.roll) && command.type.isRoll
                    || axisOptions.contains(.yaw) && command.type.isYaw
                })
            }
            .store(in: &cancellables)
    }

    func observeJoystickControlsModel() {
        joystickControlsModel.$uiState
            .receiveOnMain()
            .map(\.isActive)
            .removeDuplicates()
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
                    // start up the command timer (if not already running)
                    setCommandsActive(active: true)
                } else {
                    // stop everything. kill command timer. clear pending commands if user defaults says so.
                    releaseCommands()
                }
            }
            .store(in: &cancellables)
    }

    func observeGamePad() {
        gamePad.$connectionState.map(\.isConnected).assign(to: &$isGamePadConnected)

        let setGameControlActive: (_ active: Bool, _ column: Int) -> Void = { [weak self] active, column in
            guard let self else { return }
            if let accessibilityFocus = self.accessibilityFocus {
                self.setKeyState(keyDown: active, position: accessibilityFocus, column: column)
            } else {
                self.setKeyState(keyDown: active, column: column)
            }
        }

        gamePad.$upActive.sink { [weak self] isActive in
            if isActive {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            setGameControlActive(isActive, 0)
        }.store(in: &cancellables)

        gamePad.$leftActive.sink { [weak self] isActive in
            if isActive {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            setGameControlActive(isActive, 1)
        }.store(in: &cancellables)

        gamePad.$downActive.sink { [weak self] isActive in
            if isActive {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            setGameControlActive(isActive, 2)
        }.store(in: &cancellables)

        gamePad.$rightActive.sink { [weak self] isActive in
            if isActive {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            setGameControlActive(isActive, 3)
        }.store(in: &cancellables)

        gamePad.$leftThumbstickPosition.sink { [weak self] position in
            if position != .zero {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            self?.joystickControlsModel.joystickMoved(to: position, source: .leftJoystick)
        }.store(in: &cancellables)

        gamePad.$rightThumbstickPosition.sink { [weak self] position in
            if position != .zero {
                self?.joystickControlsModel.interruptNonJoystickControl()
            }

            self?.joystickControlsModel.joystickMoved(to: position, source: .rightJoystick)
        }.store(in: &cancellables)

        gamePad.isDirectionActive.removeDuplicates().sink { [weak self] isDirectionActive in
            guard let self else { return }
            guard self.isFocusTimerEnabled else { return }
            if isDirectionActive {
                self.stopFocusTimer()
            } else {
                self.startFocusTimer()
            }
        }.store(in: &cancellables)
    }

}
