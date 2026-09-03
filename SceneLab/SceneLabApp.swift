//
//  SceneLabApp.swift
//  SceneLab
//

import QuartzCore
import RealityKit
import SwiftUI

/// A bare harness for looking at ``SimulatorScene``.
///
/// The app target links the DJI SDK, which ships an x86_64-only simulator slice, so no
/// arm64 iPad simulator is a valid destination for anything that links it. Until this
/// target existed, the only way to see a change to the simulator's scene was to sign the
/// app, install it on an iPad and launch practice mode — a poor loop for work that is
/// entirely a matter of judging how something looks.
///
/// Nothing in ``SimulatorScene`` or ``FlightModel`` needs the SDK. So this target compiles
/// those two files, and the ``VirtualStickLimits`` they share, **by reference** — there are
/// no copies here and no second source of truth. It links nothing, which is what lets it
/// run in the simulator and in Previews.
///
/// It ships to nobody. Deleting this file and the target leaves the app untouched.
@main
struct SceneLabApp: App {

    // `Scene` has to be qualified: RealityKit declares one too, and this file imports both.
    var body: some SwiftUI.Scene {
        WindowGroup {
            SceneLabView()
        }
    }

}

// MARK: -

/// Drives ``SimulatorScene`` two ways.
///
/// **Pose** puts the aircraft at a position you scrub with sliders and snaps the camera to
/// it, which is how you judge a thing that does not move: the horizon seam at altitude, the
/// pylons on a bearing, the airframe from underneath.
///
/// **Circuit** flies a canned route through the real ``FlightModel`` at the display rate,
/// which is how you judge the things that only exist in motion: whether the grid still
/// reads as a drift cue, whether the near field has anything to move against.
@MainActor
final class SceneLabHarness: ObservableObject {

    let scene = SimulatorScene()

    /// What the readouts show. Throttled off the display rate for the same reason
    /// `SimulatorViewModel` throttles its own: SwiftUI has no business laying out four
    /// numbers sixty times a second.
    @Published private(set) var readout: FlightModel.State = .landed

    @Published private(set) var isFlyingCircuit = false

    /// What the circuit is doing, so it is obvious whether a wobble is the model or the eye.
    @Published private(set) var legLabel = ""

    // MARK: Pose controls

    @Published var altitude: Double = 25 { didSet { applyPose() } }
    @Published var distance: Double = 40 { didSet { applyPose() } }
    @Published var heading: Double = 0 { didSet { applyPose() } }
    @Published var bank: Double = 0 { didSet { applyPose() } }

