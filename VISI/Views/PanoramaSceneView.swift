import SwiftUI
import SceneKit
import CoreMotion
import simd

/// Renders an equirectangular 360° image on the inside of a sphere.
/// Drag to look around, pinch to zoom, double-tap to reset, or enable motion to look around by moving the phone.
struct PanoramaSceneView: UIViewRepresentable {
    let image: UIImage
    @Binding var motionEnabled: Bool
    var resetToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        context.coordinator.attach(to: view)
        context.coordinator.setImage(image)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.currentImage !== image {
            coordinator.setImage(image)
        }
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
        private weak var view: SCNView?
        private let motionManager = CMMotionManager()

        private(set) var currentImage: UIImage?
        var lastResetToken = 0

        // Manual navigation state (radians).
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var fieldOfView: CGFloat = 75
        private var pinchStartFOV: CGFloat = 75

        private static let minFOV: CGFloat = 30
        private static let maxFOV: CGFloat = 100

        override init() {
            let sphere = SCNSphere(radius: 10)
            sphere.segmentCount = 96
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.cullMode = .front // We look at the sphere from inside.
            // Mirror horizontally so the image isn't reversed when seen from inside.
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
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
            cameraNode.position = SCNVector3Zero

            scene.rootNode.addChildNode(sphereNode)
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
            [pan, pinch, doubleTap].forEach {
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

        // MARK: Gestures

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)

            // Scale rotation by zoom level so dragging feels like grabbing the image.
            let radiansPerPoint = Float(fieldOfView / view.bounds.height) * .pi / 180
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
