//
//  MonitorApp.swift
//  Control Link Monitor
//

import SwiftUI

/// Watches the control link on the MQTT broker: whether the iPad is there, what its sticks
/// are doing, and how long the messages take. See `docs/control-link-mqtt.md`.
///
/// Compiles `MQTTPacket.swift`, `MQTTClient.swift` and `ControlLinkProtocol.swift` by
/// reference from the app, so both ends always speak the same protocol.
@main
struct MonitorApp: App {

    @StateObject private var model = MonitorModel()

    var body: some SwiftUI.Scene {
        Window("Control Link Monitor", id: "monitor") {
            MonitorView(model: model)
                .onAppear {
                    // Launch arguments let a script start it already connected, e.g.
                    // `open -a "Control Link Monitor" --args -connect YES`.
                    if UserDefaults.standard.bool(forKey: "connect") {
                        model.start()
                    }
                }
        }
        .windowResizability(.contentMinSize)
    }

}
