//
//  UserDefaults+Settings.swift
//  CH Drone
//
//  Created by Alex Robinson on 30/11/21.
//

import Foundation

extension UserDefaults {

    func registerSettingsDefaults() {
        register(defaults: [
            #selector(getter: UserDefaults.isCustomScanningEnabled).description: true,
            #selector(getter: UserDefaults.customAutoScanningTime).description: 0.5,
            #selector(getter: UserDefaults.minimumLongPressDuration).description: 0.2,
            #selector(getter: UserDefaults.clearCommandsOnRelease).description: true,
            #selector(getter: UserDefaults.videoFeedEnabled).description: true,
            // Off unless asked for: the control link is a test-phase feature, and enabling
            // it connects out to a broker on the local network.
            #selector(getter: UserDefaults.isControlLinkEnabled).description: false,
            #selector(getter: UserDefaults.controlLinkBrokerHost).description: UserDefaults.defaultControlLinkBrokerHost,
            #selector(getter: UserDefaults.controlLinkBrokerPort).description: Int(ControlLinkProtocol.defaultPort),
            #selector(getter: UserDefaults.airPodsPitchSensitivity).description: 1.0,
            #selector(getter: UserDefaults.airPodsYawSensitivity).description: 1.0,

            #selector(getter: UserDefaults.slowestMultiplier).description: 0.5,
            #selector(getter: UserDefaults.slowMultiplier).description: 0.75,
            #selector(getter: UserDefaults.mediumMultiplier).description: 1,
            #selector(getter: UserDefaults.fastMultiplier).description: 1.5,
            #selector(getter: UserDefaults.fastestMultiplier).description: 2,

            #selector(getter: UserDefaults.gamepadJoystickReleaseRestingPeriod).description: 0.5,
        ])
    }

    @objc(CHDMinimumLongPressDuration)
    var minimumLongPressDuration: TimeInterval {
        get { sanitizedDouble(forKey: "CHDMinimumLongPressDuration") }
        set { set(newValue, forKey: "CHDMinimumLongPressDuration") }
    }

    @objc(CHDCustomScanningEnabled)
    var isCustomScanningEnabled: Bool {
        get { bool(forKey: "CHDCustomScanningEnabled") }
        set { set(newValue, forKey: "CHDCustomScanningEnabled") }
    }

    @objc(CHDAutoScanningTime)
    var customAutoScanningTime: TimeInterval {
        get { sanitizedDouble(forKey: "CHDAutoScanningTime") }
        set { set(newValue, forKey: "CHDAutoScanningTime") }
    }

    @objc(CHDClearCommandsOnRelease)
    var clearCommandsOnRelease: Bool {
        get { bool(forKey: "CHDClearCommandsOnRelease") }
        set { set(newValue, forKey: "CHDClearCommandsOnRelease") }
    }

    @objc(CHDVideoFeedEnabled)
    var videoFeedEnabled: Bool {
        get { bool(forKey: "CHDVideoFeedEnabled") }
        set { set(newValue, forKey: "CHDVideoFeedEnabled") }
    }

    /// Whether the control link streams stick state to the MQTT broker.
    ///
    /// The key name dates from the TCP link, and still matches the playground clone's.
    @objc(CHDControlLinkEnabled)
    var isControlLinkEnabled: Bool {
        get { bool(forKey: "CHDControlLinkEnabled") }
        set { set(newValue, forKey: "CHDControlLinkEnabled") }
    }

    /// Christopher's Mac, which runs Mosquitto while the link is being tested.
    static let defaultControlLinkBrokerHost = "Christophers-MacBook-Pro-5.local"

