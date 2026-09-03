//
//  SimulatorScene.swift
//  CH Drone
//

import Foundation
import RealityKit
import UIKit

/// Builds and drives the RealityKit scene the simulator flies in.
///
/// Everything here is generated in code — there are no model files, textures or asset
/// catalogues to keep in step. That is a deliberate constraint: the scene has one job,
/// which is to make motion and orientation legible, and procedural geometry does that
/// without an asset pipeline to maintain.
///
/// Entities are mutated directly from ``update(with:)`` rather than through SwiftUI state,
/// so the 60 Hz flight model does not drive a view refresh on every frame.
///
/// ## Frames
///
/// ``FlightModel`` works in East-North-Up. RealityKit is Y-up with -Z forward, so north is
/// mapped to -Z and the conversion is `(east, up, -north)`. Compass headings run clockwise
/// while rotation about +Y runs anticlockwise, hence the negated yaw.
@MainActor
final class SimulatorScene {

    /// Everything in the scene hangs off this.
    let root = Entity()

    init() {
        buildGround()
        buildGrid()
        buildPylons()
        buildHomePad()
        buildAircraft()
        buildCamera()

        update(with: .landed)
    }

    /// Moves the aircraft and camera to match `state`.
    func update(with state: FlightModel.State) {
        let position = Self.renderPosition(state.position)

        aircraft.position = position
        aircraft.orientation = Self.orientation(
            heading: state.heading,
            pitch: state.pitch,
            roll: state.roll
        )

        // The rotors spin faster under power, which reads as effort without meaning
        // anything — the model has no concept of thrust.
        rotorAngle += 0.35 + Float(abs(state.verticalSpeed)) * 0.05
        for rotor in rotors {
            rotor.orientation = simd_quatf(angle: rotorAngle, axis: [0, 1, 0])
        }

        updateShadow(for: state, at: position)
        updateCamera(for: state, at: position)
    }

    /// Snaps the camera straight to its mark, skipping the usual easing.
    ///
    /// Used when the pilot resets, where easing would read as the aircraft flying
    /// backwards at high speed rather than as a reset.
    func recentre(on state: FlightModel.State) {
        hasPlacedCamera = false
        update(with: state)
    }

    // MARK: - Private

    private let aircraft = Entity()
    private let shadow = Entity()
    private let camera = PerspectiveCamera()
    private var rotors: [Entity] = []
    private var rotorAngle: Float = 0
    private var hasPlacedCamera = false

    /// Metres. Larger than a real Mavic, which is about 0.35 m across, because at a
    /// readable chase distance a life-sized airframe is a smudge. Judging absolute
    /// distance matters less here than seeing which way the nose points.
    private static let aircraftSpan: Float = 1.6

    /// Metres behind and above the aircraft.
    private static let chaseDistance: Float = 9
    private static let chaseHeight: Float = 3.5

    // MARK: Scene construction

