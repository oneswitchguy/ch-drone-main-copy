//
//  SimulatorScene.swift
//  CH Drone
//

import Foundation
import RealityKit
import UIKit

/// Builds and drives the RealityKit scene the simulator flies in.
///
/// Everything here is generated in code — there are no model files and nothing in the
/// bundle to keep in step. That is a deliberate constraint: the scene has one job, which is
/// to make motion and orientation legible, and procedural geometry does that without an
/// asset pipeline to maintain.
///
/// The rule is *no shipped assets*, not *no textures*. ``SkyGradient`` draws two of them
/// with Core Graphics at launch, which adds no files, no asset catalogue entries and no
/// bytes to the bundle — and without them the sky is a flat colour, which is the one thing
/// that made this scene look like a debug view rather than a place.
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

    /// The sky, drawn at launch. `nil` only if the image or the resource could not be made,
    /// in which case the scene falls back to `RealityViewEnvironment.default`.
    ///
    /// Handed to the view rather than applied here: the environment belongs to the
    /// `RealityView`'s content, and the scene has no business knowing which view is showing
    /// it. `SimulatorView` and SceneLab both mount it the same way.
    private(set) var sky: EnvironmentResource?

    init() {
        buildSky()
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

    private func buildSky() {
        guard let image = SkyGradient.makeImage() else {
            assertionFailure("Could not draw the sky gradient")
            return
        }
        sky = try? EnvironmentResource(equirectangular: image)
        assert(sky != nil, "Could not build an EnvironmentResource from the sky gradient")

        optOutOfImageBasedLighting()
    }

    /// Stops the sky from lighting the scene.
    ///
    /// An `EnvironmentResource` is an image-based light as well as a backdrop, and RealityKit
    /// applies it to `UnlitMaterial` too — which is not what "unlit" leads you to expect.
    /// Adding the skybox on its own lifted every surface in the scene by roughly the average
    /// brightness of the sky: the 0.16 ground came out at 0.42, the scatter blocks went
    /// nearly white, and the red north pylon — the one landmark that has to stay
    /// unmistakable — turned pink.
    ///
    /// Pointing the whole scene at an empty image-based light restores it exactly. Measured
    /// rather than eyeballed: with this in place the ground, the pylon and the blocks come
    /// back to the same bytes they were before the sky existed.
    ///
    /// This will need revisiting when form shading lands, since by then the scene *will*
    /// want lighting — but a directional light it chooses, not whatever the sky averages to.
    private func optOutOfImageBasedLighting() {
        let none = Entity()
        none.components.set(ImageBasedLightComponent(source: .none))
        root.addChild(none)
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: none))
    }

    /// The ground, 20 km across.
    ///
    /// It used to be 2 km, which put its far edge across the frame as a hard seam from as
    /// low as 25 m. A skybox is infinite and the ground is not, so the fix is to push the
    /// edge far enough down that it lands inside the horizon line: at 20 km the edge sits
    /// within 0.7° of horizontal even from the 120 m altitude ceiling.
    ///
    /// That only hides the seam because ``SkyGradient`` paints everything below the horizon
    /// in this exact colour. The two are the same constant on purpose — matching them by eye
    /// would come apart the first time either changed.
    private func buildGround() {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 20_000, depth: 20_000),
            materials: [UnlitMaterial(color: SkyGradient.groundColor)]
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

        // `PerspectiveCameraComponent` defaults to a near plane of 1 cm, which in a 20 km
        // world spends most of the depth buffer on the first centimetre and leaves the far
        // field fighting over what is left. Nothing here is ever seen closer than the
        // airframe, and that sits nine metres away.
        camera.camera.near = 0.5

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

// MARK: -

/// The sky, drawn at launch rather than shipped.
///
/// An equirectangular gradient handed to `EnvironmentResource`. It costs about thirty lines
/// and zero bytes in the bundle, which is the whole reason a texture is allowed here at all.
///
/// ## Why the bottom half is not sky
///
/// Everything below the horizon is painted ``groundColor`` — the same constant the ground
/// plane uses. The ground is 20 km across and the skybox is infinite, so the plane's far
/// edge always lands a fraction of a degree below horizontal; painting the sky underneath it
/// the same colour is what makes that edge stop being a seam. Change one of these two
/// without the other and the horizon splits open again.
///
/// ## Where the sun is
///
/// There is no sun disc, only a warm brightening of the haze centred on **bearing 135°**.
/// It is deliberate and it is load-bearing later: when form shading arrives, the
/// `DirectionalLight` has to come from this bearing or the scene will be lit from somewhere
/// the sky plainly says it is not.
enum SkyGradient {