    /// The MQTT broker the control link connects to. Typed into the Settings app, which
    /// cannot validate, so a blank value falls back to the default here.
    @objc(CHDControlLinkBrokerHost)
    var controlLinkBrokerHost: String {
        get {
            let host = string(forKey: "CHDControlLinkBrokerHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return host.isEmpty ? Self.defaultControlLinkBrokerHost : host
        }
        set { set(newValue, forKey: "CHDControlLinkBrokerHost") }
    }

    /// The broker's port. Settings stores the field as text; anything that is not a valid
    /// port falls back to MQTT's standard 1883.
    @objc(CHDControlLinkBrokerPort)
    var controlLinkBrokerPort: UInt16 {
        get {
            let port = integer(forKey: "CHDControlLinkBrokerPort")
            return (1...Int(UInt16.max)).contains(port) ? UInt16(port) : ControlLinkProtocol.defaultPort
        }
        set { set(Int(newValue), forKey: "CHDControlLinkBrokerPort") }
    }

    @objc(CHDAirPodsPitchSensitivity)
    var airPodsPitchSensitivity: Double {
        get { sanitizedDouble(forKey: "CHDAirPodsPitchSensitivity") }
        set { set(newValue, forKey: "CHDAirPodsPitchSensitivity") }
    }

    @objc(CHDAirPodsYawSensitivity)
    var airPodsYawSensitivity: Double {
        get { sanitizedDouble(forKey: "CHDAirPodsYawSensitivity") }
        set { set(newValue, forKey: "CHDAirPodsYawSensitivity") }
    }

    @objc(CHDGamepadJoystickReleaseRestingPeriod)
    var gamepadJoystickReleaseRestingPeriod: TimeInterval {
        get { sanitizedDouble(forKey: "CHDGamepadJoystickReleaseRestingPeriod") }
        set { set(newValue, forKey: "CHDGamepadJoystickReleaseRestingPeriod") }
    }

    // MARK: - Command Speeds

    @objc(CHDSlowestMultiplier)
    var slowestMultiplier: Float {
        get { sanitizedMultiplier(forKey: "CHDSlowestMultiplier") }
        set { set(newValue, forKey: "CHDSlowestMultiplier") }
    }

    @objc(CHDSlowMultiplier)
    var slowMultiplier: Float {
        get { sanitizedMultiplier(forKey: "CHDSlowMultiplier") }
        set { set(newValue, forKey: "CHDSlowMultiplier") }
    }

    @objc(CHDMediumMultiplier)
    var mediumMultiplier: Float {
        get { sanitizedMultiplier(forKey: "CHDMediumMultiplier") }
        set { set(newValue, forKey: "CHDMediumMultiplier") }
    }

    @objc(CHDFastMultiplier)
    var fastMultiplier: Float {
        get { sanitizedMultiplier(forKey: "CHDFastMultiplier") }
        set { set(newValue, forKey: "CHDFastMultiplier") }
    }

    @objc(CHDFastestMultiplier)
    var fastestMultiplier: Float {
        get { sanitizedMultiplier(forKey: "CHDFastestMultiplier") }
        set { set(newValue, forKey: "CHDFastestMultiplier") }
    }

}

private extension UserDefaults {

    /// Reads a speed multiplier, bounded to `MovementMultipliers.allowedRange`.
    ///
    /// Clamping happens on read rather than on write because the iOS Settings app writes
    /// to these keys directly — a setter here would never see the value. A number outside
    /// the range therefore stays visible in Settings while having no effect beyond the
    /// bound, which is the safe way round.
    func sanitizedMultiplier(forKey key: String) -> Float {
        sanitizedFloat(forKey: key).clamped(to: MovementMultipliers.allowedRange)
    }

    func sanitizedFloat(forKey key: String) -> Float {
        func assignDefaultValue() {
            // rely on registered defaults
            setValue(nil, forKey: key)
            setValue(float(forKey: key), forKey: key)
        }

        // empty value
        if value(forKey: key) == nil {
            assignDefaultValue()
        }

        // non-float value
        if let stringValue = string(forKey: key) {
            if stringValue.isEmpty || Float(stringValue) == nil {
                assignDefaultValue()
            }
        }

        return float(forKey: key)
    }

    func sanitizedDouble(forKey key: String) -> Double {
        func assignDefaultValue() {
            // rely on registered defaults
            setValue(nil, forKey: key)
            setValue(double(forKey: key), forKey: key)
        }

        // empty value
        if value(forKey: key) == nil {
            assignDefaultValue()
        }

        // non-float value
        if let stringValue = string(forKey: key) {
            if stringValue.isEmpty || Double(stringValue) == nil {
                assignDefaultValue()
            }
        }

        return double(forKey: key)
    }

}
