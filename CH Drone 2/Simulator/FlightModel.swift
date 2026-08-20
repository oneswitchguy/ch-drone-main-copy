//
//  FlightModel.swift
//  CH Drone
//

import Foundation

/// A kinematic model of a velocity-commanded multirotor.
///
/// Deliberately *not* a physics engine. The app never commands thrust or attitude — it
/// commands velocities and the aircraft's own flight controller closes the loop. So what
/// has to be reproduced here is the behaviour of that loop as felt from the pilot's side:
/// the command ceilings, the lag before a commanded velocity is actually reached, and the
/// envelope limits. Aerodynamics would add nothing a pilot could feel through this app.
///
/// Reference airframe is the Mavic 2 Pro in Sport mode, which is what
/// `docs/dji-virtual-stick-sport-mode.md` records as the real flight configuration.
///
/// Deliberately free of DJI imports so it can be unit tested on the Mac. Anything that
/// needs to touch the SDK belongs in `SimulatedFlightController`.
///
/// ## Coordinate frame
///
/// East-North-Up, in metres, with the origin at the take-off point:
///
/// - `x` — east, positive
/// - `y` — north, positive
/// - `z` — up, positive
///
/// Note that this is *not* DJI's frame. `DJISimulatorState` reports `positionX` as east,
/// `positionY` as north and `positionZ` as **negative** when above the home point. The
/// conversion is `(x, y, -z)`, and it matters when comparing this model against a
/// recording from the aircraft's own simulator.
///
/// `heading` is a compass bearing in degrees — 0 is north, increasing clockwise, wrapped
/// to `-180...180` to match `DJISimulatorState.yaw`.
struct FlightModel {

    // MARK: - Configuration

    /// The flight envelope. Defaults describe a Mavic 2 Pro flown in Sport mode.
    struct Limits: Equatable {

        /// Horizontal ceiling, m/s. The aircraft will pass no more than this however large
        /// a value is sent, which is what makes it worth simulating.
        var horizontalSpeed = Double(VirtualStickLimits.horizontalSpeed)

        /// Vertical ceiling, m/s.
        var verticalSpeed = Double(VirtualStickLimits.verticalSpeed)

        /// Yaw ceiling, °/s.
        var yawRate = Double(VirtualStickLimits.yawRate)

        /// Geofence ceiling, metres above the take-off point. 120 m is DJI's default and
        /// the legal limit in most jurisdictions, so practising against it is the point.
        var maximumAltitude: Double = 120

        /// Largest tilt shown by the renderer, degrees. Sport mode allows about 35°.
        /// Cosmetic only — tilt is a consequence of the commanded velocity here, never a
        /// cause of it.
        var maximumTilt: Double = 35

        /// Time constant of the horizontal velocity response, seconds.
        ///
        /// A first-order lag settles to within 5% after about 3τ, and coasts `v·τ` metres
        /// when the command is released. DJI quote roughly 30 m of braking distance from
        /// Sport-mode top speed, which is where 1.5 s comes from. This is the number most
        /// worth replacing with a measurement — see the calibration note on
        /// ``Limits/horizontalSpeed``.
        var horizontalResponse: Double = 1.5

        /// Time constant of the vertical velocity response, seconds. Climb and descent
        /// settle noticeably faster than horizontal flight.
        var verticalResponse: Double = 0.6

        /// Time constant of the yaw rate response, seconds.
        var yawResponse: Double = 0.3

        /// Height the aircraft climbs to on an automatic take-off, metres.
        var takeOffAltitude: Double = 1.2

        /// Climb rate during automatic take-off, m/s.
        var takeOffClimbRate: Double = 1.0

        /// Descent rate during automatic landing, m/s.
        var landingDescentRate: Double = 0.5

        static let mavic2Pro = Limits()
    }

    // MARK: - Command

    /// A pilot command, in SI units, in the aircraft's body frame.
    ///
    /// This is what the app is really asking for once the virtual stick encoding is
    /// stripped away. `SimulatedFlightController` does that decoding.
    struct Command: Equatable {

        /// Velocity along the nose direction, m/s. Positive is forward.
        var forward: Double = 0

        /// Velocity across the airframe, m/s. Positive is to the pilot's right when
        /// looking along the nose.
        var right: Double = 0

        /// Vertical velocity, m/s. Positive climbs.
        var up: Double = 0

        /// Yaw rate, °/s. Positive rotates clockwise seen from above.
        var yawRate: Double = 0

        /// The command that holds position.
        static let hover = Command()
    }

    // MARK: - State

    enum Phase: Equatable {
        case landed
        case takingOff
        case flying
        case landing
    }

    struct State: Equatable {

