import SwiftUI
import SceneKit
import CoreMotion
import simd

/// A clickable marker shown inside the panorama (e.g. a doorway leading to another room).
struct SceneHotspot: Identifiable, Equatable {
    let id: UUID
    let yaw: Double
    let pitch: Double
    let label: String
}

/// Lets SwiftUI ask the renderer where the camera is currently looking.
final class PanoramaSceneController {
    fileprivate weak var coordinator: PanoramaSceneView.Coordinator?

    /// Current viewing direction as (yaw, pitch) in radians.
    func currentDirection() -> (yaw: Double, pitch: Double)? {
        coordinator?.currentDirection()
    }
}

/// Renders an equirectangular 360° image on the inside of a sphere.
/// Drag to look around, pinch to zoom, double-tap to reset; optional gyroscope control.
struct PanoramaSceneView: UIViewRepresentable {
    let image: UIImage
    var hotspots: [SceneHotspot] = []
    @Binding var motionEnabled: Bool
    var resetToken: Int = 0
    var controller: PanoramaSceneController?
    var onHotspotTap: ((UUID) -> Void)?
    var onBackgroundTap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onHotspotTap = onHotspotTap
        coordinator.onBackgroundTap = onBackgroundTap
        controller?.coordinator = coordinator
        if coordinator.currentImage !== image {
            coordinator.setImage(image)
        }
        coordinator.setHotspots(hotspots)
        if coordinator.lastResetToken != resetToken {
            coordinator.lastResetToken = resetToken
            coordinator.reset()
        }
        coordinator.setMotion(enabled: motionEnabled)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.setMotion(enabled: false)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private let sphereNode: SCNNode
        private let hotspotRoot = SCNNode()
        private weak var view: SCNView?
        private let motionManager = CMMotionManager()

        private(set) var currentImage: UIImage?
        private var currentHotspots: [SceneHotspot] = []
        var lastResetToken = 0
        var onHotspotTap: ((UUID) -> Void)?
        var onBackgroundTap: (() -> Void)?

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var fieldOfView: CGFloat = 75
        private var pinchStartFOV: CGFloat = 75

        private static let minFOV: CGFloat = 30
        private static let maxFOV: CGFloat = 100
        private static let sphereRadius: CGFloat = 10
        private static let hotspotDistance: Float = 7
        private static let hotspotPrefix = "hotspot:"

        override init() {
            let sphere = SCNSphere(radius: Self.sphereRadius)
            sphere.segmentCount = 96
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.cullMode = .front // Seen from inside.
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1) // Un-mirror when seen from inside.
            material.diffuse.wrapS = .repeat
            material.diffuse.mipFilter = .linear
            sphere.firstMaterial = material
            sphereNode = SCNNode(geometry: sphere)

            super.init()

            let camera = SCNCamera()
            camera.fieldOfView = fieldOfView
            camera.zNear = 0.1
            camera.zFar = 100
            cameraNode.camera = camera

