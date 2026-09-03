//
//  ProceduralMeshTests.swift
//  CHDroneTests
//

import simd
import XCTest

@testable import CH_Drone_2

/// The simulator is otherwise a matter of taste; this is the one part of it with a correct
/// answer, so it is the one part with tests.
///
/// Three of these matter more than the counts. **Winding**, because a face wound the wrong
/// way is not drawn wrong, it is culled — the shape simply is not there, and that is a
/// miserable thing to debug through a scene. **Normal direction**, because nothing reads
/// normals while everything is `UnlitMaterial`, so a wrong one is silent right up until
/// form shading lands and every surface is lit from the inside. And **index range**,
/// because that is what `MeshResource.generate` throws on.
final class ProceduralMeshTests: XCTestCase {

    // MARK: - Invariants

    /// Everything that must hold for any part the builder produces, whatever built it.
    private func assertInvariants(
        _ part: MeshBuilder.Part,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(part.positions.count, part.normals.count, "one normal per position", file: file, line: line)
        XCTAssertEqual(part.indices.count % 3, 0, "whole triangles", file: file, line: line)

        for index in part.indices {
            XCTAssertLessThan(Int(index), part.positions.count, "index in range", file: file, line: line)
        }

        for normal in part.normals {
            XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4, "normal is unit length", file: file, line: line)
        }

