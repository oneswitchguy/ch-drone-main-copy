//
//  MQTTClient.swift
//  CH Drone
//

import Foundation
import Network

/// A small MQTT 3.1.1 client over one TCP connection: connect with a Will, publish, answer
/// what arrives on its subscriptions, keep alive, and reconnect until stopped.
///
/// Built on `NWConnection` with Nagle's algorithm off (`noDelay`), because the control link
/// streams small messages at 10 Hz and exists partly to measure latency. Batching would add
/// delay whenever an earlier message is still unacknowledged.
///
/// Everything runs on one private serial queue, and the callbacks are called on it too.
/// Set them before ``start(_:)``. No UIKit or DJI imports: the Mac monitor in
/// `tools/ControlLinkMonitor` compiles this file by reference.
///
/// QoS 1 is acknowledged but not retried. The link sends it only for the retained status,
/// which is published again on every connect anyway.
final class MQTTClient {

    struct Configuration: Equatable {
        var host: String
        var port: UInt16
        var clientID: String
        var keepAlive: UInt16 = 5
        var will: MQTTWill?
        /// Subscribed again after every connect, since sessions are clean.
        var subscriptions: [MQTTSubscription] = []
    }

    enum State: Equatable {
        case idle
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    /// Called on the client's queue whenever the state changes.
    var onStateChange: ((State) -> Void)?
    /// Called on the client's queue once the broker has accepted the connection, after the
    /// subscriptions have been sent. Publishing from here goes straight out.
    var onConnect: (() -> Void)?
    /// Called on the client's queue for every message arriving on a subscription.
    var onMessage: ((_ topic: String, _ payload: Data) -> Void)?

