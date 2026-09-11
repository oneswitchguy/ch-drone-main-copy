//
//  ControlLinkClient.swift
//  CH Drone
//
//

import Foundation
import Network

/// Browses for the receiver app over Bonjour and streams control state to it.
///
/// Ported unchanged from the playground clone apart from `sendControlState`'s `source`
/// parameter, which is a `String` here — see `ControlLinkProtocol.swift`.

enum ControlLinkConnectionState: Equatable {
    case idle
    case browsing
    case connecting(String)
    case connected(String)
    case failed(String)
}

final class ControlLinkClient {

    @ValueSubject private(set) var state: ControlLinkConnectionState = .idle

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard browser == nil else { return }

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            let browser = NWBrowser(
                for: .bonjour(type: ControlLinkProtocol.serviceType, domain: nil),
                using: parameters
            )

            browser.stateUpdateHandler = { [weak self] browserState in
                self?.handleBrowserState(browserState)
            }

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.handleBrowseResults(results)
            }

            self.browser = browser
            self.state = .browsing
            browser.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    func sendControlState(
        controlsState: VirtualControlsState,
        isActive: Bool,
        source: String?
    ) {
        let payload = ControlLinkProtocol.makeControlStatePayload(
            sessionID: sessionID,
            controlsState: controlsState,
            isActive: isActive,
            source: source
        )
        send(messageType: .controlState, payload: payload)
    }

    deinit {
        stopLocked()
    }

    private let queue = DispatchQueue(label: "CHDrone.ControlLink", qos: .userInitiated)
    private let encoder = JSONEncoder()
    private let sessionID = UUID()

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var heartbeatTimer: DispatchSourceTimer?
    private var sequence: UInt64 = 0
    private var lastSentControlState: ControlLinkControlStatePayload?

    private func stopLocked() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil

        connection?.cancel()
        connection = nil

        browser?.cancel()
        browser = nil

        state = .idle
    }

    private func handleBrowserState(_ browserState: NWBrowser.State) {
        switch browserState {
        case .ready:
            state = .browsing
        case .failed(let error):
            state = .failed(error.localizedDescription)
            browser?.cancel()
            browser = nil
        case .cancelled:
            if connection == nil {
                state = .idle
            }
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard connection == nil else {
            return
        }

        guard let result = results.sorted(by: { $0.endpoint.debugDescription < $1.endpoint.debugDescription }).first else {
            return
        }

        connect(to: result.endpoint)
    }

    private func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        let endpointDescription = endpoint.debugDescription

        state = .connecting(endpointDescription)

        connection.stateUpdateHandler = { [weak self] connectionState in
            self?.handleConnectionState(connectionState, endpointDescription: endpointDescription)
        }

        self.connection = connection
        connection.start(queue: queue)
    }

    private func handleConnectionState(_ connectionState: NWConnection.State, endpointDescription: String) {
        switch connectionState {
        case .ready:
            state = .connected(endpointDescription)
            sendHello()
            startHeartbeat()
            resendLastControlStateIfNeeded()
        case .failed(let error):
            state = .failed(error.localizedDescription)
            reconnect()
        case .cancelled:
            reconnect()
        default:
            break
        }
    }

    private func reconnect() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        connection = nil

        guard browser != nil else {
            state = .idle
            return
        }

        state = .browsing
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.sendHeartbeat()
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func resendLastControlStateIfNeeded() {
        guard let lastSentControlState else {
            return
        }

        send(messageType: .controlState, payload: lastSentControlState)
    }

    private func sendHello() {
        send(messageType: .hello, payload: ControlLinkProtocol.makeHelloPayload(sessionID: sessionID))
    }

    private func sendHeartbeat() {
        send(messageType: .heartbeat, payload: ControlLinkProtocol.makeHeartbeatPayload(sessionID: sessionID))
    }

    private func send<Payload: Encodable>(messageType: ControlLinkMessageType, payload: Payload) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let connection else { return }

            do {
                let frame = try ControlLinkProtocol.encodeFrame(
                    type: messageType,
                    payload: payload,
                    sequence: nextSequence(),
                    encoder: encoder
                )

                connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if let error {
                        self.state = .failed(error.localizedDescription)
                        self.reconnect()
                    }
                })

                if let payload = payload as? ControlLinkControlStatePayload {
                    lastSentControlState = payload
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func nextSequence() -> UInt64 {
        sequence += 1
        return sequence
    }
}
