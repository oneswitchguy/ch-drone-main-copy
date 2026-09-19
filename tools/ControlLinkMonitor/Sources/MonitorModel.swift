//
//  MonitorModel.swift
//  Control Link Monitor
//

import AppKit
import Combine
import Foundation

/// Connects to the broker, listens to everything under `chdrone/v1/`, pings five times a
/// second, and feeds ``MonitorStats``.
///
/// Arrival times are taken on the MQTT client's queue the moment a message is decoded,
/// before hopping to the main queue, so a busy UI does not count as network latency.
final class MonitorModel: ObservableObject {

    @Published var host = "127.0.0.1"
    @Published var port = String(ControlLinkProtocol.defaultPort)
    @Published private(set) var isRunning = false
    @Published private(set) var brokerState: MQTTClient.State = .idle
    @Published private(set) var appStatus: ControlLinkStatus?
    /// Republished five times a second rather than on every message, which is plenty to
    /// read and keeps VoiceOver from being flooded.
    @Published private(set) var stats = MonitorStats()
    @Published private(set) var now = MonitorModel.monotonicSeconds()

    init() {
        client.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.brokerState = state }
        }
        client.onMessage = { [weak self] topic, payload in
            self?.handle(topic: topic, payload: payload, arrivedMonotonic: Self.monotonicSeconds(), arrivedWall: Self.wallMillis())
        }
    }

    var brokerAddress: String {
        "\(host):\(port)"
    }

    func toggleConnection() {
        isRunning ? stop() : start()
    }

    func start() {
        guard let port = UInt16(port) else {
            brokerState = .failed("The port must be a number from 1 to 65535")
            return
        }

        client.start(MQTTClient.Configuration(
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            clientID: "chdrone-monitor-\(pingerID.suffix(6))",
            subscriptions: [
                MQTTSubscription(topicFilter: ControlLinkProtocol.stickTopic, qos: .atMostOnce),
                MQTTSubscription(topicFilter: ControlLinkProtocol.statusTopic, qos: .atMostOnce),
                MQTTSubscription(topicFilter: ControlLinkProtocol.pongTopic, qos: .atMostOnce),
            ]
        ))
        isRunning = true

        timer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        client.stop()
        timer = nil
        isRunning = false
        brokerState = .idle
    }

    func resetStats() {
        liveStats.reset()
        stats = liveStats
        pendingPings.withLock { $0.removeAll() }
    }

    func copyReport() {
        let report = liveStats.report(nowMonotonic: Self.monotonicSeconds(), broker: brokerAddress)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    // MARK: - Private

    private struct PendingPing {
        let sentMonotonic: Double
        let sentWallMillis: Double
    }

    private let client = MQTTClient(queueLabel: "ControlLinkMonitor.MQTT")
    /// Tells this monitor's pongs from anyone else's, if two are running.
    private let pingerID = "monitor-" + UUID().uuidString.prefix(8)
    private var timer: AnyCancellable?
    /// Updated on every message, on the main queue; copied to ``stats`` by the timer.
    private var liveStats = MonitorStats()
    private var nextPingID: UInt64 = 0
    private var ticks = 0
    private let pendingPings = LockedDictionary<UInt64, PendingPing>()

    private func tick() {
        now = Self.monotonicSeconds()
        stats = liveStats

        if case .connected = brokerState {
            sendPing()
        }

        ticks += 1
        if ticks % 5 == 0 {
            writeReportIfAsked()
        }
    }

    /// For leaving the monitor running unattended, or scripting it: launched with
    /// `-reportPath <file>`, it rewrites the text report there every second.
    private func writeReportIfAsked() {
        guard let path = UserDefaults.standard.string(forKey: "reportPath") else { return }
        let report = liveStats.report(nowMonotonic: Self.monotonicSeconds(), broker: brokerAddress)
        try? report.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func sendPing() {
        nextPingID += 1
        let sentWall = Self.wallMillis()
        let ping = ControlLinkPing(id: nextPingID, from: pingerID, t: UInt64(sentWall))
        guard let payload = try? JSONEncoder().encode(ping) else { return }

        let pending = PendingPing(sentMonotonic: Self.monotonicSeconds(), sentWallMillis: sentWall)
        pendingPings.withLock { pings in
            pings[ping.id] = pending
            // A pong that has not come back in five seconds is not coming.
            pings = pings.filter { pending.sentMonotonic - $0.value.sentMonotonic < 5 }
        }
        liveStats.recordPingSent()
        client.publish(topic: ControlLinkProtocol.pingTopic, payload: payload)
    }

    /// Runs on the MQTT client's queue.
    private func handle(topic: String, payload: Data, arrivedMonotonic: Double, arrivedWall: Double) {
        let decoder = JSONDecoder()

        switch topic {
        case ControlLinkProtocol.stickTopic:
            guard let stick = try? decoder.decode(ControlLinkStick.self, from: payload) else { return }
            DispatchQueue.main.async { [self] in
                liveStats.recordStick(stick, receivedAtWallMillis: arrivedWall, receivedAtMonotonic: arrivedMonotonic)
            }

        case ControlLinkProtocol.statusTopic:
            let status = try? decoder.decode(ControlLinkStatus.self, from: payload)
            DispatchQueue.main.async { [self] in appStatus = status }

        case ControlLinkProtocol.pongTopic:
            guard let pong = try? decoder.decode(ControlLinkPong.self, from: payload),
                  pong.from == pingerID,
                  let pending = pendingPings.withLock({ $0.removeValue(forKey: pong.id) }) else { return }

            let roundTrip = (arrivedMonotonic - pending.sentMonotonic) * 1_000
            DispatchQueue.main.async { [self] in
                liveStats.recordPong(pong, roundTripMillis: roundTrip, sentAtWallMillis: pending.sentWallMillis)
            }

        default:
            break
        }
    }

    static func monotonicSeconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private static func wallMillis() -> Double {
        Date().timeIntervalSince1970 * 1_000
    }

}

/// A dictionary shared between the main queue, which sends pings, and the MQTT queue,
/// which matches the pongs.
private final class LockedDictionary<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private let lock = NSLock()

    func withLock<Result>(_ body: (inout [Key: Value]) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}