    init(queueLabel: String = "CHDrone.MQTT") {
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    func start(_ configuration: Configuration) {
        queue.async { [self] in
            self.configuration = configuration
            isStarted = true
            reconnectDelay = Self.initialReconnectDelay
            tearDownConnection()
            connect()
        }
    }

    /// Sends DISCONNECT, so the broker does **not** publish the Will, then closes. Anything
    /// published just before this goes out first, because both are on the same queue.
    func stop() {
        queue.async { [self] in
            isStarted = false
            reconnectWork?.cancel()
            reconnectWork = nil

            if let connection, isConnected, let disconnect = try? MQTTPacket.disconnect.encoded() {
                connection.send(content: disconnect, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.connection = nil
                stopTimers()
            } else {
                tearDownConnection()
            }

            isConnected = false
            setState(.idle)
        }
    }

    func publish(topic: String, payload: Data, qos: MQTTQoS = .atMostOnce, retain: Bool = false) {
        queue.async { [self] in
            guard isConnected else { return }

            let packet = MQTTPacket.publish(
                topic: topic,
                payload: payload,
                qos: qos,
                retain: retain,
                packetID: qos == .atMostOnce ? nil : nextPacketID()
            )
            send(packet)
        }
    }

    // MARK: - Private

    private static let initialReconnectDelay: TimeInterval = 0.5
    private static let maximumReconnectDelay: TimeInterval = 5
    private static let connackTimeout: TimeInterval = 5

    private let queue: DispatchQueue

    private var configuration: Configuration?
    private var isStarted = false
    private var isConnected = false
    private var connection: NWConnection?
    private var decoder = MQTTPacketDecoder()
    private var packetID: UInt16 = 0
    private var reconnectDelay = initialReconnectDelay
    private var reconnectWork: DispatchWorkItem?
    private var connackTimer: DispatchSourceTimer?
    private var keepAliveTimer: DispatchSourceTimer?
    private var lastInbound = Date()

    private func setState(_ state: State) {
        onStateChange?(state)
    }

    private func connect() {
        guard isStarted, let configuration else { return }

        guard !configuration.host.isEmpty, let port = NWEndpoint.Port(rawValue: configuration.port) else {
            setState(.failed("Invalid broker address"))
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = Int(Self.connackTimeout)
        let parameters = NWParameters(tls: nil, tcp: tcp)

        let connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: parameters)
        let address = "\(configuration.host):\(configuration.port)"

        self.connection = connection
        decoder = MQTTPacketDecoder()
        isConnected = false
        lastInbound = Date()
        setState(.connecting(address))

        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            guard let self, let connection, connection === self.connection else { return }

            switch newState {
            case .ready:
                self.handleTransportReady(connection, configuration: configuration)
            case .waiting(let error), .failed(let error):
                // `.waiting` means no route to the broker yet. Retrying on our own schedule
                // keeps the state honest instead of sitting in "connecting" indefinitely.
                self.fail(Self.describe(error, address: address))
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func handleTransportReady(_ connection: NWConnection, configuration: Configuration) {
        receive(on: connection)

        send(.connect(
            clientID: configuration.clientID,
            keepAlive: configuration.keepAlive,
            cleanSession: true,
            will: configuration.will
        ))

        connackTimer = makeTimer(after: Self.connackTimeout) { [weak self] in
            self?.fail("The broker did not answer")
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, connection === self.connection else { return }

            if let data, !data.isEmpty {
                do {
                    for packet in try decoder.append(data) {
                        handle(packet)
                    }
                } catch {
                    fail("Unreadable data from the broker")
                    return
                }
            }

            if let error {
                fail(error.localizedDescription)
            } else if isComplete {
                fail("The broker closed the connection")
            } else if connection === self.connection {
                receive(on: connection)
            }
        }
    }

    private func handle(_ packet: MQTTPacket) {
        lastInbound = Date()

        switch packet {
        case let .connack(_, returnCode):
            connackTimer?.cancel()
            connackTimer = nil

            guard returnCode == 0 else {
                fail("The broker refused the connection (code \(returnCode))")
                return
            }
            handleConnected()

        case let .publish(topic, payload, qos, _, packetID):
            if qos == .atLeastOnce, let packetID {
                send(.puback(packetID: packetID))
            }
            onMessage?(topic, payload)

        case .puback, .suback, .pingresp:
            break

        case .connect, .subscribe, .pingreq, .disconnect:
            break
        }
    }

    private func handleConnected() {
        guard let configuration else { return }

        isConnected = true
        reconnectDelay = Self.initialReconnectDelay
        setState(.connected("\(configuration.host):\(configuration.port)"))

        if !configuration.subscriptions.isEmpty {
            send(.subscribe(packetID: nextPacketID(), subscriptions: configuration.subscriptions))
        }

        startKeepAlive(interval: TimeInterval(configuration.keepAlive))
        onConnect?()
    }

    /// Pings at half the keepalive, so the broker never sees a silent client. Treats the
    /// connection as dead if nothing at all has come back in one and a half keepalives,
    /// the same allowance the broker gives the client.
    private func startKeepAlive(interval: TimeInterval) {
        guard interval > 0 else { return }

        keepAliveTimer = makeTimer(after: interval / 2, repeating: interval / 2) { [weak self] in
            guard let self else { return }

            if Date().timeIntervalSince(lastInbound) > interval * 1.5 {
                fail("The broker stopped answering")
            } else {
                send(.pingreq)
            }
        }
    }

    private func send(_ packet: MQTTPacket) {
        guard let connection else { return }

        let data: Data
        do {
            data = try packet.encoded()
        } catch {
            return
        }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, let error, connection === self.connection else { return }
            fail(error.localizedDescription)
        })
    }

    private func fail(_ reason: String) {
        guard connection != nil else { return }

        tearDownConnection()
        isConnected = false
        setState(.failed(reason))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isStarted else { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maximumReconnectDelay)

        let work = DispatchWorkItem { [weak self] in
            guard let self, isStarted, connection == nil else { return }
            connect()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func tearDownConnection() {
        stopTimers()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func stopTimers() {
        connackTimer?.cancel()
        connackTimer = nil
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    /// The state is spoken by VoiceOver on the simulator's Link button, so the common
    /// failures get a sentence rather than `NWError`'s own description.
    private static func describe(_ error: NWError, address: String) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            return "Nothing is listening at \(address). Is the broker running?"
        case .posix(.ETIMEDOUT), .posix(.EHOSTUNREACH), .posix(.ENETUNREACH), .posix(.EHOSTDOWN):
            return "Cannot reach \(address)"
        case .dns:
            return "Cannot find \(address) on the network"
        default:
            return error.localizedDescription
        }
    }

    private func nextPacketID() -> UInt16 {
        // Zero is not a valid packet identifier.
        packetID = packetID == UInt16.max ? 1 : packetID + 1
        return packetID
    }

    private func makeTimer(after delay: TimeInterval, repeating interval: TimeInterval? = nil, handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        if let interval {
            timer.schedule(deadline: .now() + delay, repeating: interval)
        } else {
            timer.schedule(deadline: .now() + delay)
        }
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

}
