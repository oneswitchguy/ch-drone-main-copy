//
//  ProceduralMesh.swift
//  CH Drone
//

import Foundation
import RealityKit
import simd

/// Accumulates many small primitives into one merged mesh.
///
/// The simulator scene builds its world from hundreds of tiny shapes. One `ModelEntity`
/// each does not survive contact with an iPad, so they are merged: geometry is collected
/// into a bucket per material, each bucket becomes one `MeshDescriptor`, and the whole lot
/// becomes a single `MeshResource` with one part per material. A scene that gains several
/// hundred objects ends up with *fewer* draw calls than it started with.
///
/// ## Why buckets rather than vertex colours
///
/// RealityKit's mesh descriptors expose no vertex-colour buffer. Getting one means
/// `CustomMaterial` and a Metal shader, which is a build-system problem rather than a
/// graphics one. Grouping by material index costs nothing instead: a tree with a trunk and
/// two canopy tones is three parts, three materials, one entity, and no shader anywhere.
///
/// ## Flat shading, and why the normals matter now
///
/// Every face carries its own copies of its vertices so it can carry its own normal. That
/// is what this scene wants — low-poly geometry that reads as facets — and it is the only
/// arrangement in which "the normal is perpendicular to its own face" is a statement that
/// can be tested.
///
/// Nothing reads those normals today: the whole scene is `UnlitMaterial`. Form shading is a
/// later commit, and it will read every one of them. Getting them right here, in the one
/// phase that has tests, is far cheaper than retrofitting them once several generators and
/// a scattering routine depend on this type.
///
/// ## Winding
///
/// Faces are wound counter-clockwise as seen from the side they face, which is what
/// RealityKit treats as front-facing. Get it backwards and the shape does not render
/// wrong — it renders *not at all*, because back-face culling removes it.
///
/// ## Testing
///
/// Nothing on the input side of this type is a RealityKit type — only `simd` and Swift —
/// so the geometry unit-tests on the Mac exactly as `FlightModel` does. ``meshResource()``
/// is the single line that crosses over.
struct MeshBuilder {

    // MARK: - Output

    /// One material's worth of accumulated geometry.
    struct Part: Equatable {

        /// Index into the materials array handed to the `ModelEntity`.
        let material: Int

        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]