        /// Position in the ENU frame described on ``FlightModel``, metres.
        var position: SIMD3<Double> = .zero

        /// Velocity in the ENU frame, m/s. World frame, not body frame.
        var velocity: SIMD3<Double> = .zero

        /// Compass bearing of the nose, degrees, wrapped to `-180...180`.
        var heading: Double = 0

        /// Current rate of turn, °/s.
        var yawRate: Double = 0

        /// Nose-up attitude in degrees. Cosmetic — derived from acceleration so the
        /// renderer can tilt the airframe convincingly.
        var pitch: Double = 0

        /// Right-wing-down attitude in degrees. Cosmetic, as with ``pitch``.
        var roll: Double = 0

        var phase: Phase = .landed

        /// Set while the pilot is asking for more speed than the aircraft will give.
        ///
        /// Under default settings this never lights: the app tops out around 2 m/s against
        /// a 15 m/s ceiling. It exists for the case in `docs/virtual-stick-command-scaling.md`
        /// — the speed multipliers are unbounded free-text fields in the iOS Settings app,
        /// and nothing clamps the converted command, so a large enough value commands a
        /// speed the aircraft will silently refuse. Surfacing it means that can be seen on
        /// the ground rather than discovered in the air.
        var isCommandSaturated: Bool = false

        /// Height above the take-off point, metres.
        var altitude: Double { position.z }

        /// Horizontal speed over the ground, m/s.
        var groundSpeed: Double { hypot(velocity.x, velocity.y) }

        /// Vertical speed, m/s. Positive climbs.
        var verticalSpeed: Double { velocity.z }

        /// Horizontal distance from the take-off point, metres.
        var distanceFromHome: Double { hypot(position.x, position.y) }

        var isFlying: Bool { phase != .landed }

        static let landed = State()
    }

    // MARK: - Properties

    private(set) var state: State
    var limits: Limits

    init(limits: Limits = .mavic2Pro, state: State = .landed) {
        self.limits = limits
        self.state = state
    }

    // MARK: - Pilot actions

    /// Starts an automatic take-off. Ignored unless the aircraft is on the ground.
    mutating func takeOff() {
        guard state.phase == .landed else { return }
        state.phase = .takingOff
    }

    /// Starts an automatic landing. Ignored if the aircraft is already on the ground.
    mutating func land() {
        guard state.phase != .landed else { return }
        state.phase = .landing
    }

    /// Cuts the motors and drops everything back to the take-off point.
    ///
    /// Not a real aircraft behaviour — this is the simulator's "put it back" affordance,
    /// so a pilot who has flown themselves into a corner can restart without a menu.
    mutating func reset() {
        state = .landed
    }

    // MARK: - Integration

    /// Advances the model by `interval` seconds under `command`.
    ///
    /// `command` is ignored during automatic take-off and landing, which is what the real
    /// aircraft does — those are flight-controller routines, not piloted manoeuvres.
    mutating func advance(by interval: TimeInterval, command: Command = .hover) {
        guard interval > 0 else { return }

        switch state.phase {
        case .landed:
            settleOnGround()
        case .takingOff:
            climbToTakeOffAltitude(over: interval)
        case .flying:
            fly(command, over: interval)
        case .landing:
            descendToGround(over: interval)
        }
    }

    // MARK: - Private

    private mutating func settleOnGround() {
        state.velocity = .zero
        state.yawRate = 0
        state.pitch = 0
        state.roll = 0
        state.position.z = 0
        state.isCommandSaturated = false
    }

    private mutating func climbToTakeOffAltitude(over interval: TimeInterval) {
        state.isCommandSaturated = false
        state.velocity = SIMD3(0, 0, limits.takeOffClimbRate)
        state.position.z += limits.takeOffClimbRate * interval

        if state.position.z >= limits.takeOffAltitude {
            state.position.z = limits.takeOffAltitude
            state.velocity = .zero
            state.phase = .flying
        }
    }

    private mutating func descendToGround(over interval: TimeInterval) {
        state.isCommandSaturated = false
        state.velocity = SIMD3(0, 0, -limits.landingDescentRate)
        state.position.z -= limits.landingDescentRate * interval

        if state.position.z <= 0 {
            state.phase = .landed
            settleOnGround()
        }
    }

