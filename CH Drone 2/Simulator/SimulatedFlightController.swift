//
//  SimulatedFlightController.swift
//  CH Drone
//

import DJISDK
import Foundation
import Logging
import QuartzCore

private let logger = Logger(label: #fileID)

/// A `FlightControlling` that flies ``FlightModel`` instead of an aircraft.
///
/// Dropped into `SimulatorAircraft.flightControl`, this makes the whole existing control
/// path — switch grid, on-screen joystick, gamepad, AirPods head tracking — fly a
/// simulation with nothing connected. `FlightViewModel` is unchanged and unaware.
///
/// This is the only file in the simulator that imports the SDK. It exists to translate,
/// and the flying itself belongs in ``FlightModel``, which has no DJI dependency and can
/// therefore be tested without a device.
final class SimulatedFlightController: NSObject, FlightControlling {

    /// The current simulated aircraft state, for the renderer to observe.
    @ValueSubject private(set) var state: FlightModel.State = .landed

    override init() {
        super.init()
        start()
    }

    deinit {
        displayLink?.invalidate()
    }

    /// Stops the simulation.
    ///
    /// `deinit` covers the normal case, but leaving this to deallocation alone would mean
    /// a simulation kept running for as long as anything still held the controller.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - FlightControlling

    weak var delegate: DJIFlightControllerDelegate?

    /// Always `nil`. A simulated aircraft has no obstacle sensors; `SimulatorAircraft`
    /// supplies `SimulatedObstacleAvoidance` separately when that is wanted.
    var flightAssistant: DJIFlightAssistant? { nil }

    var rollPitchControlMode: DJIVirtualStickRollPitchControlMode = .velocity
    var rollPitchCoordinateSystem: DJIVirtualStickFlightCoordinateSystem = .body
    var yawControlMode: DJIVirtualStickYawControlMode = .angularVelocity
    var verticalControlMode: DJIVirtualStickVerticalControlMode = .velocity

    func setVirtualStickModeEnabled(_ enabled: Bool, withCompletion completion: DJICompletionBlock?) {
        lock.lock()
        isVirtualStickModeEnabled = enabled
        // Drop any stick position held from a previous session, so re-enabling cannot
        // resume a command the pilot has long since let go of.
        pendingCommand = .hover
        lock.unlock()

        logger.info("Virtual stick mode", metadata: ["enabled": .stringConvertible(enabled)])
        completion?(nil)
    }

    /// Called from `FlightViewModel`'s send queue at 10 Hz, so this is not the main thread.
    /// The command is stashed under a lock and applied by the display link.
    func send(_ controlData: DJIVirtualStickFlightControlData, withCompletion completion: DJICompletionBlock?) {
        let decoded = Self.command(from: controlData)

        lock.lock()
        pendingCommand = decoded
        lock.unlock()

        completion?(nil)
    }

    func confirmSmartReturn(toHomeRequest confirmed: Bool, withCompletion completion: DJICompletionBlock?) {
        // Smart return-to-home never triggers in the simulator, so there is nothing to
        // confirm or cancel. Reported as success so callers are not left hanging.
        completion?(nil)
    }

    // MARK: - Simulator actions

    /// These have no `FlightControlling` equivalent because the real app takes off through
    /// `DUXBetaTakeOffWidget`, which talks to the SDK directly. The simulator screen drives
    /// them itself.

    func takeOff() {
        model.takeOff()
        publish()
    }

    func land() {
        model.land()
        publish()
    }

    func reset() {
        lock.lock()
        pendingCommand = .hover
        lock.unlock()

        model.reset()
        publish()
    }

    /// The flight envelope in use. Exposed so a calibration run against the aircraft's own
    /// `DJISimulator` can replace the estimated response times with measured ones.
    var limits: FlightModel.Limits {
        get { model.limits }
        set { model.limits = newValue }
    }

    // MARK: - Private

    private var model = FlightModel()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let lock = NSLock()
    private var pendingCommand: FlightModel.Command = .hover
    private var isVirtualStickModeEnabled = false

    private func start() {
        let link = CADisplayLink(target: DisplayLinkProxy(target: self), selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }

        guard let lastTimestamp else { return }

        // Clamp the step. Coming back from the background produces one enormous interval,
        // which would otherwise teleport the aircraft.
        let interval = min(link.timestamp - lastTimestamp, 1.0 / 20)

        lock.lock()
        let command = isVirtualStickModeEnabled ? pendingCommand : .hover
        lock.unlock()

        model.noteSaturation(of: command)
        model.advance(by: interval, command: command)
        publish()
    }

    private func publish() {
        state = model.state
    }

    /// Undoes the virtual stick encoding applied by `VirtualControlsState.controlData`.
    ///
    /// The pitch and roll fields are swapped there, under a comment reading "YES, THESE
    /// ARE BACKWARDS!" — in DJI's body coordinate system it is the `roll` field that moves
    /// the aircraft along its nose. Decoding has to swap them back the same way, or the
    /// simulator would fly at right angles to the real thing.
    ///
    /// The values arrive in m/s and °/s and are passed through unscaled, so the simulator
    /// is subject to whatever the real command chain produces — including the unbounded
    /// speed multipliers described in `docs/virtual-stick-command-scaling.md`.
    /// ``FlightModel`` then clamps exactly as the aircraft would.
    private static func command(from controlData: DJIVirtualStickFlightControlData) -> FlightModel.Command {
        FlightModel.Command(
            forward: Double(controlData.roll),
            right: Double(controlData.pitch),
            up: Double(controlData.verticalThrottle),
            yawRate: Double(controlData.yaw)
        )
    }

}

// MARK: -

/// Holds ``SimulatedFlightController`` weakly on behalf of its display link.
///
/// `CADisplayLink` retains its target, so targeting the controller directly would make it
/// immortal: `deinit` would never run, `invalidate()` would never be called, and the
/// simulation would go on ticking for the life of the process.
private final class DisplayLinkProxy {

    weak var target: SimulatedFlightController?

    init(target: SimulatedFlightController) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let target else {
            link.invalidate()
            return
        }
        target.tick(link)
    }

}