    private func buildGround() {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 2000, depth: 2000),
            materials: [UnlitMaterial(color: UIColor(white: 0.16, alpha: 1))]
        )
        // Fractionally below zero so the grid does not fight it for depth.
        ground.position = [0, -0.02, 0]
        root.addChild(ground)
    }

    /// A 10 m grid over 400 m.
    ///
    /// Not decoration. A featureless plane gives no sense of speed or drift at all, and
    /// drift is the thing a pilot most needs to notice.
    ///
    /// One merged mesh rather than the 82 entities this used to be. The geometry is
    /// deliberately unchanged — the same boxes at the same positions, built out of quads by
    /// ``MeshBuilder`` instead of `MeshResource.generateBox` — so anything that looks
    /// different after the merge is a bug in the builder rather than a decision.
    private func buildGrid() {
        let extent: Float = 200
        let spacing: Float = 10

        var builder = MeshBuilder()

        var offset = -extent
        while offset <= extent {
            let isMajor = offset.truncatingRemainder(dividingBy: 50) == 0
            let thickness: Float = isMajor ? 0.16 : 0.06
            let material = isMajor ? Self.gridMajor : Self.gridMinor

            builder.addBox(size: [thickness, 0.01, extent * 2], at: [offset, 0, 0], material: material)
            builder.addBox(size: [extent * 2, 0.01, thickness], at: [0, 0, offset], material: material)

            offset += spacing
        }

        guard let mesh = try? builder.meshResource() else {
            // Getting here means ``MeshBuilder`` emitted something invalid, which is what
            // its tests exist to prevent. Loud in development; in a pilot's hands a missing
            // drift cue is bad, but a crash on entering practice mode is worse.
            assertionFailure("MeshBuilder produced an invalid grid mesh")
            return
        }

        let grid = ModelEntity(
            mesh: mesh,
            materials: [
                UnlitMaterial(color: UIColor(white: 0.32, alpha: 1)),
                UnlitMaterial(color: UIColor(white: 0.52, alpha: 1)),
            ]
        )
        root.addChild(grid)
    }

    /// Material slots in the grid mesh, indexing the array handed to the entity above.
    /// Not free to reorder.
    private static let gridMinor = 0
    private static let gridMajor = 1

    /// Landmarks at known bearings, so heading is readable without reading the compass.
    ///
    /// North is deliberately the odd one out — a single tall marker a pilot can orient
    /// against at a glance.
    private func buildPylons() {
        let bearings: [(degrees: Float, height: Float, color: UIColor)] = [
            (0, 30, .systemRed),
            (90, 18, .systemOrange),
            (180, 18, .systemTeal),
            (270, 18, .systemPurple),
        ]

        for bearing in bearings {
            let radians = bearing.degrees * .pi / 180
            let distance: Float = 120

            let pylon = ModelEntity(
                mesh: .generateBox(size: [3, bearing.height, 3]),
                materials: [UnlitMaterial(color: bearing.color)]
            )
            // Compass bearing to RealityKit: north is -Z, east is +X.
            pylon.position = [
                sin(radians) * distance,
                bearing.height / 2,
                -cos(radians) * distance,
            ]
            root.addChild(pylon)
        }

        // A scattering of low blocks to give the near field some texture to move against.
        for index in 0..<40 {
            let angle = Float(index) * 0.618 * 2 * .pi
            let distance = 25 + Float(index) * 2.2
            let height = Float(2 + (index % 5) * 2)

            let block = ModelEntity(
                mesh: .generateBox(size: [4, height, 4]),
                materials: [UnlitMaterial(color: UIColor(white: 0.42, alpha: 1))]
            )
            block.position = [sin(angle) * distance, height / 2, -cos(angle) * distance]
            root.addChild(block)
        }
    }

    private func buildHomePad() {
        let pad = ModelEntity(
            mesh: .generateCylinder(height: 0.05, radius: 3),
            materials: [UnlitMaterial(color: UIColor.systemGreen.withAlphaComponent(0.9))]
        )
        pad.position = [0, 0.03, 0]
        root.addChild(pad)
    }

    private func buildAircraft() {
        let bodyMaterial = UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))
        let armMaterial = UnlitMaterial(color: UIColor(white: 0.55, alpha: 1))
        let rotorMaterial = UnlitMaterial(color: UIColor(white: 0.7, alpha: 1))

        let span = Self.aircraftSpan

        let body = ModelEntity(
            mesh: .generateBox(size: [span * 0.34, span * 0.16, span * 0.55], cornerRadius: 0.05),
            materials: [bodyMaterial]
        )
        aircraft.addChild(body)

        // The nose flash. Which way the aircraft is facing is the single hardest thing to
        // read in flight, so it gets a colour nothing else in the scene uses.
        let nose = ModelEntity(
            mesh: .generateBox(size: [span * 0.2, span * 0.1, span * 0.22]),
            materials: [UnlitMaterial(color: .systemYellow)]
        )
        nose.position = [0, 0, -span * 0.34]
        aircraft.addChild(nose)

        // Arms and rotors, one per corner.
        for x in [-1, 1] as [Float] {
            for z in [-1, 1] as [Float] {
                let offset = SIMD3<Float>(x * span * 0.34, 0, z * span * 0.34)

                let arm = ModelEntity(
                    mesh: .generateBox(size: [span * 0.07, span * 0.05, span * 0.07]),
                    materials: [armMaterial]
                )
                arm.position = offset
                aircraft.addChild(arm)

                let rotor = Entity()
                rotor.position = offset + [0, span * 0.08, 0]

                let disc = ModelEntity(
                    mesh: .generateBox(size: [span * 0.5, span * 0.012, span * 0.05]),
                    materials: [rotorMaterial]
                )
                rotor.addChild(disc)

                aircraft.addChild(rotor)
                rotors.append(rotor)
            }
        }

        root.addChild(aircraft)

        // A ground shadow. Altitude is genuinely hard to judge from a chase camera, and
        // the gap between aircraft and shadow reads as height far better than a number.
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: span * 0.45),
            materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1))]
        )
        shadow.addChild(disc)
        root.addChild(shadow)
    }

    private func buildCamera() {
        camera.camera.fieldOfViewInDegrees = 60
        root.addChild(camera)
    }

    // MARK: Per-frame updates

    private func updateShadow(for state: FlightModel.State, at position: SIMD3<Float>) {
        shadow.position = [position.x, 0.04, position.z]
        shadow.orientation = simd_quatf(angle: Float(-state.heading) * .pi / 180, axis: [0, 1, 0])

        // Fade and shrink with altitude, so the cue degrades the way a real shadow does
        // rather than sitting there at full strength 100 m up.
        let fade = max(0, 1 - Float(state.altitude) / 60)
        shadow.scale = SIMD3(repeating: 0.4 + fade * 0.6)
        shadow.isEnabled = state.altitude < 60
    }

    private func updateCamera(for state: FlightModel.State, at position: SIMD3<Float>) {
        let yaw = simd_quatf(angle: Float(-state.heading) * .pi / 180, axis: [0, 1, 0])
        let offset = yaw.act(SIMD3<Float>(0, Self.chaseHeight, Self.chaseDistance))
        let target = position + offset

        if hasPlacedCamera {
            // Ease toward the mark. A camera pinned rigidly behind the aircraft makes yaw
            // look like the world spinning, which is exactly the confusion this is meant
            // to be teaching a pilot out of.
            camera.position += (target - camera.position) * 0.12
        } else {
            camera.position = target
            hasPlacedCamera = true
        }

        // Look slightly above the aircraft so it sits low in frame, leaving the ground
        // ahead visible.
        camera.look(at: position + [0, 0.6, 0], from: camera.position, relativeTo: nil)
    }

    // MARK: Frame conversion

    private static func renderPosition(_ position: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(position.x), Float(position.z), Float(-position.y))
    }

    private static func orientation(heading: Double, pitch: Double, roll: Double) -> simd_quatf {
        let yawRotation = simd_quatf(angle: Float(-heading) * .pi / 180, axis: [0, 1, 0])
        let pitchRotation = simd_quatf(angle: Float(pitch) * .pi / 180, axis: [1, 0, 0])
        let rollRotation = simd_quatf(angle: Float(-roll) * .pi / 180, axis: [0, 0, 1])
        return yawRotation * pitchRotation * rollRotation
    }

}
