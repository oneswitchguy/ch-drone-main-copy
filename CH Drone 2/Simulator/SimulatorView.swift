//
//  SimulatorView.swift
//  CH Drone
//

import RealityKit
import SwiftUI

/// The simulator's background layer: the RealityKit scene, plus the readouts and the two
/// controls the pilot needs that the switch grid does not already provide.
///
/// Everything here lives in the top strip. The rest of the screen belongs to the switch
/// grid and the joystick, which are the whole point — the simulator exists so those can be
/// practised, not so it can compete with them for space.
struct SimulatorView: View {

    @ObservedObject var viewModel: SimulatorViewModel

    /// Test-phase only. See ``controlLinkButton``.
    @ObservedObject var controlLinkSession: ControlLinkSession

    var body: some View {
        ZStack(alignment: .top) {
            RealityView { content in
                content.add(viewModel.scene.root)

                // The environment belongs to the view's content rather than to the scene
                // graph, so the scene hands over the resource and each view mounts it.
                // There is no flat-colour case on `RealityViewEnvironment` — `.default` or
                // an image, nothing in between — which is why the sky is drawn at all.
                if let sky = viewModel.scene.sky {
                    content.environment = .skybox(sky)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            topStrip
        }
        .background(Color.black)
    }

    // MARK: - Private

    private var state: FlightModel.State { viewModel.displayState }

    private var topStrip: some View {
        HStack(spacing: 16) {
            simulationBadge

            readouts

            Spacer(minLength: 8)

            if state.isCommandSaturated {
                saturationWarning
            }

            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55))
    }

    /// A pilot must never be in any doubt about whether an aircraft is going to move.
    /// This is why it is always on screen and never dims.
    private var simulationBadge: some View {
        Text("SIMULATION", comment: "Always-visible badge marking practice mode")
            .font(.caption.weight(.heavy))
            .monospaced()
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.yellow, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(Text("Simulation mode. No aircraft is connected.", comment: ""))
    }

    private var readouts: some View {
        HStack(spacing: 14) {
            readout(
                label: String(localized: "ALT", comment: "Short label for altitude"),
                value: measurement(state.altitude, unit: "m"),
                accessibility: String(
                    localized: "Altitude \(Int(state.altitude.rounded())) metres",
                    comment: ""
                )
            )
            readout(
                label: String(localized: "SPD", comment: "Short label for ground speed"),
                value: measurement(state.groundSpeed, unit: "m/s"),
                accessibility: String(
                    localized: "Ground speed \(Int(state.groundSpeed.rounded())) metres per second",
                    comment: ""
                )
            )
            readout(
                label: String(localized: "HDG", comment: "Short label for compass heading"),
                value: heading,
                accessibility: String(localized: "Heading \(heading)", comment: "")
            )
            readout(
                label: String(localized: "HOME", comment: "Short label for distance from home"),
                value: measurement(state.distanceFromHome, unit: "m"),
                accessibility: String(
                    localized: "\(Int(state.distanceFromHome.rounded())) metres from home",
                    comment: ""
                )
            )
        }
    }

    private func readout(label: String, value: String, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// Lights when the command exceeds what the aircraft will fly.
    ///
    /// Should never appear at default settings. If it does, a speed multiplier has been set
    /// high enough in the iOS Settings app to command a speed the aircraft will refuse —
    /// see `docs/virtual-stick-command-scaling.md`.
    private var saturationWarning: some View {
        Label {
            Text("At limit", comment: "Shown when the pilot commands more speed than the aircraft allows")
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .accessibilityLabel(Text(
            "Speed limit reached. The aircraft will not fly faster than this, however far the controls are moved.",
            comment: ""
        ))
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            controlLinkButton

            Button(viewModel.primaryActionTitle) {
                viewModel.performPrimaryAction()
            }
            .disabled(!viewModel.isPrimaryActionEnabled)

            Button {
                viewModel.reset()
            } label: {
                Label {
                    Text("Reset", comment: "Returns the simulated aircraft to its starting point")
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            .accessibilityLabel(Text("Reset. Returns the aircraft to the take-off point.", comment: ""))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .font(.callout.weight(.semibold))
    }

    /// Turns the TCP control link to the receiver app on and off.
    ///
    /// **Test phase.** The link streams the stick positions the pilot is commanding to a
    /// second device over the local network; nothing comes back, and nothing about the
    /// simulation depends on it. It lives on the simulator screen because that is where the
    /// link can be exercised without an aircraft in the air.
    ///
    /// Styled as a secondary control so it cannot be mistaken for the flight buttons beside
    /// it, and tinted by connection state rather than by whether it is merely switched on —
    /// "enabled but never found the receiver" is the failure this is most likely to hit.
    private var controlLinkButton: some View {
        Button {
            controlLinkSession.toggle()
        } label: {
            Label {
                Text("Link", comment: "Toggles the test TCP link to the receiver app")
            } icon: {
                Image(systemName: controlLinkIconName)
            }
        }
        .buttonStyle(.bordered)
        .tint(controlLinkTint)
        .accessibilityLabel(Text("Control link", comment: ""))
        .accessibilityValue(Text(controlLinkStatus))
        .accessibilityHint(Text(
            controlLinkSession.isEnabled
                ? String(localized: "Turns off streaming the controls to the receiver app.", comment: "")
                : String(localized: "Streams the controls to the receiver app for testing.", comment: "")
        ))
    }

    private var controlLinkIconName: String {
        guard controlLinkSession.isEnabled else {
            return "antenna.radiowaves.left.and.right.slash"
        }

        switch controlLinkSession.connectionState {
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var controlLinkTint: Color {
        guard controlLinkSession.isEnabled else { return .gray }

        switch controlLinkSession.connectionState {
        case .connected:
            return .green
        case .failed:
            return .orange
        case .idle, .browsing, .connecting:
            return .yellow
        }
    }

    /// Spoken by VoiceOver and, deliberately, the only place the link's state is spelled
    /// out — the icon and tint alone would leave a switch-control pilot guessing.
    private var controlLinkStatus: String {
        guard controlLinkSession.isEnabled else {
            return String(localized: "Off", comment: "Control link is switched off")
        }

        switch controlLinkSession.connectionState {
        case .idle:
            return String(localized: "On, starting up", comment: "")
        case .browsing:
            return String(localized: "On, looking for the receiver app", comment: "")
        case .connecting:
            return String(localized: "On, connecting", comment: "")
        case .connected(let endpoint):
            return String(localized: "Connected to \(endpoint)", comment: "")
        case .failed(let message):
            return String(localized: "Link failed. \(message)", comment: "")
        }
    }

    private var heading: String {
        // Readouts use 0–359, not the model's -180...180, because that is what a compass
        // shows and what the pilot will be comparing against.
        let degrees = (Int(state.heading.rounded()) % 360 + 360) % 360
        return String(format: "%03d°", degrees)
    }

    private func measurement(_ value: Double, unit: String) -> String {
        String(format: "%.0f %@", value, unit)
    }

}
