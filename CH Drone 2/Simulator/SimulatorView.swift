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

    var body: some View {
        ZStack(alignment: .top) {
            RealityView { content in
                content.add(viewModel.scene.root)
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
