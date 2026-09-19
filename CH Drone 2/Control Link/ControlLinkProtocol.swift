//
//  ControlLinkProtocol.swift
//  CH Drone
//

import Foundation

/// The MQTT contract between this app, the joystick mover and the Mac monitor.
///
/// Written up for the mover's firmware in `docs/control-link-mqtt.md`; change the two
/// together. Every payload is flat JSON so that a microcontroller can parse it without
/// nesting or base64.
///
/// Pure Foundation, because the Mac monitor in `tools/ControlLinkMonitor` compiles this file
/// by reference.
enum ControlLinkProtocol {

    static let topicRoot = "chdrone/v1/"

    /// Stick deflection, QoS 0, not retained. Sent at the flight send timer's 10 Hz.
    static let stickTopic = topicRoot + "stick"
    /// Whether the app is online, QoS 1, retained. The Will publishes the offline form.
    static let statusTopic = topicRoot + "status"
    /// Latency probes. Anything on the link may answer a ping with a pong.
    static let pingTopic = topicRoot + "ping"
    static let pongTopic = topicRoot + "pong"

    static let defaultPort: UInt16 = 1883

    /// Names the simulator as the origin of a stick message, so the receiver can tell
    /// practice traffic from a real flight.
    static let simulatorSource = "simulator"
    static let flightSource = "flight"

    /// Milliseconds since 1970 on this device's clock, the unit of every `t` on the wire.
    static func nowMillis() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    /// Converts one axis of the app's command into physical stick deflection, -1…1.
    ///
    /// Full stick is the axis's baseline command at the **Fastest** speed step, which is the
    /// on-screen joystick pushed all the way at Fastest. Because the speed steps are already
    /// in `command`, each step becomes a fixed fraction of full stick: with the default
    /// multipliers, a held Pitch Forward at Medium (1.0 of Fastest's 2.0) is 0.5.
    ///
    /// Rounded to a thousandth, which is finer than any stick can be set and keeps the JSON
    /// readable (0.375, not 0.37499997).
    static func deflection(command: Float, baseline: Float, fastestMultiplier: Float) -> Float {
        let fullStick = abs(baseline) * fastestMultiplier
        guard fullStick > 0 else {
            return 0
        }

        let clamped = min(max(command / fullStick, -1), 1)
        return (clamped * 1_000).rounded() / 1_000
    }

}

/// Published on ``ControlLinkProtocol/stickTopic``.
///
/// Axes are Mode 2 stick positions, each -1…1: pitch +1 is the right stick fully up
/// (forward), roll +1 the right stick fully right, yaw +1 the left stick fully right
/// (clockwise), throttle +1 the left stick fully up (climb).
struct ControlLinkStick: Codable, Equatable {
    /// One per app launch, so a receiver can tell a restart from a sequence gap.
    let session: String
    /// Increases by one per message within a session.
    let seq: UInt64
    /// Sender's clock, milliseconds since 1970.
    let t: UInt64
    let pitch: Float
    let roll: Float
    let yaw: Float
    let throttle: Float
    /// False when every axis is at rest.
    let active: Bool
    /// ``ControlLinkProtocol/simulatorSource`` or ``ControlLinkProtocol/flightSource``.
    let source: String
}

/// Published retained on ``ControlLinkProtocol/statusTopic``.
struct ControlLinkStatus: Codable, Equatable {
    let online: Bool
    let session: String
    let device: String?
    let build: String?
}

/// Published on ``ControlLinkProtocol/pingTopic`` by whoever is measuring.
struct ControlLinkPing: Codable, Equatable {
    let id: UInt64
    /// Who sent the ping, so each measurer only counts its own pongs.
    let from: String
    /// The pinger's clock when sent.
    let t: UInt64
}

/// Published on ``ControlLinkProtocol/pongTopic`` in answer to a ping, straight away.
struct ControlLinkPong: Codable, Equatable {
    let id: UInt64
    let from: String
    /// Who answered: `"ipad"` for this app, and for example `"mover"` for the hardware.
    let by: String
    /// Copied from the ping.
    let t: UInt64
    /// The responder's clock when the ping arrived. With the round trip, this lets the
    /// measurer estimate the offset between the two clocks.
    let rt: UInt64
}