        for triangle in stride(from: 0, to: part.indices.count, by: 3) {
            let a = part.positions[Int(part.indices[triangle])]
            let b = part.positions[Int(part.indices[triangle + 1])]
            let c = part.positions[Int(part.indices[triangle + 2])]
            let normal = part.normals[Int(part.indices[triangle])]

            XCTAssertEqual(simd_dot(normal, b - a), 0, accuracy: 1e-3, "normal ⟂ its own face", file: file, line: line)
            XCTAssertEqual(simd_dot(normal, c - a), 0, accuracy: 1e-3, "normal ⟂ its own face", file: file, line: line)

            XCTAssertGreaterThan(
                simd_dot(simd_cross(b - a, c - a), normal), 0,
                "winding agrees with the normal, or back-face culling deletes it",
                file: file, line: line
            )
        }
    }

    // MARK: - Quads

    func testQuadIsTwoTrianglesSharingFourVertices() {
        var builder = MeshBuilder()
        builder.addQuad([-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1], material: 0)

        XCTAssertEqual(builder.parts.count, 1)
        XCTAssertEqual(builder.parts[0].positions.count, 4)
        XCTAssertEqual(builder.parts[0].triangleCount, 2)
        assertInvariants(builder.parts[0])
    }

    func testWindingDecidesWhichWayAQuadFaces() {
        var down = MeshBuilder()
        down.addQuad([-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1], material: 0)
        XCTAssertEqual(down.parts[0].normals[0].y, -1, accuracy: 1e-4)

        var up = MeshBuilder()
        up.addQuad([-1, 0, 1], [1, 0, 1], [1, 0, -1], [-1, 0, -1], material: 0)
        XCTAssertEqual(up.parts[0].normals[0].y, 1, accuracy: 1e-4)
    }

    // MARK: - Boxes

    func testBoxHasSixUnsharedFaces() {
        var builder = MeshBuilder()
        builder.addBox(size: [2, 4, 6], material: 0)
        let part = builder.parts[0]

        XCTAssertEqual(part.positions.count, 24, "six faces of four, unshared so each carries its own normal")
        XCTAssertEqual(part.triangleCount, 12)
        assertInvariants(part)

        for axis in [SIMD3<Float>(1, 0, 0), [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]] {
            let facing = part.normals.filter { simd_distance($0, axis) < 1e-5 }.count
            XCTAssertEqual(facing, 4, "four vertices face \(axis)")
        }
    }

    func testBoxFacesPointOutward() {
        var builder = MeshBuilder()
        builder.addBox(size: [2, 3, 4], material: 0)
        let part = builder.parts[0]

        // For a convex shape about the origin, outward means the normal agrees with the
        // direction of the face's own centroid.
        for corner in stride(from: 0, to: part.positions.count, by: 4) {
            let centroid = part.positions[corner..<(corner + 4)].reduce(SIMD3<Float>.zero, +) / 4
            XCTAssertGreaterThan(simd_dot(part.normals[corner], centroid), 0)
        }
    }

    func testBoxIsTheSizeItWasAskedFor() {
        var builder = MeshBuilder()
        builder.addBox(size: [2, 4, 6], material: 0)
        let positions = builder.parts[0].positions

        XCTAssertEqual(positions.map(\.x).max()! - positions.map(\.x).min()!, 2, accuracy: 1e-4)
        XCTAssertEqual(positions.map(\.y).max()! - positions.map(\.y).min()!, 4, accuracy: 1e-4)
        XCTAssertEqual(positions.map(\.z).max()! - positions.map(\.z).min()!, 6, accuracy: 1e-4)
    }

    // MARK: - Frusta

    func testCylinderSidesAreQuadsFacingOutward() {
        var builder = MeshBuilder()
        builder.addFrustum(bottomRadius: 2, topRadius: 2, height: 5, sides: 8, material: 0)
        let part = builder.parts[0]

        XCTAssertEqual(part.positions.count, 8 * 4)
        XCTAssertEqual(part.triangleCount, 16)
        assertInvariants(part)

        for normal in part.normals {
            XCTAssertEqual(normal.y, 0, accuracy: 1e-3, "a cylinder's sides are vertical")
            XCTAssertGreaterThan(simd_dot(normal, SIMD3(normal.x, 0, normal.z)), 0.99, "and point away from the axis")
        }
    }

    func testConeSidesAreTrianglesRatherThanDegenerateQuads() {
        var builder = MeshBuilder()
        builder.addFrustum(bottomRadius: 3, topRadius: 0, height: 4, sides: 6, material: 0)
        let part = builder.parts[0]

        XCTAssertEqual(part.positions.count, 6 * 3, "three corners a side, not four with two on top of each other")
        XCTAssertEqual(part.triangleCount, 6)
        assertInvariants(part)

        for normal in part.normals {
            XCTAssertGreaterThan(normal.y, 0, "a cone's sides lean outward and up")
        }
    }

    func testCapsCloseBothEndsFacingAway() {
        var builder = MeshBuilder()
        builder.addFrustum(
            bottomRadius: 1, topRadius: 1, height: 2, sides: 8,
            capBottom: true, capTop: true, material: 0
        )
        let part = builder.parts[0]

        XCTAssertEqual(part.positions.count, 8 * 4 + 8 + 8)
        XCTAssertEqual(part.triangleCount, 16 + 6 + 6, "a fan of six triangles closes an eight-sided ring")
        assertInvariants(part)

        XCTAssertTrue(part.normals.contains { abs($0.y - 1) < 1e-4 }, "the top faces up")
        XCTAssertTrue(part.normals.contains { abs($0.y + 1) < 1e-4 }, "the bottom faces down")
    }

    // MARK: - Placement

    func testTranslationMovesGeometryAndLeavesNormalsAlone() {
        var builder = MeshBuilder()
        builder.addBox(size: [1, 1, 1], at: [10, 20, 30], material: 0)
        let part = builder.parts[0]

        for position in part.positions {
            XCTAssertEqual(simd_distance(position, SIMD3(10, 20, 30)), sqrt(0.75), accuracy: 1e-4)
        }
        assertInvariants(part)
    }

    func testRotationCarriesNormalsWithIt() {
        var builder = MeshBuilder()
        builder.addBox(
            size: [1, 1, 1],
            rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]),
            material: 0
        )
        let part = builder.parts[0]

        XCTAssertTrue(part.normals.contains { abs($0.x - 1) < 1e-4 })
        XCTAssertTrue(part.normals.contains { abs($0.y - 1) < 1e-4 })
        assertInvariants(part)
    }

    func testScaleLeavesNormalsUnitLength() {
        var builder = MeshBuilder()
        builder.addBox(size: [1, 1, 1], scale: 4, material: 0)
        let part = builder.parts[0]

        let xs = part.positions.map(\.x)
        XCTAssertEqual(xs.max()! - xs.min()!, 4, accuracy: 1e-4)
        for normal in part.normals {
            XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4)
        }
    }

    // MARK: - Materials

    func testGeometryIsBucketedByMaterialAndOrderedByIndex() {
        var builder = MeshBuilder()
        builder.addBox(size: [1, 1, 1], material: 3)
        builder.addQuad([0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], material: 1)

        XCTAssertEqual(builder.parts.map(\.material), [1, 3], "ordered by index, so materials line up")
        XCTAssertEqual(builder.parts[0].triangleCount, 2)
        XCTAssertEqual(builder.parts[1].triangleCount, 12)
    }

    // MARK: - Degenerate input

    func testDegenerateInputIsDroppedRatherThanEmitted() {
        var builder = MeshBuilder()
        builder.addQuad([0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], material: 0)  // collinear
        builder.addFrustum(bottomRadius: 0, topRadius: 0, height: 1, material: 0) // no radius
        builder.addFrustum(bottomRadius: 1, topRadius: 1, height: 1, sides: 2, material: 0)

        XCTAssertTrue(builder.isEmpty, "a face with no normal is dropped, keeping the invariant true by construction")
    }

    // MARK: - The grid

    func testGridMergesEightyTwoLinesIntoTwoParts() {
        var builder = MeshBuilder()
        let extent: Float = 200
        var offset = -extent
        var lines = 0

        while offset <= extent {
            let isMajor = offset.truncatingRemainder(dividingBy: 50) == 0
            let thickness: Float = isMajor ? 0.16 : 0.06
            let material = isMajor ? 1 : 0
            builder.addBox(size: [thickness, 0.01, extent * 2], at: [offset, 0, 0], material: material)
            builder.addBox(size: [extent * 2, 0.01, thickness], at: [0, 0, offset], material: material)
            lines += 2
            offset += 10
        }

        XCTAssertEqual(lines, 82, "the same 82 lines the scene used to build one entity at a time")
        XCTAssertEqual(builder.parts.count, 2, "minor and major")
        XCTAssertEqual(builder.parts.reduce(0) { $0 + $1.triangleCount }, 82 * 12)
        XCTAssertEqual(builder.parts[1].triangleCount / 12, 18, "nine major offsets each way")

        for part in builder.parts {
            assertInvariants(part)
        }
    }

}
