import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO
import UIKit

/// A SwiftUI view that displays a high-definition rotating Earth from a GLB model.
///
/// It attempts to load `earth.glb` from:
/// 1) The app bundle (Copy Bundle Resources), or
/// 2) An asset catalog as a Data asset named "earth" (NSDataAsset)
///
/// If found as a data asset, it writes the data to a temporary file to allow ModelIO to load it.
struct EarthGLBView: UIViewRepresentable {
    var rotationDuration: TimeInterval = 30
    var allowsCameraControl: Bool = false
    var backgroundColor: UIColor = .clear
    var dataAssetName: String = "earth"

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = backgroundColor
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = allowsCameraControl

        let scene = SCNScene()
        scnView.scene = scene

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.wantsHDR = true
        cameraNode.position = SCNVector3(0, 0, 3.0)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1200
        keyLight.eulerAngles = SCNVector3(-0.3, 0.8, 0.0)
        scene.rootNode.addChildNode(keyLight)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        ambient.light?.color = UIColor(white: 0.65, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Load the model (GLB or USDZ)
        if let modelNode = loadEarthNode() {
            // Normalize/center and scale to a reasonable size
            modelNode.scale = normalizedScale(for: modelNode, target: 1.6)
            centerPivot(of: modelNode)

            // Add subtle rotation
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0, 1, 0, 0)
            spin.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
            spin.duration = rotationDuration
            spin.repeatCount = .infinity
            modelNode.addAnimation(spin, forKey: "spin")

            scene.rootNode.addChildNode(modelNode)
            print("[EarthGLBView] Loaded earth model successfully.")
        } else {
            let placeholder = placeholderEarthNode()
            // Add same rotation so UX matches
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0, 1, 0, 0)
            spin.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
            spin.duration = rotationDuration
            spin.repeatCount = .infinity
            placeholder.addAnimation(spin, forKey: "spin")
            scene.rootNode.addChildNode(placeholder)
            print("[EarthGLBView] Showing placeholder sphere because earth model could not be loaded.")
        }

        scnView.isPlaying = true
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // No dynamic updates required for now.
    }

    // MARK: - Loading helpers

    private func loadEarthNode() -> SCNNode? {
        // USDZ-only pipeline
        // 1) Try to load from bundle (earth.usdz)
        if let url = Bundle.main.url(forResource: "earth", withExtension: "usdz") {
            print("[EarthGLBView] Found earth.usdz in bundle at: \(url.path)")
            if let node = nodeFromModel(at: url) { return node }
            print("[EarthGLBView] Failed to build node from bundle USDZ.")
        } else {
            print("[EarthGLBView] earth.usdz not found in bundle resources.")
        }

        // 2) Try to load from asset catalog as Data asset named exactly `dataAssetName` (default: "earth")
        let name = dataAssetName
        if let dataAsset = NSDataAsset(name: name, bundle: .main) {
            do {
                print("[EarthGLBView] Found Data asset '\(name)' (\(dataAsset.data.count) bytes). Treating as USDZ.")
                let tmpURL = try writeToTemporaryFile(data: dataAsset.data, fileName: "earth", ext: "usdz")
                print("[EarthGLBView] Wrote temp USDZ to: \(tmpURL.path)")
                if let node = nodeFromModel(at: tmpURL) { return node }
                print("[EarthGLBView] Failed to build node from Data asset USDZ '", name, "'.")
            } catch {
                print("[EarthGLBView] Failed to write USDZ data to temp file from asset '\(name)': \(error)")
            }
        } else {
            print("[EarthGLBView] No Data asset named '\(name)' found.")
        }

        print("[EarthGLBView] Could not locate or parse earth.usdz from bundle or asset catalog.")
        return nil
    }

    private func nodeFromModel(at url: URL) -> SCNNode? {
        let ext = url.pathExtension.lowercased()
        if ext == "usdz" || ext == "usd" {
            // Load USDZ directly with SceneKit
            do {
                let scene = try SCNScene(url: url, options: nil)
                let container = SCNNode()
                let children = scene.rootNode.childNodes
                if children.isEmpty {
                    print("[EarthGLBView] USDZ scene has no child nodes: \(url.path)")
                    return nil
                }
                for child in children { container.addChildNode(child) }
                return container
            } catch {
                print("[EarthGLBView] Failed to load USDZ at \(url.path): \(error)")
                return nil
            }
        } else {
            // Assume GLB/GLTF via ModelIO
            let asset = MDLAsset(url: url)
            print("[EarthGLBView] MDLAsset contains \(asset.count) top-level objects.")
            let scene = SCNScene(mdlAsset: asset)
            let children = scene.rootNode.childNodes
            if !children.isEmpty {
                let container = SCNNode()
                for child in children { container.addChildNode(child) }
                return container
            }
            print("[EarthGLBView] SCNScene(mdlAsset:) produced no child nodes. Falling back to manual mesh conversion.")
            let container = SCNNode()
            let meshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] ?? []
            print("[EarthGLBView] Fallback found \(meshes.count) MDLMesh objects.")
            for mesh in meshes { container.addChildNode(SCNNode(mdlObject: mesh)) }
            if container.childNodes.isEmpty {
                print("[EarthGLBView] Manual conversion yielded no nodes. The model may be incompatible or empty: \(url.path)")
                return nil
            }
            return container
        }
    }

    private func writeToTemporaryFile(data: Data, fileName: String, ext: String) throws -> URL {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = tmpDir.appendingPathComponent("\(fileName).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Geometry utilities

    private func centerPivot(of node: SCNNode) {
        let (minVec, maxVec) = node.boundingBox
        let center = SCNVector3(
            (minVec.x + maxVec.x) * 0.5,
            (minVec.y + maxVec.y) * 0.5,
            (minVec.z + maxVec.z) * 0.5
        )
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    }

    private func normalizedScale(for node: SCNNode, target: Float) -> SCNVector3 {
        let (minVec, maxVec) = node.boundingBox
        let size = SCNVector3(
            maxVec.x - minVec.x,
            maxVec.y - minVec.y,
            maxVec.z - minVec.z
        )
        let maxDimension = max(size.x, max(size.y, size.z))
        guard maxDimension > 0 else { return SCNVector3(1, 1, 1) }
        let s = target / maxDimension
        return SCNVector3(s, s, s)
    }

    private func placeholderEarthNode() -> SCNNode {
        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 96
        let mat = SCNMaterial()
        if let img = UIImage(named: "earthTexture") {
            mat.diffuse.contents = img
        } else if let dataAsset = NSDataAsset(name: "earthTexture") {
            mat.diffuse.contents = UIImage(data: dataAsset.data)
        } else {
            mat.diffuse.contents = UIColor.systemBlue
        }
        mat.specular.contents = UIColor.white
        mat.shininess = 0.3
        mat.locksAmbientWithDiffuse = true
        sphere.firstMaterial = mat
        let node = SCNNode(geometry: sphere)
        centerPivot(of: node)
        node.scale = SCNVector3(1.2, 1.2, 1.2)
        return node
    }
}

// MARK: - SwiftUI convenience wrapper

extension View {
    /// Convenience modifier to apply a rounded, bordered card style similar to the app's aesthetic.
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
            )
    }
}

#Preview {
    VStack(spacing: 16) {
        Text("Earth GLB Preview").font(.headline)
        EarthGLBView(rotationDuration: 40, allowsCameraControl: false, backgroundColor: .clear, dataAssetName: "earth")
            .frame(height: 260)
            .glassCard(cornerRadius: 20)
            .padding()
    }
}
