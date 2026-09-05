//
//  SimulatorScene.swift
//  CH Drone
//

import Foundation
import RealityKit
import UIKit

/// Builds and drives the RealityKit scene the simulator flies in.
///
/// The world is generated in code — ground, grid, pylons, home pad and sky, none of which
/// ships a byte. The scene has one job, which is to make motion and orientation legible,
/// and procedural geometry does that without an asset pipeline to maintain. ``SkyGradient``
/// draws the sky with Core Graphics at launch for the same reason: it is a texture, but it
/// is not a *file*.
///
/// The **airframe is the exception**, and the only one: it is loaded from `Drone.reality`.
/// A drone is the one thing in this scene a pilot has to read rather than merely see, and
/// a shape they recognise does that better than anything reasonable to assemble out of
/// primitives. See ``buildAircraft()``.
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
        // anything — the flight model has no concept of thrust.
        //
        // Setting `orientation` here is safe despite how lopsided a rotor's own scale is —
        // the blades are 27:1 bars — because a `Transform` scales before it rotates, so the
        // blade is made first and then turned rigidly. That holds only while every ancestor
        // up to the load root is uniformly scaled, which they are. A non-uniform scale
        // introduced anywhere above these entities would shear the blades as they turned.
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

    /// The empty image-based light the whole scene is pointed at by
    /// ``optOutOfImageBasedLighting()``. Held rather than made and forgotten, because the
    /// airframe opts into a real light and the parts that must keep an exact colour —
    /// see ``addHeadingFlash(to:)`` — have to be able to opt back out of it.
    private let noImageBasedLight = Entity()

    private let camera = PerspectiveCamera()
    private var rotors: [Entity] = []
    private var rotorAngle: Float = 0
    private var hasPlacedCamera = false

    /// Metres, measured across the widest part of the airframe. Larger than a real Mavic,
    /// which is about 0.35 m across, because at a readable chase distance a life-sized
    /// airframe is a smudge. Judging absolute distance matters less here than seeing which
    /// way the nose points.
    ///
    /// ``loadAirframe()`` scales the model to this rather than trusting the size it was
    /// exported at, so this constant stays the single place the airframe's size is decided.
    private static let aircraftSpan: Float = 1.6

    /// `Drone.reality`, in the main bundle. Built into the app and into SceneLab, which is
    /// the only other target that mounts this scene.
    private static let airframeResource = "Drone"

    /// The four rotors inside `Drone.reality`, which ``update(with:)`` spins.
    ///
    /// Matched by name, and asserted on load — a rename in the model would otherwise show
    /// up as rotors that quietly stopped turning, which is exactly the sort of thing nobody
    /// notices for a month.
    private static let rotorNames = ["rotor_FL", "rotor_FR", "rotor_BL", "rotor_BR"]

    /// The body of the model, which the nose flash is sized and positioned against.
    private static let bodyName = "hub"

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
        noImageBasedLight.components.set(ImageBasedLightComponent(source: .none))
        root.addChild(noImageBasedLight)
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: noImageBasedLight))
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

    /// The airframe, loaded from `Drone.reality`.
    ///
    /// The one shipped asset in this scene, and a deliberate exception to the rule at the
    /// top of this file rather than a hole in it. What it buys is orientation: arms, motors,
    /// landing gear and a camera gimbal hanging off the nose say which way the aircraft is
    /// pointing from further away, and from more angles, than the box-and-sticks airframe
    /// this replaces ever did.
    ///
    /// Three adjustments are made on the way in, every one of them derived from the model's
    /// own bounds rather than written down here, so that re-exporting it at a different size
    /// or with a different origin cannot quietly move it:
    ///
    /// - **Scaled** until its widest horizontal extent is ``aircraftSpan``.
    /// - **Turned to face -Z.** The model is built nose-toward +Z — that is the face the
    ///   gimbal hangs off — and RealityKit's forward, which is the direction
    ///   ``orientation(heading:pitch:roll:)`` points the aircraft along, is the other way.
    ///   Get this wrong and the scene flies backwards while looking entirely plausible.
    /// - **Lifted** so the feet rest on the ground at zero altitude. The old airframe was
    ///   centred on its body and sat half-buried in the ground plane; this one has legs.
    ///
    /// If the model will not load, ``buildProceduralAirframe()`` stands in. Practice mode
    /// with a plain-looking drone in it beats practice mode with no drone in it, for a mode
    /// whose whole job is teaching a pilot to read where the aircraft is pointing.
    private func buildAircraft() {
        if let airframe = Self.loadAirframe() {
            aircraft.addChild(airframe)
            lightAirframe()
            addHeadingFlash(to: airframe)

            rotors = Self.rotorNames.compactMap { airframe.findEntity(named: $0) }
            assert(
                rotors.count == Self.rotorNames.count,
                "Drone.reality is missing a rotor — found \(rotors.count) of \(Self.rotorNames.count)"
            )
        } else {
            assertionFailure("Could not load a usable airframe from \(Self.airframeResource).reality")
            buildProceduralAirframe()
        }

        root.addChild(aircraft)
        buildShadow()
    }

    /// Loads the airframe and puts it into this scene's frame and scale.
    ///
    /// The transform goes on the loaded model rather than on ``aircraft``, which
    /// ``update(with:)`` overwrites sixty times a second with the flight pose. Those two
    /// jobs stay on separate entities: this one is the model's, and that one is the
    /// aircraft's.
    private static func loadAirframe() -> Entity? {
        guard let model = try? Entity.load(named: airframeResource, in: .main) else { return nil }

        // Local-space bounds, so the model's own transform is not counted twice.
        let bounds = model.visualBounds(relativeTo: model)
        let width = max(bounds.extents.x, bounds.extents.z)
        guard width > 0 else { return nil }

        let scale = aircraftSpan / width
        model.scale = SIMD3(repeating: scale)
        model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        // Applied after the rotation, which is about Y and so leaves this lift alone.
        model.position = [0, -bounds.min.y * scale, 0]

        return model
    }

    /// Lights the airframe, and nothing else in the scene.
    ///
    /// Everything else here is `UnlitMaterial` and has its colour whether or not anything
    /// is shining on it. The model's four materials are `ShaderGraphMaterial` and do not:
    /// under the empty image-based light that ``optOutOfImageBasedLighting()`` points the
    /// whole scene at, they render black.
    ///
    /// So the aircraft opts back in on its own account, to an image-based light built from
    /// the very sky it is being flown against — the cheapest light available here, and the
    /// only one that cannot disagree with the backdrop about where the sun is.
    /// `ImageBasedLightReceiverComponent` is inherited and the nearest one up the hierarchy
    /// wins, so setting it on ``aircraft`` covers the airframe and leaves every colour
    /// measured elsewhere in the scene exactly where it was.
    private func lightAirframe() {
        guard let sky else {
            // No sky means no light to give it, and a black airframe would be worse than a
            // plain one. `buildSky` has already asserted by this point.
            return
        }

        let light = Entity()
        light.components.set(ImageBasedLightComponent(source: .single(sky)))
        root.addChild(light)

        aircraft.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
    }

    /// Marks the nose, in a colour nothing else in the scene uses.
    ///
    /// The model does say which way it is pointing on its own — the gimbal hangs off the
    /// front, the legs rake back — but shape is the first cue to go: at altitude, at
    /// distance, and for a pilot reading the scene out of the corner of their eye while
    /// working a switch. The airframe this replaced marked its nose in yellow for exactly
    /// that reason, and a better-looking model is no reason to stop.
    ///
    /// It straddles the top-front edge of the body, which is the one place in view both from
    /// behind and above — where the chase camera sits — and from in front. Sized off the
    /// body rather than off ``aircraftSpan``, so it stays in proportion to the airframe if
    /// the model is ever re-exported.
    ///
    /// Pointed back at the scene's empty image-based light. This is a marker, not a part: it
    /// has to be the same yellow whichever way the aircraft has turned, and the sky the
    /// airframe is lit by would otherwise wash it toward white — the one direction that
    /// costs it its contrast against the pale grid and the light steel body.
    private func addHeadingFlash(to airframe: Entity) {
        guard let body = airframe.findEntity(named: Self.bodyName) else {
            assertionFailure("Drone.reality has no \(Self.bodyName) to mark the nose of")
            return
        }

        let bounds = body.visualBounds(relativeTo: aircraft)
        let flash = ModelEntity(
            mesh: .generateBox(
                size: [bounds.extents.x * 0.6, bounds.extents.y * 0.45, bounds.extents.z * 0.26],
                cornerRadius: bounds.extents.y * 0.08
            ),
            materials: [UnlitMaterial(color: .systemYellow)]
        )
        flash.position = [0, bounds.max.y, bounds.min.z]
        flash.components.set(ImageBasedLightReceiverComponent(imageBasedLight: noImageBasedLight))

        aircraft.addChild(flash)
    }

    /// A ground shadow.
    ///
    /// Altitude is genuinely hard to judge from a chase camera, and the gap between the
    /// aircraft and its shadow reads as height far better than a number does.
    private func buildShadow() {
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: Self.aircraftSpan * 0.45),
            materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1))]
        )
        shadow.addChild(disc)
        root.addChild(shadow)
    }

    /// The airframe this scene flew before `Drone.reality`, kept as the fallback.
    ///
    /// Boxes and sticks, but boxes and sticks that cannot fail to load.
    private func buildProceduralAirframe() {
        let bodyMaterial = UnlitMaterial(color: UIColor(white: 0.9, alpha: 1))
        let armMaterial = UnlitMaterial(color: UIColor(white: 0.55, alpha: 1))
        let rotorMaterial = UnlitMaterial(color: UIColor(white: 0.7, alpha: 1))

        let span = Self.aircraftSpan

        let body = ModelEntity(
            mesh: .generateBox(size: [span * 0.34, span * 0.16, span * 0.55], cornerRadius: 0.05),
            materials: [bodyMaterial]
        )
        aircraft.addChild(body)

        // The nose flash, for the same reason the loaded airframe gets one.
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
