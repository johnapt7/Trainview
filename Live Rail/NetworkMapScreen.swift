import SceneKit
import SwiftUI

/// Full-screen 3D map of the GB rail network with every active train shown
/// live, coloured by lateness. The scene is always dark regardless of app
/// appearance — the HUD uses fixed light-on-dark colours to match.
struct NetworkMapScreen: View {
    let onBack: () -> Void

    @State private var controller = LiveTrainsController()
    @State private var trainCount: Int?
    @State private var feedError = false
    @State private var tracksReady = false
    @State private var tracksFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NetworkSceneView(controller: controller, tracksReady: $tracksReady, tracksFailed: $tracksFailed)
                .ignoresSafeArea()

            if !tracksReady && !tracksFailed {
                ProgressView()
                    .tint(.white.opacity(0.6))
            }
            if tracksFailed {
                Text("Couldn't load the track model")
                    .font(.mono(12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .background(Color(red: 0.02, green: 0.027, blue: 0.05))
        .preferredColorScheme(.dark)
        .onAppear {
            controller.onCountChange = { trainCount = $0 }
            controller.onError = { feedError = $0 }
            controller.start()
        }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            // The poll loop keeps its cadence; just stop/start around
            // backgrounding so we never poll while suspended.
            if phase == .active {
                controller.start()
            } else {
                controller.stop()
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 3) {
                Text("NETWORK")
                    .font(.mono(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.92))
                Text(statusLine)
                    .font(.mono(9))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var statusLine: String {
        if feedError { return "LIVE FEED UNAVAILABLE" }
        guard let trainCount else { return "CONNECTING…" }
        return "\(trainCount.formatted()) TRAINS LIVE"
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                legendDot(colour: Color(red: 0.75, green: 0.87, blue: 1.0), label: "ON TIME")
                legendDot(colour: Color(red: 1.0, green: 0.76, blue: 0.29), label: "LATE")
                legendDot(colour: Color(red: 1.0, green: 0.28, blue: 0.22), label: "10 MIN +")
            }
            Text("Contains Network Rail data")
                .font(.mono(8))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.bottom, 12)
    }

    private func legendDot(colour: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 6, height: 6)
            Text(label)
                .font(.mono(8, weight: .medium))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct NetworkSceneView: UIViewRepresentable {
    let controller: LiveTrainsController
    @Binding var tracksReady: Bool
    @Binding var tracksFailed: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let (scene, cameraNode) = TrackNetworkScene.makeScene()
        view.scene = scene
        view.backgroundColor = UIColor(red: 0.02, green: 0.027, blue: 0.05, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.pointOfView = cameraNode
        view.delegate = controller
        view.isPlaying = true  // keep the render loop alive for dot tweens

        scene.rootNode.addChildNode(controller.node)

        // Orbit / pinch / pan around the network centre.
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3Zero

        // 186k vertices — parse and build off the main thread, attach when done.
        Task.detached(priority: .userInitiated) {
            do {
                let trackNode = try TrackNetworkScene.buildTrackNode()
                await MainActor.run {
                    scene.rootNode.addChildNode(trackNode)
                    tracksReady = true
                }
            } catch {
                await MainActor.run { tracksFailed = true }
            }
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

#Preview {
    NetworkMapScreen(onBack: {})
}
