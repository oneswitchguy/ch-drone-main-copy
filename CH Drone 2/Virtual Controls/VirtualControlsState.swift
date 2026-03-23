//
//  VirtualControlsState.swift
//  VirtualControlsState
//
//  Created by Alex Robinson on 10/8/21.
//

import DJISDK
import Foundation

/// Relative control levels. Each control point is in the range of (-1...1).
struct VirtualControlsState: Equatable {

    static let stopped = VirtualControlsState(pitch: 0, roll: 0, yaw: 0, verticalThrottle: 0)

    var pitch: Float = 0 {
        didSet {
            pitch = pitch.clamped(to: -1...1)
        }
    }

    var roll: Float = 0 {
        didSet {
            roll = roll.clamped(to: -1...1)
        }
    }

    var yaw: Float = 0 {
        didSet {
            yaw = yaw.clamped(to: -1...1)
        }
    }

    var verticalThrottle: Float = 0 {
        didSet {
            verticalThrottle = verticalThrottle.clamped(to: -1...1)
        }
    }

}

extension VirtualControlsState {

    static func + (lhs: VirtualControlsState, rhs: VirtualControlsState) -> VirtualControlsState {
        VirtualControlsState(
            pitch: lhs.pitch + rhs.pitch,
            roll: lhs.roll + rhs.roll,
            yaw: lhs.yaw + rhs.yaw,
            verticalThrottle: lhs.verticalThrottle + rhs.verticalThrottle
        )
    }

    func forcingNonZeroValuesUpon(_ other: VirtualControlsState) -> VirtualControlsState {
        VirtualControlsState(
            pitch: pitch == 0 ? other.pitch : pitch,
            roll: roll == 0 ? other.roll : roll,
            yaw: yaw == 0 ? other.yaw : yaw,
            verticalThrottle: verticalThrottle == 0 ? other.verticalThrottle : verticalThrottle
        )
    }

}

// MARK: - Conversion to SDK values

extension VirtualControlsState {

    var controlData: DJIVirtualStickFlightControlData {
        // Ranges are documented in:
        // - `DJIVirtualStickRollPitchControlMode` (we're using `.velocity`)
        // - `DJIVirtualStickYawControlMode` (we're using `.angularVelocity`)
        // - `DJIVirtualStickVerticalControlMode` (we're using `.velocity`)
        let pitchRollAngleRange: ClosedRange<Float> = 0...100
        let yawAngularVelocityRange: ClosedRange<Float> = 0...100
        let verticalVelocityRange: ClosedRange<Float> = 0...4

        // the valid ranges are all symmetric, so we can interpolate our (-1.0...1.0) value on the positive range.
        return DJIVirtualStickFlightControlData(
            pitch: pitchRollAngleRange.interpolatedValue(at: roll), // YES, THESE ARE BACKWARDS!
            roll: pitchRollAngleRange.interpolatedValue(at: pitch), // YES, THESE ARE BACKWARDS!
            yaw: yawAngularVelocityRange.interpolatedValue(at: yaw),
            verticalThrottle: verticalVelocityRange.interpolatedValue(at: verticalThrottle)
        )
    }

}
