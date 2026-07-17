import Foundation
import SceneKit
import simd
import UIKit

/// Builds the static 3D geometry of the GB rail network from the bundled
/// Network Rail Track Model extract (`tracks.bin`).
///
/// Binary layout (little-endian): uint32 lineCount, uint32[lineCount]
/// pointCounts, then float32 x,y pairs — British National Grid metres,
/// centred on the network bounding-box centre. Scene units are kilometres:
/// x = easting, y = up, z = -northing (so north points away from a
/// south-facing camera).
enum TrackNetworkScene {
    /// Network bounding box in absolute BNG metres (from the Track Model
    /// extract) — used to recover absolute northing for the colour ramp and
    /// to place live train dots in the same centred frame.
    static let centre = SIMD2<Double>(408_563.8217, 499_254.88605)
    static let northingMin = 30_609.7869
    static let northingMax = 967_899.9852
    static let metresPerUnit = 1000.0

    enum ParseError: Error {
        case missingResource
        case corruptData
    }

    /// Colour ramp south -> north (warm amber through pink and violet to
    /// teal), matching the web prototype. `t` is normalised northing 0...1.
    static func rampColour(_ t: Float) -> SIMD3<Float> {
        let stops: [(Float, SIMD3<Float>)] = [
            (0.00, SIMD3(1.000, 0.702, 0.278)),  // 0xffb347
            (0.30, SIMD3(1.000, 0.369, 0.471)),  // 0xff5e78
            (0.55, SIMD3(0.541, 0.424, 1.000)),  // 0x8a6cff
            (0.80, SIMD3(0.208, 0.784, 1.000)),  // 0x35c8ff
            (1.00, SIMD3(0.490, 0.980, 0.859)),  // 0x7dfadb
        ]
        let t = max(0, min(1, t))
        for i in 1..<stops.count where t <= stops[i].0 {
            let (t0, c0) = stops[i - 1]
            let (t1, c1) = stops[i]
            return simd_mix(c0, c1, SIMD3(repeating: (t - t0) / (t1 - t0)))
        }
        return stops[stops.count - 1].1
    }

    /// Converts a WGS84 position to centred scene coordinates (km).
    static func scenePosition(latitude: Double, longitude: Double) -> SCNVector3 {
        let (e, n) = BNGConverter.toOSGB36(latitude: latitude, longitude: longitude)
        return SCNVector3(
            Float((e - centre.x) / metresPerUnit),
            0,
            Float(-(n - centre.y) / metresPerUnit)
        )
    }

    /// Parses tracks.bin and builds the network as a single line-primitive
    /// geometry node. Heavy (186k vertices) — call off the main thread.
    static func buildTrackNode() throws -> SCNNode {
        guard let url = Bundle.main.url(forResource: "tracks", withExtension: "bin") else {
            throw ParseError.missingResource
        }
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count >= 4 else { throw ParseError.corruptData }

        var positions = [Float]()
        var colours = [Float]()
        var indices = [UInt32]()

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let lineCount = Int(raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
            let countsEnd = 4 + 4 * lineCount
            guard data.count >= countsEnd else { throw ParseError.corruptData }

            var counts = [Int](repeating: 0, count: lineCount)
            var totalPoints = 0
            for i in 0..<lineCount {
                counts[i] = Int(raw.loadUnaligned(fromByteOffset: 4 + 4 * i, as: UInt32.self))
                totalPoints += counts[i]
            }
            guard data.count == countsEnd + 8 * totalPoints else { throw ParseError.corruptData }

            positions.reserveCapacity(totalPoints * 3)
            colours.reserveCapacity(totalPoints * 4)
            indices.reserveCapacity((totalPoints - lineCount) * 2)

            let span = Float(northingMax - northingMin)
            var offset = countsEnd
            var vertex: UInt32 = 0
            for count in counts {
                for p in 0..<count {
                    let x = raw.loadUnaligned(fromByteOffset: offset + 8 * p, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: offset + 8 * p + 4, as: Float.self)
                    positions.append(x / Float(metresPerUnit))
                    positions.append(0)
                    positions.append(-y / Float(metresPerUnit))

                    let t = (y + Float(centre.y - northingMin)) / span
                    let c = rampColour(t)
                    colours.append(c.x)
                    colours.append(c.y)
                    colours.append(c.z)
                    colours.append(0.62)

                    if p > 0 {
                        indices.append(vertex - 1)
                        indices.append(vertex)
                    }
                    vertex += 1
                }
                offset += 8 * count
            }
        }

        let geometry = SCNGeometry(
            sources: [
                positionSource(positions),
                colourSource(colours),
            ],
            elements: [
                SCNGeometryElement(
                    data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
                    primitiveType: .line,
                    primitiveCount: indices.count / 2,
                    bytesPerIndex: 4
                ),
            ]
        )
        geometry.firstMaterial = glowMaterial()

        let node = SCNNode(geometry: geometry)
        node.castsShadow = false
        return node
    }

    /// Shared unlit additive material — vertex colours carry all the colour.
    static func glowMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = true
        return material
    }

    static func positionSource(_ floats: [Float]) -> SCNGeometrySource {
        SCNGeometrySource(
            data: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .vertex,
            vectorCount: floats.count / 3,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 3 * MemoryLayout<Float>.size
        )
    }

    static func colourSource(_ floats: [Float]) -> SCNGeometrySource {
        SCNGeometrySource(
            data: floats.withUnsafeBufferPointer { Data(buffer: $0) },
            semantic: .color,
            vectorCount: floats.count / 4,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 4 * MemoryLayout<Float>.size
        )
    }

    /// Assembles the scene shell: background, camera. The track node is
    /// attached later (it builds asynchronously).
    static func makeScene() -> (scene: SCNScene, cameraNode: SCNNode) {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.02, green: 0.027, blue: 0.05, alpha: 1)

        let camera = SCNCamera()
        camera.zNear = 0.5
        camera.zFar = 4000
        camera.fieldOfView = 50
        camera.wantsHDR = true
        camera.bloomIntensity = 0.9
        camera.bloomThreshold = 0.35

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 850, 400)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        return (scene, cameraNode)
    }
}
