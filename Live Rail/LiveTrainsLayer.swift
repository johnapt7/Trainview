import Foundation
import SceneKit
import simd

/// Owns the live-train dots: polls `/api/movements` every 20 seconds, keeps
/// one dot per train, tweens dots to newly reported positions, and fades out
/// trains that stop reporting. All dots render as a single point-cloud
/// geometry (one draw call) rebuilt on the SceneKit render loop while any
/// tween is active.
final class LiveTrainsController: NSObject, SCNSceneRendererDelegate {
    private struct Dot {
        var current: SIMD3<Float>
        var start: SIMD3<Float>
        var target: SIMD3<Float>
        var tweenStart: TimeInterval  // renderer time; <0 = not tweening
        var colour: SIMD3<Float>
        var ageSeconds: Int
        var lastPolled: Date
    }

    private static let pollInterval: TimeInterval = 20
    private static let tweenDuration: TimeInterval = 2.5
    private static let fadeAfterSeconds = 20 * 60   // dim dots silent > 20 min
    private static let dropAfterSeconds = 45 * 60   // remove dots silent > 45 min
    private static let rebuildInterval: TimeInterval = 1.0 / 15.0

    let node = SCNNode()

    /// Published for the HUD. Updated on the main actor after each poll.
    @MainActor var onCountChange: ((Int) -> Void)?
    @MainActor var onError: ((Bool) -> Void)?

    private var dots: [String: Dot] = [:]
    private let lock = NSLock()
    private var pollTask: Task<Void, Never>?
    private var lastRebuild: TimeInterval = 0
    private var needsRebuild = false

    // MARK: - Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        do {
            let response = try await APIClient.shared.getActiveTrains()
            apply(response.trains)
            let count = response.trains.count
            await MainActor.run {
                onCountChange?(count)
                onError?(false)
            }
        } catch {
            await MainActor.run { onError?(true) }
        }
    }

    private func apply(_ trains: [ActiveTrain]) {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }

        var seen = Set<String>()
        seen.reserveCapacity(trains.count)
        for train in trains {
            guard train.ageSeconds < Self.dropAfterSeconds else { continue }
            let key = train.key
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)

            let position = TrackNetworkScene.scenePosition(latitude: train.lat, longitude: train.lon)
            let target = SIMD3(position.x, 0.4, position.z)  // float dots just above the tracks
            let colour = Self.latenessColour(variationSeconds: train.variationSeconds)

            if var dot = dots[key] {
                if simd_distance(dot.target, target) > 0.05 {
                    dot.start = dot.current
                    dot.target = target
                    dot.tweenStart = -1  // armed; stamped with renderer time on next frame
                }
                dot.colour = colour
                dot.ageSeconds = train.ageSeconds
                dot.lastPolled = now
                dots[key] = dot
            } else {
                dots[key] = Dot(
                    current: target, start: target, target: target,
                    tweenStart: -2, colour: colour,
                    ageSeconds: train.ageSeconds, lastPolled: now
                )
            }
        }

        // Trains no longer in the snapshot: the server already ages them out,
        // so anything absent has terminated or gone stale — drop straight away
        // once our own grace period passes, using time since we last saw it.
        for (key, dot) in dots where !seen.contains(key) {
            if now.timeIntervalSince(dot.lastPolled) > Self.pollInterval * 3 {
                dots.removeValue(forKey: key)
            }
        }

        needsRebuild = true
    }

    /// On time / early: cool blue-white. 3 minutes late: amber. 10+ minutes
    /// late: red. Interpolated between those anchors.
    static func latenessColour(variationSeconds: Int) -> SIMD3<Float> {
        let onTime = SIMD3<Float>(0.75, 0.87, 1.0)
        let amber = SIMD3<Float>(1.0, 0.76, 0.29)
        let red = SIMD3<Float>(1.0, 0.28, 0.22)
        let late = Float(variationSeconds)
        if late <= 0 { return onTime }
        if late <= 180 { return simd_mix(onTime, amber, SIMD3(repeating: late / 180)) }
        if late <= 600 { return simd_mix(amber, red, SIMD3(repeating: (late - 180) / 420)) }
        return red
    }

    // MARK: - Rendering

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        var tweening = false
        for (key, var dot) in dots {
            if dot.tweenStart == -1 {
                dot.tweenStart = time
                dots[key] = dot
            }
            guard dot.tweenStart >= 0 else { continue }
            let t = (time - dot.tweenStart) / Self.tweenDuration
            if t >= 1 {
                dot.current = dot.target
                dot.tweenStart = -2
            } else {
                tweening = true
                let eased = Float(t * t * (3 - 2 * t))  // smoothstep
                dot.current = simd_mix(dot.start, dot.target, SIMD3(repeating: eased))
            }
            dots[key] = dot
        }
        let rebuild = (tweening || needsRebuild) && time - lastRebuild >= Self.rebuildInterval
        if rebuild {
            needsRebuild = tweening
            lastRebuild = time
        }
        let snapshot = rebuild ? Array(dots.values) : []
        lock.unlock()

        if rebuild {
            let geometry = Self.buildPointCloud(snapshot)
            DispatchQueue.main.async { [weak self] in
                self?.node.geometry = geometry
            }
        }
    }

    private static func buildPointCloud(_ dots: [Dot]) -> SCNGeometry? {
        guard !dots.isEmpty else { return nil }

        var positions = [Float]()
        var colours = [Float]()
        var indices = [UInt32]()
        positions.reserveCapacity(dots.count * 3)
        colours.reserveCapacity(dots.count * 4)
        indices.reserveCapacity(dots.count)

        for (i, dot) in dots.enumerated() {
            positions.append(dot.current.x)
            positions.append(dot.current.y)
            positions.append(dot.current.z)

            // Stale fade: full brightness under 20 min, dimming to 0.25 by 45.
            let fade: Float
            if dot.ageSeconds <= fadeAfterSeconds {
                fade = 1
            } else {
                let over = Float(dot.ageSeconds - fadeAfterSeconds)
                let span = Float(dropAfterSeconds - fadeAfterSeconds)
                fade = max(0.25, 1 - 0.75 * over / span)
            }
            colours.append(dot.colour.x * fade)
            colours.append(dot.colour.y * fade)
            colours.append(dot.colour.z * fade)
            colours.append(fade)

            indices.append(UInt32(i))
        }

        let element = SCNGeometryElement(
            data: indices.withUnsafeBufferPointer { Data(buffer: $0) },
            primitiveType: .point,
            primitiveCount: dots.count,
            bytesPerIndex: 4
        )
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 2.5
        element.maximumPointScreenSpaceRadius = 8

        let geometry = SCNGeometry(
            sources: [
                TrackNetworkScene.positionSource(positions),
                TrackNetworkScene.colourSource(colours),
            ],
            elements: [element]
        )
        geometry.firstMaterial = TrackNetworkScene.glowMaterial()
        return geometry
    }
}
