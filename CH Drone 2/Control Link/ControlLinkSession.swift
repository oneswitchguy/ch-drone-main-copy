//
//  ControlLinkSession.swift
//  CH Drone
//

import Combine
import Foundation
import os
import UIKit

/// Owns the MQTT control link for the app, and is what the simulator's link button talks to.
///
/// Streams the pilot's stick state as physical stick deflection to the broker set in
/// Settings, for the joystick mover and the Mac monitor. The contract is
/// `ControlLinkProtocol.swift`, written up in `docs/control-link-mqtt.md`.
///
/// While connected it also:
/// - keeps a retained status on the broker (online, and offline through the Will if the
///   connection drops), so a receiver knows whether the app is there at all;
/// - answers every ping with a pong at once, so the monitor can measure the round trip.
///
/// The flag is persisted but **defaults to off**: this is a test-phase feature, and a
/// practice session should not start connecting out because a pilot opened the simulator.
///
/// Threading: ``setEnabled(_:)``, ``toggle()`` and the published properties are main-queue
/// only, like the rest of the view models here. ``send(controlsState:source:)`` is the
/// exception. It runs at 10 Hz on the flight send timer's queue, and once more from the main
/// queue when the timer stops, so its flag and sequence number live behind a lock.
final class ControlLinkSession: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var connectionState: MQTTClient.State = .idle

    init(client: MQTTClient = MQTTClient(), userDefaults: UserDefaults = .standard) {
        let enabled = userDefaults.isControlLinkEnabled

        self.client = client
        self.userDefaults = userDefaults
        self.isEnabled = enabled
        self.sendState = OSAllocatedUnfairLock(initialState: SendState(isEnabled: enabled))

        client.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.isEnabled || state == .idle else { return }
                self.connectionState = state
            }
        }

        client.onConnect = { [weak self] in
            self?.publishStatus(online: true)
        }

        client.onMessage = { [weak self] topic, payload in
            self?.handleMessage(topic: topic, payload: payload)
        }

        if enabled {
            client.start(makeConfiguration())
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        sendState.withLock { $0.isEnabled = enabled }
        userDefaults.isControlLinkEnabled = enabled

        if enabled {
            client.start(makeConfiguration())
        } else {
            // Ahead of the DISCONNECT on the same queue, so a clean stop still tells
            // receivers the app has gone, without waiting for the Will.
            publishStatus(online: false)
            client.stop()
            connectionState = .idle
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Forwards the current stick positions as physical deflection.
    ///
    /// Dropped entirely when the link is off, which keeps the cost of the disabled case —
    /// every flight, for every pilot who never turns this on — to one lock read.
    func send(controlsState: VirtualControlsState, source: String) {
        guard let seq = sendState.withLock({ state -> UInt64? in
            guard state.isEnabled else { return nil }
            state.seq += 1
            return state.seq
        }) else { return }

        let deflection = Self.stickDeflection(for: controlsState, fastestMultiplier: userDefaults.fastestMultiplier)
        let stick = ControlLinkStick(
            session: sessionID,
            seq: seq,
            t: ControlLinkProtocol.nowMillis(),
            pitch: deflection.pitch,
            roll: deflection.roll,
            yaw: deflection.yaw,
            throttle: deflection.verticalThrottle,
            active: controlsState != .stopped,
            source: source
        )

        guard let payload = try? JSONEncoder().encode(stick) else { return }
        client.publish(topic: ControlLinkProtocol.stickTopic, payload: payload)
    }

    /// The app's command, which already includes the speed step, as stick deflection per
    /// axis. Full stick is the axis's baseline at the Fastest step — see
    /// ``ControlLinkProtocol/deflection(command:baseline:fastestMultiplier:)``.
    static func stickDeflection(for controlsState: VirtualControlsState, fastestMultiplier: Float) -> VirtualControlsState {
        func deflection(_ command: Float, _ movementType: MovementType) -> Float {
            ControlLinkProtocol.deflection(
                command: command,
                baseline: movementType.baselineValue,
                fastestMultiplier: fastestMultiplier
            )
        }

        return VirtualControlsState(
            pitch: deflection(controlsState.pitch, .pitchForward),
            roll: deflection(controlsState.roll, .rollRight),
            yaw: deflection(controlsState.yaw, .yawRight),
            verticalThrottle: deflection(controlsState.verticalThrottle, .up)
        )
    }

    // MARK: - Private

    private struct SendState {
        var isEnabled: Bool
        var seq: UInt64 = 0
    }

    private let client: MQTTClient
    private let userDefaults: UserDefaults
    private let sendState: OSAllocatedUnfairLock<SendState>

    /// One per launch, so receivers can tell a restart from a gap in `seq`.
    private let sessionID = UUID().uuidString
    private let deviceName = UIDevice.current.name
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    private func makeConfiguration() -> MQTTClient.Configuration {
        MQTTClient.Configuration(
            host: userDefaults.controlLinkBrokerHost,
            port: userDefaults.controlLinkBrokerPort,
            clientID: "chdrone-ipad-\(sessionID.prefix(8))",
            will: MQTTWill(
                topic: ControlLinkProtocol.statusTopic,
                payload: statusPayload(online: false),
                qos: .atLeastOnce,
                retain: true
            ),
            subscriptions: [MQTTSubscription(topicFilter: ControlLinkProtocol.pingTopic, qos: .atMostOnce)]
        )
    }

    private func publishStatus(online: Bool) {
        client.publish(
            topic: ControlLinkProtocol.statusTopic,
            payload: statusPayload(online: online),
            qos: .atLeastOnce,
            retain: true
        )
    }

    private func statusPayload(online: Bool) -> Data {
        let status = ControlLinkStatus(online: online, session: sessionID, device: deviceName, build: build)
        return (try? JSONEncoder().encode(status)) ?? Data()
    }

    /// Runs on the client's queue, which is the quickest way back out for a pong.
    private func handleMessage(topic: String, payload: Data) {
        guard topic == ControlLinkProtocol.pingTopic,
              let ping = try? JSONDecoder().decode(ControlLinkPing.self, from: payload) else {
            return
        }

        let pong = ControlLinkPong(id: ping.id, from: ping.from, by: "ipad", t: ping.t, rt: ControlLinkProtocol.nowMillis())
        guard let data = try? JSONEncoder().encode(pong) else { return }
        client.publish(topic: ControlLinkProtocol.pongTopic, payload: data)
    }

}