        var triangleCount: Int { indices.count / 3 }
    }

    /// The accumulated geometry, one part per material, ordered by material index.
    var parts: [Part] {
        buckets.keys.sorted().map { material in
            let bucket = buckets[material]!
            return Part(
                material: material,
                positions: bucket.positions,
                normals: bucket.normals,
                indices: bucket.indices
            )
        }
    }

    var isEmpty: Bool { buckets.isEmpty }

    // MARK: - Adding geometry

    /// Adds a quad from four coplanar corners, wound counter-clockwise seen from the front.
    mutating func addQuad(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        at position: SIMD3<Float> = .zero,
        rotation: simd_quatf = .identity,
        scale: Float = 1,
        material: Int
    ) {
        addFace([a, b, c, d], at: position, rotation: rotation, scale: scale, material: material)
    }

    /// Adds an axis-aligned box, centred on the origin before the transform is applied.
    ///
    /// Six quads rather than a primitive of its own: a box is the one shape this scene
    /// already had, and building it out of the quad generator means the grid can be
    /// rebuilt through here without changing a single vertex position.
    mutating func addBox(
        size: SIMD3<Float>,
        at position: SIMD3<Float> = .zero,
        rotation: simd_quatf = .identity,
        scale: Float = 1,
        material: Int
    ) {
        let h = size / 2

        let faces: [[SIMD3<Float>]] = [
            // +Y, -Y
            [[-h.x, h.y, h.z], [h.x, h.y, h.z], [h.x, h.y, -h.z], [-h.x, h.y, -h.z]],
            [[-h.x, -h.y, -h.z], [h.x, -h.y, -h.z], [h.x, -h.y, h.z], [-h.x, -h.y, h.z]],
            // +Z, -Z
            [[-h.x, -h.y, h.z], [h.x, -h.y, h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z]],
            [[h.x, -h.y, -h.z], [-h.x, -h.y, -h.z], [-h.x, h.y, -h.z], [h.x, h.y, -h.z]],
            // +X, -X
            [[h.x, -h.y, h.z], [h.x, -h.y, -h.z], [h.x, h.y, -h.z], [h.x, h.y, h.z]],
            [[-h.x, -h.y, -h.z], [-h.x, -h.y, h.z], [-h.x, h.y, h.z], [-h.x, h.y, -h.z]],
        ]

        for face in faces {
            addFace(face, at: position, rotation: rotation, scale: scale, material: material)
        }
    }

    /// Adds a cone frustum about the Y axis, base at y = 0 and top at y = `height`.
    ///
    /// One generator covers three shapes: equal radii make a cylinder, a zero top radius
    /// makes a cone. Trunk, canopy and tapered arm are all this function.
    mutating func addFrustum(
        bottomRadius: Float,
        topRadius: Float,
        height: Float,
        sides: Int = 8,
        capBottom: Bool = false,
        capTop: Bool = false,
        at position: SIMD3<Float> = .zero,
        rotation: simd_quatf = .identity,
        scale: Float = 1,
        material: Int
    ) {
        guard sides >= 3, height != 0, bottomRadius > 0 || topRadius > 0 else { return }

        let bottom = Self.ring(radius: bottomRadius, y: 0, sides: sides)
        let top = Self.ring(radius: topRadius, y: height, sides: sides)

        for i in 0..<sides {
            let next = (i + 1) % sides

            // A cone has no top edge to span, so its sides are triangles rather than quads
            // with two coincident corners — a degenerate quad would contribute a zero-area
            // triangle and a meaningless normal.
            var face = [bottom[i]]
            if topRadius > 0 {
                face.append(top[i])
                face.append(top[next])
            } else {
                face.append(top[i])
            }
            face.append(bottom[next])

            addFace(face, at: position, rotation: rotation, scale: scale, material: material)
        }

        // Caps face away from the body, so the bottom takes the ring as it comes and the
        // top takes it reversed.
        if capBottom, bottomRadius > 0 {
            addFace(bottom, at: position, rotation: rotation, scale: scale, material: material)
        }
        if capTop, topRadius > 0 {
            addFace(top.reversed(), at: position, rotation: rotation, scale: scale, material: material)
        }
    }

    // MARK: - RealityKit

    /// The merged mesh, one part per material.
    ///
    /// Material indices map onto the array handed to `ModelEntity(mesh:materials:)`, so a
    /// builder that used materials 0 and 1 needs a two-element array in that order.
    func meshResource() throws -> MeshResource {
        let descriptors = parts.map { part -> MeshDescriptor in
            var descriptor = MeshDescriptor(name: "part\(part.material)")
            descriptor.positions = MeshBuffer(part.positions)
            descriptor.normals = MeshBuffer(part.normals)
            descriptor.primitives = .triangles(part.indices)
            descriptor.materials = .allFaces(UInt32(part.material))
            return descriptor
        }
        return try MeshResource.generate(from: descriptors)
    }

    // MARK: - Private

    private struct Bucket {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
    }

    private var buckets: [Int: Bucket] = [:]

    /// Adds one convex, planar face as a triangle fan.
    private mutating func addFace(
        _ points: [SIMD3<Float>],
        at position: SIMD3<Float>,
        rotation: simd_quatf,
        scale: Float,
        material: Int
    ) {
        guard points.count >= 3 else { return }

        let placed = points.map { position + rotation.act($0 * scale) }
        let normal = Self.faceNormal(placed)

        // A degenerate face has no normal to give and nothing to draw. Dropping it keeps
        // the "every normal is unit length" invariant true by construction.
        guard normal != .zero else { return }

        var bucket = buckets[material] ?? Bucket()
        let base = UInt32(bucket.positions.count)

        bucket.positions.append(contentsOf: placed)
        bucket.normals.append(contentsOf: repeatElement(normal, count: placed.count))

        for corner in 1..<(placed.count - 1) {
            bucket.indices.append(base)
            bucket.indices.append(base + UInt32(corner))
            bucket.indices.append(base + UInt32(corner + 1))
        }

        buckets[material] = bucket
    }

    /// The outward normal of a planar polygon, by Newell's method.
    ///
    /// Newell rather than a cross product of the first three corners, which goes wrong the
    /// moment those three happen to be collinear — as they are on a cone's side face if the
    /// vertices are taken in an unlucky order.
    private static func faceNormal(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        var normal = SIMD3<Float>.zero

        for i in points.indices {
            let current = points[i]
            let next = points[(i + 1) % points.count]

            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }

        let length = simd_length(normal)
        return length > 0 ? normal / length : .zero
    }

    private static func ring(radius: Float, y: Float, sides: Int) -> [SIMD3<Float>] {
        (0..<sides).map { i in
            let angle = Float(i) / Float(sides) * 2 * .pi
            return SIMD3(cos(angle) * radius, y, sin(angle) * radius)
        }
    }

}

// MARK: -

extension simd_quatf {

    /// Spelled out because `simd_quatf()` is not the identity — it is uninitialised.
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

}
