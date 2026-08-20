//
//  VirtualStickLimits.swift
//  CH Drone
//

import Foundation

/// The ceilings the flight controller accepts for virtual stick commands.
///
/// Quoted from `DJIFlightControllerBaseTypes.h` and the API reference for
/// `DJIVirtualStickRollPitchControlMode`. These previously existed only as comments, and
/// nothing enforced them — the app sent whatever the command chain produced and relied on
/// the aircraft to reject anything out of range. Firmware is not a validation layer, and
/// `docs/virtual-stick-command-scaling.md` sets out how far out of range it could get.
///
/// Deliberately free of DJI imports so ``FlightModel`` can share these without linking the
/// SDK, which would make it untestable off-device.
enum VirtualStickLimits {

    /// Maximum horizontal velocity for roll and pitch in `.velocity` mode, m/s.
    static let horizontalSpeed: Float = 15

    /// Maximum vertical velocity in `.velocity` mode, m/s.
    static let verticalSpeed: Float = 4

    /// Maximum yaw rate in `.angularVelocity` mode, °/s.
    static let yawRate: Float = 100

    // MARK: - As ranges

    /// Every SDK ceiling is symmetric about zero, so these are the clamps to apply.

    static var horizontalVelocityRange: ClosedRange<Float> { -horizontalSpeed...horizontalSpeed }
    static var verticalVelocityRange: ClosedRange<Float> { -verticalSpeed...verticalSpeed }
    static var yawRateRange: ClosedRange<Float> { -yawRate...yawRate }

}