            scene.rootNode.addChildNode(sphereNode)
            scene.rootNode.addChildNode(hotspotRoot)
            scene.rootNode.addChildNode(cameraNode)
            applyManualOrientation()
        }

        func attach(to view: SCNView) {
            self.view = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: doubleTap)
            [pan, pinch, doubleTap, tap].forEach {
                $0.delegate = self
                view.addGestureRecognizer($0)
            }
        }

        func setImage(_ image: UIImage) {
            currentImage = image
            sphereNode.geometry?.firstMaterial?.diffuse.contents = image
        }

        func reset() {
            yaw = 0
            pitch = 0
            fieldOfView = 75
            cameraNode.camera?.fieldOfView = fieldOfView
            if !motionManager.isDeviceMotionActive { applyManualOrientation() }
        }

        // MARK: Hotspots

        func setHotspots(_ hotspots: [SceneHotspot]) {
            guard hotspots != currentHotspots else { return }
            currentHotspots = hotspots
            hotspotRoot.childNodes.forEach { $0.removeFromParentNode() }
            for hotspot in hotspots {
                hotspotRoot.addChildNode(makeHotspotNode(hotspot))
            }
        }

        private func makeHotspotNode(_ hotspot: SceneHotspot) -> SCNNode {
            let image = Self.hotspotImage(label: hotspot.label)
            let height: CGFloat = 0.55
            let plane = SCNPlane(width: height * image.size.width / image.size.height, height: height)
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.readsFromDepthBuffer = false
            plane.firstMaterial = material

            let node = SCNNode(geometry: plane)
            node.name = Self.hotspotPrefix + hotspot.id.uuidString
            node.renderingOrder = 10
            let constraint = SCNBillboardConstraint()
            constraint.freeAxes = .all
            node.constraints = [constraint]
            node.simdPosition = Self.direction(yaw: Float(hotspot.yaw), pitch: Float(hotspot.pitch)) * Self.hotspotDistance
            return node
        }

        /// A dark translucent pill with an arrow and the destination's name.
        private static func hotspotImage(label: String) -> UIImage {
            let font = UIFont.systemFont(ofSize: 34, weight: .semibold)
            let text = label as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let height: CGFloat = 76
            let iconSize: CGFloat = 48
            let width = 14 + iconSize + 14 + ceil(textSize.width) + 28
            let size = CGSize(width: width, height: height)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
                UIColor.white.withAlphaComponent(0.9).setStroke()
                let border = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5),
                                          cornerRadius: height / 2 - 1.5)
                border.lineWidth = 3
                border.stroke()

                let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
                if let icon = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    icon.draw(in: CGRect(x: 14, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                }
                text.draw(at: CGPoint(x: 14 + iconSize + 14, y: (height - textSize.height) / 2),
                          withAttributes: [.font: font, .foregroundColor: UIColor.white])
            }
        }

        /// Unit vector for a viewing direction; yaw 0 / pitch 0 looks down -Z.
        private static func direction(yaw: Float, pitch: Float) -> SIMD3<Float> {
            SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        }

        func currentDirection() -> (yaw: Double, pitch: Double) {
            let front = simd_normalize(cameraNode.presentation.simdWorldFront)
            let yaw = atan2(-front.x, -front.z)
            let pitch = asin(max(-1, min(1, front.y)))
            return (Double(yaw), Double(pitch))
        }

        // MARK: Gestures

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.rootNode: hotspotRoot
            ])
            if let name = hits.lazy.compactMap({ $0.node.name }).first(where: { $0.hasPrefix(Self.hotspotPrefix) }),
               let id = UUID(uuidString: String(name.dropFirst(Self.hotspotPrefix.count))) {
                onHotspotTap?(id)
            } else {
                onBackgroundTap?()
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)

            // Scale by zoom level so dragging feels like grabbing the image.
            let radiansPerPoint = Float(fieldOfView / max(view.bounds.height, 1)) * .pi / 180
            yaw += Float(translation.x) * radiansPerPoint
            if !motionManager.isDeviceMotionActive {
                pitch += Float(translation.y) * radiansPerPoint
                pitch = max(-.pi / 2, min(.pi / 2, pitch))
                applyManualOrientation()
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartFOV = fieldOfView
            case .changed:
                fieldOfView = max(Self.minFOV, min(Self.maxFOV, pinchStartFOV / gesture.scale))
                cameraNode.camera?.fieldOfView = fieldOfView
            default:
                break
            }
        }

        @objc private func handleDoubleTap() {
            reset()
        }

        private func applyManualOrientation() {
            let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            cameraNode.simdOrientation = yawRotation * pitchRotation
        }

        // MARK: Device motion

        func setMotion(enabled: Bool) {
            guard motionManager.isDeviceMotionAvailable else { return }
            if enabled, !motionManager.isDeviceMotionActive {
                yaw = 0
                motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
                    guard let self, let motion else { return }
                    self.applyMotion(motion.attitude.quaternion)
                }
            } else if !enabled, motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
                yaw = 0
                pitch = 0
                applyManualOrientation()
            }
        }

        private func applyMotion(_ q: CMQuaternion) {
            let attitude = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            // Core Motion uses Z-up; SceneKit uses Y-up.
            let worldCorrection = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            let yawOffset = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let screenRotation = simd_quatf(angle: screenAngle(), axis: SIMD3<Float>(0, 0, 1))
            cameraNode.simdOrientation = yawOffset * worldCorrection * attitude * screenRotation
        }

        /// Compensates for the interface rotating with the device in landscape.
        private func screenAngle() -> Float {
            switch view?.window?.windowScene?.interfaceOrientation {
            case .landscapeRight: return -.pi / 2
            case .landscapeLeft: return .pi / 2
            case .portraitUpsideDown: return .pi
            default: return 0
            }
        }
    }
}
