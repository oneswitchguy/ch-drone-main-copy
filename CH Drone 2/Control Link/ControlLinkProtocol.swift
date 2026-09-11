//
//  ControlLinkProtocol.swift
//  CH Drone
//

import Foundation
import UIKit

/// The wire format shared with the receiver app.
///
/// Ported from the playground clone (`ch-drone-playground`, commit `92ad2a3`), where the
/// control link was first built, and from which it is not otherwise reachable — that clone
/// has no simulator. The two copies must stay byte-compatible or the receiver stops
/// decoding, and nothing keeps the two in step automatically.
///
/// The one deliberate difference is ``makeControlStatePayload``, which takes the control
/// source as a plain `String`. The playground passes a `JoystickUIState.ControlSource` and
/// maps it through a `wireValue` property, which this branch does not have — the enum itself
/// exists here, only that extension is missing. The field is `String?` on the wire either
/// way, so both ends stay compatible.

enum ControlLinkMessageType: String, Codable {
    case hello
    case heartbeat
    case controlState
    case error
}

struct ControlLinkEnvelope: Codable {
    let version: Int
    let messageType: ControlLinkMessageType
    let sequence: UInt64
    let timestampMillis: UInt64
    let payload: Data
}

struct ControlLinkHelloPayload: Codable {
    let appName: String
    let deviceName: String
    let sessionID: UUID
    let capabilities: [String]
}

struct ControlLinkHeartbeatPayload: Codable {
    let sessionID: UUID
}

struct ControlLinkControlStatePayload: Codable, Equatable {
    let sessionID: UUID
    let pitch: Float
    let roll: Float
    let yaw: Float
    let verticalThrottle: Float
    let isActive: Bool
    let source: String?
}

enum ControlLinkProtocolError: Error {
    case frameTooLarge
}

enum ControlLinkProtocol {
    static let version = 1
    static let serviceType = "_chdrone-control._tcp"
    static let capabilities = ["control-state-stream-v1", "heartbeat-v1"]
    static let maxFrameSize = Int(UInt32.max)

    /// Names the simulator as the origin of a control state, so the receiver can tell
    /// practice traffic from a real flight.
    static let simulatorSource = "simulator"

    static func makeHelloPayload(sessionID: UUID) -> ControlLinkHelloPayload {
        ControlLinkHelloPayload(
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "CH Drone",
            deviceName: UIDevice.current.name,
            sessionID: sessionID,
            capabilities: capabilities
        )
    }

    static func makeHeartbeatPayload(sessionID: UUID) -> ControlLinkHeartbeatPayload {
        ControlLinkHeartbeatPayload(sessionID: sessionID)
    }

    static func makeControlStatePayload(
        sessionID: UUID,
        controlsState: VirtualControlsState,
        isActive: Bool,
        source: String?
    ) -> ControlLinkControlStatePayload {
        ControlLinkControlStatePayload(
            sessionID: sessionID,
            pitch: controlsState.pitch,
            roll: controlsState.roll,
            yaw: controlsState.yaw,
            verticalThrottle: controlsState.verticalThrottle,
            isActive: isActive,
            source: source
        )
    }

    static func encodeFrame<Payload: Encodable>(
        type: ControlLinkMessageType,
        payload: Payload,
        sequence: UInt64,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        let payloadData = try encoder.encode(payload)
        let envelope = ControlLinkEnvelope(
            version: version,
            messageType: type,
            sequence: sequence,
            timestampMillis: UInt64(Date().timeIntervalSince1970 * 1_000),
            payload: payloadData
        )
        let envelopeData = try encoder.encode(envelope)

        guard envelopeData.count <= maxFrameSize else {
            throw ControlLinkProtocolError.frameTooLarge
        }

        var frameLength = UInt32(envelopeData.count).bigEndian
        let header = Data(bytes: &frameLength, count: MemoryLayout<UInt32>.size)
        return header + envelopeData
    }
}