    private mutating func fly(_ command: Command, over interval: TimeInterval) {
        let target = targetVelocity(for: command)
        let previousVelocity = state.velocity

        // Exact solution of v̇ = (target − v)/τ over the interval, rather than an Euler
        // step. The timer driving this runs at 10 Hz but is not guaranteed to, and the
        // exponential form stays stable and frame-rate independent when it drifts.
        let horizontalBlend = blend(over: interval, timeConstant: limits.horizontalResponse)
        let verticalBlend = blend(over: interval, timeConstant: limits.verticalResponse)

        state.velocity.x += (target.x - state.velocity.x) * horizontalBlend
        state.velocity.y += (target.y - state.velocity.y) * horizontalBlend
        state.velocity.z += (target.z - state.velocity.z) * verticalBlend

        let targetYawRate = command.yawRate.clamped(to: limits.yawRate)
        state.yawRate += (targetYawRate - state.yawRate) * blend(over: interval, timeConstant: limits.yawResponse)
        state.heading = Self.wrapped(state.heading + state.yawRate * interval)

        state.position.x += state.velocity.x * interval
        state.position.y += state.velocity.y * interval
        state.position.z += state.velocity.z * interval

        constrainAltitude()
        updateAttitude(target: target, previousVelocity: previousVelocity)
    }

    /// Converts a body-frame command into the world-frame velocity the aircraft will
    /// actually try to reach.
    private func targetVelocity(for command: Command) -> SIMD3<Double> {
        // Each axis is clamped separately first, because that is what the SDK does — the
        // ceilings are per-field, not on the resulting vector.
        let forward = command.forward.clamped(to: limits.horizontalSpeed)
        let right = command.right.clamped(to: limits.horizontalSpeed)

        let radians = state.heading * .pi / 180
        let sinHeading = sin(radians)
        let cosHeading = cos(radians)

        // Heading 0 points north, so the nose vector is (sin, cos) in ENU and the
        // starboard vector is that turned 90° clockwise.
        var east = forward * sinHeading + right * cosHeading
        var north = forward * cosHeading - right * sinHeading

        // The airframe then clamps total ground speed, so a diagonal command cannot reach
        // √2 × the limit the way per-axis clamping alone would allow.
        let speed = hypot(east, north)
        if speed > limits.horizontalSpeed {
            let scale = limits.horizontalSpeed / speed
            east *= scale
            north *= scale
        }

        return SIMD3(east, north, command.up.clamped(to: limits.verticalSpeed))
    }

    private mutating func constrainAltitude() {
        if state.position.z >= limits.maximumAltitude {
            state.position.z = limits.maximumAltitude
            state.velocity.z = min(state.velocity.z, 0)
        }

        if state.position.z <= 0 {
            state.position.z = 0
            state.velocity.z = max(state.velocity.z, 0)
        }
    }

    /// Derives a cosmetic attitude from the acceleration the model is currently producing.
    ///
    /// A multirotor tilts to accelerate, so `tan(θ) = a/g` reads correctly to a pilot even
    /// though nothing here depends on it. Taken analytically from the first-order lag
    /// rather than by differencing positions, which keeps it free of timer jitter.
    private mutating func updateAttitude(target: SIMD3<Double>, previousVelocity: SIMD3<Double>) {
        let accelerationEast = (target.x - previousVelocity.x) / limits.horizontalResponse
        let accelerationNorth = (target.y - previousVelocity.y) / limits.horizontalResponse

        let radians = state.heading * .pi / 180
        let sinHeading = sin(radians)
        let cosHeading = cos(radians)

        let alongNose = accelerationEast * sinHeading + accelerationNorth * cosHeading
        let alongStarboard = accelerationEast * cosHeading - accelerationNorth * sinHeading

        let gravity = 9.81
        // Accelerating forward pitches the nose down, hence the negation.
        state.pitch = (-atan2(alongNose, gravity) * 180 / .pi).clamped(to: limits.maximumTilt)
        state.roll = (atan2(alongStarboard, gravity) * 180 / .pi).clamped(to: limits.maximumTilt)
    }

    private func blend(over interval: TimeInterval, timeConstant: Double) -> Double {
        guard timeConstant > 0 else { return 1 }
        return 1 - exp(-interval / timeConstant)
    }

    private static func wrapped(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

}

// MARK: - Saturation reporting

extension FlightModel {

    /// Records whether `command` asked for more than the envelope allows.
    ///
    /// Kept separate from ``advance(by:command:)`` so the integration stays a pure
    /// function of the command, and so callers that do not care can skip it.
    mutating func noteSaturation(of command: Command) {
        state.isCommandSaturated =
            abs(command.forward) > limits.horizontalSpeed
            || abs(command.right) > limits.horizontalSpeed
            || abs(command.up) > limits.verticalSpeed
            || abs(command.yawRate) > limits.yawRate
    }

}

// MARK: -

private extension Double {

    /// Clamps to a symmetric range about zero, which is the shape every SDK limit takes.
    func clamped(to magnitude: Double) -> Double {
        Swift.min(Swift.max(self, -magnitude), magnitude)
    }

}