    init() {
        // Launch arguments override the starting pose, so a scripted run can put the camera
        // somewhere specific before it screenshots. `-altitude 150 -distance 0` looks
        // straight down at the whole grid, which is the view that catches a geometry
        // regression the default pose would hide.
        let defaults = UserDefaults.standard
        for key in ["altitude", "distance", "heading", "bank"] where defaults.object(forKey: key) != nil {
            let value = defaults.double(forKey: key)
            switch key {
            case "altitude": altitude = value
            case "distance": distance = value
            case "heading": heading = value
            default: bank = value
            }
        }

        applyPose()
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: Actions

    func flyCircuit() {
        guard !isFlyingCircuit else { return }

        model = FlightModel()
        legIndex = 0
        legElapsed = 0
        readoutElapsed = 0
        lastTimestamp = nil
        isFlyingCircuit = true
        scene.recentre(on: model.state)

        let link = CADisplayLink(
            target: DisplayLinkProxy(target: self),
            selector: #selector(DisplayLinkProxy.tick)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopCircuit() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        isFlyingCircuit = false
        legLabel = ""
        applyPose()
    }

    /// Snaps the camera back behind the aircraft without moving anything.
    func recentre() {
        scene.recentre(on: isFlyingCircuit ? model.state : readout)
    }

    // MARK: - Private

    private var model = FlightModel()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var legIndex = 0
    private var legElapsed: TimeInterval = 0
    private var readoutElapsed: TimeInterval = 0

    /// One leg of the canned circuit.
    ///
    /// Take-off and landing are phase changes rather than durations — the model decides
    /// when they are done — so they are their own cases rather than a command held for a
    /// guessed number of seconds.
    private enum Leg {
        case takeOff
        case fly(FlightModel.Command, seconds: TimeInterval, label: String)
        case land
    }

    /// Climb out, a box with a turn at each corner, then home and down.
    ///
    /// Chosen so that everything in the scene gets looked at from the air, and each corner
    /// puts a different pylon ahead of the nose. Speeds are well inside the envelope, so
    /// nothing here is testing the clamps — `FlightModelTests` does that.
    private static let circuit: [Leg] = [
        .takeOff,
        .fly(FlightModel.Command(up: 2), seconds: 5, label: "Climb"),
        .fly(FlightModel.Command(forward: 7), seconds: 8, label: "Outbound"),
        .fly(FlightModel.Command(forward: 3, yawRate: 45), seconds: 2, label: "Corner 1"),
        .fly(FlightModel.Command(forward: 7), seconds: 6, label: "Crosswind"),
        .fly(FlightModel.Command(forward: 3, yawRate: 45), seconds: 2, label: "Corner 2"),
        .fly(FlightModel.Command(forward: 7), seconds: 6, label: "Downwind"),
        .fly(FlightModel.Command(forward: 3, yawRate: 45), seconds: 2, label: "Corner 3"),
        .fly(FlightModel.Command(forward: 7), seconds: 6, label: "Base"),
        .fly(FlightModel.Command(forward: 3, yawRate: 45), seconds: 2, label: "Corner 4"),
        .fly(FlightModel.Command(forward: 5, up: -1.5), seconds: 8, label: "Descending"),
        .fly(FlightModel.Command(), seconds: 2, label: "Settling"),
        .land,
    ]

    private func applyPose() {
        guard !isFlyingCircuit else { return }

        // East-North-Up, origin at the take-off point. Flying out along the current heading
        // is the arrangement a pilot would actually be in, and it keeps one slider doing one
        // job instead of needing a separate bearing.
        let radians = heading * .pi / 180

        var state = FlightModel.State()
        state.position = SIMD3(sin(radians) * distance, cos(radians) * distance, altitude)
        state.heading = heading
        state.roll = bank
        state.phase = altitude > 0.1 ? .flying : .landed

        readout = state
        scene.recentre(on: state)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }

        guard let lastTimestamp else { return }

        // Clamp the step exactly as `SimulatedFlightController` does. Coming back from the
        // background produces one enormous interval, which would otherwise teleport the
        // aircraft.
        let interval = min(link.timestamp - lastTimestamp, 1.0 / 20)

        advanceCircuit(by: interval)
        scene.update(with: model.state)

        readoutElapsed += interval
        if readoutElapsed >= 0.1 {
            readoutElapsed = 0
            readout = model.state
        }
    }

    private func advanceCircuit(by interval: TimeInterval) {
        guard legIndex < Self.circuit.count else {
            model.advance(by: interval)
            return
        }

        switch Self.circuit[legIndex] {
        case .takeOff:
            if model.state.phase == .landed {
                model.takeOff()
                legLabel = "Taking off"
            }
            model.advance(by: interval)
            if model.state.phase == .flying {
                nextLeg()
            }

        case let .fly(command, seconds, label):
            if legLabel != label {
                legLabel = label
            }
            model.advance(by: interval, command: command)
            legElapsed += interval
            if legElapsed >= seconds {
                nextLeg()
            }

        case .land:
            if model.state.phase == .flying {
                model.land()
                legLabel = "Landing"
            }
            model.advance(by: interval)
            if model.state.phase == .landed {
                readout = model.state
                legLabel = "Down"
                displayLink?.invalidate()
                displayLink = nil
                isFlyingCircuit = false
            }
        }
    }

    private func nextLeg() {
        legIndex += 1
        legElapsed = 0
    }

}

// MARK: -

/// Holds the harness weakly on behalf of its display link.
///
/// Same reason `SimulatedFlightController` has one: `CADisplayLink` retains its target, so
/// targeting the harness directly would make it immortal and the circuit would go on
/// flying for the life of the process.
private final class DisplayLinkProxy {

    weak var target: SceneLabHarness?

    init(target: SceneLabHarness) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let target else {
            link.invalidate()
            return
        }
        MainActor.assumeIsolated {
            target.tick(link)
        }
    }

}

// MARK: -

struct SceneLabView: View {

    @StateObject private var harness = SceneLabHarness()

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                content.add(harness.scene.root)
            }
            .ignoresSafeArea()

            panel
                .padding(16)
        }
        .background(Color.black)
        .task {
            // `xcrun simctl launch <device> com.christopherhills.SceneLab -flyOnLaunch YES`
            // flies the circuit with nothing to tap, which is what makes build → launch →
            // screenshot scriptable. That loop is the whole reason this target exists, so it
            // is worth the four lines.
            if UserDefaults.standard.bool(forKey: "flyOnLaunch") {
                harness.flyCircuit()
            }
        }
    }

    // MARK: - Private

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            readouts

            Divider()

            if harness.isFlyingCircuit {
                Text(harness.legLabel)
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                sliders
            }

            buttons
        }
        .padding(14)
        .frame(width: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var readouts: some View {
        HStack(alignment: .top, spacing: 16) {
            readout("ALT", String(format: "%.0f m", harness.readout.altitude))
            readout("SPD", String(format: "%.1f m/s", harness.readout.groundSpeed))
            readout("HDG", String(format: "%03d°", compassHeading))
            readout("HOME", String(format: "%.0f m", harness.readout.distanceFromHome))
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            slider("Altitude", value: $harness.altitude, in: 0...200, unit: "m")
            slider("Distance", value: $harness.distance, in: 0...300, unit: "m")
            slider("Heading", value: $harness.heading, in: -180...180, unit: "°")
            slider("Bank", value: $harness.bank, in: -35...35, unit: "°")
        }
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.0f %@", value.wrappedValue, unit))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(harness.isFlyingCircuit ? "Stop" : "Fly circuit") {
                if harness.isFlyingCircuit {
                    harness.stopCircuit()
                } else {
                    harness.flyCircuit()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Recentre") {
                harness.recentre()
            }
            .buttonStyle(.bordered)
        }
        .font(.callout.weight(.semibold))
        .controlSize(.small)
    }

    /// Readouts use 0–359 rather than the model's -180...180, matching `SimulatorView`.
    private var compassHeading: Int {
        (Int(harness.readout.heading.rounded()) % 360 + 360) % 360
    }

}

#Preview {
    SceneLabView()
}
