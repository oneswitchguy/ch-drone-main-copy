//
//  ControlLinkSession.swift
//  CH Drone
//

import Combine
import Foundation
import os

/// Owns the control link for the app, and is what the simulator's link button talks to.
///
/// ``ControlLinkClient`` is deliberately unaware of whether anyone wants it running. This
/// wraps it with the enabled flag and republishes the connection state on the main queue,
/// so SwiftUI has something to observe and the send path has one place to ask.
///
/// The flag is persisted but **defaults to off**: this is a test-phase feature, and a
/// practice session should not start advertising itself on the local network because a
/// pilot happened to open the simulator.
///
/// Threading: ``setEnabled(_:)``, ``toggle()`` and the published properties are main-queue
/// only, like the rest of the view models here. ``send(controlsState:source:)`` is the
/// exception — it is called from the flight send timer's own queue at 10 Hz, so the flag it
/// reads is mirrored into a lock rather than read off `isEnabled`.
final class ControlLinkSession: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var connectionState: ControlLinkConnectionState = .idle

    init(client: ControlLinkClient = ControlLinkClient(), userDefaults: UserDefaults = .standard) {
        let enabled = userDefaults.isControlLinkEnabled

        self.client = client
        self.userDefaults = userDefaults
        self.isEnabled = enabled
        self.isEnabledForSending = OSAllocatedUnfairLock(initialState: enabled)

        client.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)

        if enabled {
            client.start()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        isEnabled = enabled
        isEnabledForSending.withLock { $0 = enabled }
        userDefaults.isControlLinkEnabled = enabled

        if enabled {
            client.start()
        } else {
            client.stop()
            connectionState = .idle
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Forwards the current stick positions to the receiver.
    ///
    /// Dropped entirely when the link is off, which keeps the cost of the disabled case —
    /// every flight, for every pilot who never turns this on — to one lock read.
    func send(controlsState: VirtualControlsState, source: String?) {
        guard isEnabledForSending.withLock({ $0 }) else { return }

        client.sendControlState(
            controlsState: controlsState,
            isActive: controlsState != .stopped,
            source: source
        )
    }

    // MARK: - Private

    private let client: ControlLinkClient
    private let userDefaults: UserDefaults
    private let isEnabledForSending: OSAllocatedUnfairLock<Bool>
    private var cancellables: [AnyCancellable] = []

}