    /// Everything below the horizon, and the ground plane with it.
    ///
    /// Deliberately dark. The grid is drawn in greys of 0.32 and 0.52 and is the drift cue —
    /// the thing a pilot most needs to notice — so the ground it sits on has to stay well
    /// clear of both.
    static let groundColor = UIColor(white: 0.16, alpha: 1)

    /// Compass bearing the haze brightens toward. See the note above: a later
    /// `DirectionalLight` must agree with this.
    static let sunBearing: Double = 135

    /// Texture azimuth runs 180° out of phase with compass bearing.
    ///
    /// Measured, not looked up: a sky painted in four saturated quadrants put texture 180°
    /// dead ahead when the aircraft was heading north, and the same offset held at 90° and
    /// 180°, increasing in the same direction, so it is a rotation rather than a mirror.
    /// Without this the sun sits opposite where ``sunBearing`` says it does — which is
    /// exactly the sort of thing that stays invisible until a directional light disagrees
    /// with the sky and nobody can say which one is wrong.
    private static let textureAzimuthOffset: Double = 180

    /// A 1024×512 equirectangular gradient: row 0 is the zenith, the last row is the nadir,
    /// and x runs once around the compass.
    static func makeImage(width: Int = 1024, height: Int = 512) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        var groundRed: CGFloat = 0, groundGreen: CGFloat = 0, groundBlue: CGFloat = 0, alpha: CGFloat = 0
        groundColor.getRed(&groundRed, green: &groundGreen, blue: &groundBlue, alpha: &alpha)
        let ground = SIMD3<Double>(Double(groundRed), Double(groundGreen), Double(groundBlue))

        let sun = (sunBearing + textureAzimuthOffset) * .pi / 180

        for y in 0..<height {
            // +90° at the top row through to -90° at the bottom.
            let elevation = (0.5 - (Double(y) + 0.5) / Double(height)) * .pi

            for x in 0..<width {
                let azimuth = (Double(x) + 0.5) / Double(width) * 2 * .pi
                let color = elevation < 0 ? ground : skyColor(elevation: elevation, azimuth: azimuth, sun: sun)

                let offset = (y * width + x) * 4
                pixels[offset] = channel(color.x)
                pixels[offset + 1] = channel(color.y)
                pixels[offset + 2] = channel(color.z)
                pixels[offset + 3] = 255
            }
        }

        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return nil
            }
            return context.makeImage()
        }
    }

    // MARK: - Private

    /// Elevation stops, in degrees, from the horizon up.
    ///
    /// Muted on purpose. The scene's cues are a red pylon, a yellow nose flash and a pale
    /// grey grid; a saturated sky would compete with all three, and the teal pylon would be
    /// the first to go. These are also not final: under `SimpleMaterial` every one of them
    /// comes back darker, so they are chosen to be legible now and re-tuned once.
    private static let stops: [(elevation: Double, color: SIMD3<Double>)] = [
        (0, [0.74, 0.78, 0.80]),
        (3, [0.68, 0.74, 0.79]),
        (12, [0.50, 0.62, 0.74]),
        (40, [0.26, 0.42, 0.62]),
        (90, [0.13, 0.24, 0.42]),
    ]

    private static func skyColor(elevation: Double, azimuth: Double, sun: Double) -> SIMD3<Double> {
        let degrees = elevation * 180 / .pi
        var color = stops[stops.count - 1].color

        for index in 1..<stops.count where degrees <= stops[index].elevation {
            let lower = stops[index - 1]
            let upper = stops[index]
            let t = (degrees - lower.elevation) / (upper.elevation - lower.elevation)
            color = lower.color + (upper.color - lower.color) * t
            break
        }

        // A warm lift toward the sun, strongest on the horizon and gone by 25° up. No disc:
        // a bright spot in the sky is one more thing competing with the pylons for a
        // pilot's attention, and the point is only to say which way the light comes from.
        let separation = abs(atan2(sin(azimuth - sun), cos(azimuth - sun)))
        let across = max(0, 1 - separation / (.pi / 2))
        let up = max(0, 1 - degrees / 25)
        let glow = pow(across, 3) * up * 0.16

        return color + SIMD3(1.0, 0.86, 0.62) * glow
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

}
