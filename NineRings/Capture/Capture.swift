#if DEBUG
import CoreImage
import Foundation
import Metal
import Motion
import RealityKit
import Toy

/// Renders the toy to PNG files without a window and quits: how an agent sees what the app draws.
///
/// Launch the debug app with, for example,
/// `-capture-frames 16 -capture-views side,top,tip -capture-sheet -capture-dir scratch/captures`.
///
/// - `-capture-frames 16`: that many frames evenly across the move, from every ring on (progress 0) to its ring
///   off (progress 1). Or `-capture-progress 0,0.25,0.5` for frames at given progress values.
/// - `-capture-move 3`: ring 3's move in the written moves menu rather than ring 1's; any ring from 1 to 9.
/// - `-capture-views side,top,tip`: the app's camera presets, or a yaw and a pitch in degrees, as `30:20`.
/// - `-capture-sheet`: also lays the frames of each view out on one contact sheet, labelled with their progress
///   and stage.
/// - `-capture-size 1600x1000` (pixels), `-capture-appearance dark`, and `-capture-focus x,y,z,size` to frame a
///   cube of `size` millimetres around a point in the toy's frame instead of the whole move.
///
/// Each frame is posed exactly as the slider poses the app: the app's own player is set to the progress, and the
/// scene draws the pose the player gives. Frames are named `ring<n>-p<progress>-<view>-<appearance>.png`, and
/// sheets `ring<n>-sheet-<view>-<appearance>.png`.
@MainActor
enum Capture {
    struct Request {
        var move: Move
        var progress: [Double]
        var views: [View]
        var focus: (center: SIMD3<Float>, size: Float)?
        var sheet: Bool
        var directory: URL
        var size: CGSize
        var appearance: Backdrop.Appearance
    }

    static let request: Request? = parse(ProcessInfo.processInfo.arguments)

    static func run(_ request: Request) async {
        do {
            try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
            let player = Player(move: request.move)
            let framing = ContentView.framing
            let ring = request.move.ring
            let prefix = "ring\(ring)"
            let renderer = try await Renderer(size: request.size, appearance: request.appearance, floor: framing.lower.y - 6)
            for view in request.views {
                var frames: [ContactSheet.Frame] = []
                for progress in request.progress {
                    // The same path as the slider: set the player's progress, draw the pose it gives.
                    player.progress = progress
                    let name = "\(prefix)-p\(format(progress))-\(view.name)-\(request.appearance.rawValue).png"
                    let url = request.directory.appending(path: name)
                    let box = request.focus.map { ToyBounds(center: $0.center, size: $0.size) } ?? framing
                    let stageName = player.stageName
                    let pose = player.pose
                    let image = try await renderer.render(pose, view: view, framing: box, to: url)
                    print("capture: wrote \(url.path)")
                    frames.append(ContactSheet.Frame(image: image, caption: "\(format(progress))  \(stageName)"))
                }
                if request.sheet {
                    let url = request.directory.appending(path: "\(prefix)-sheet-\(view.name)-\(request.appearance.rawValue).png")
                    try ContactSheet.write(frames, title: "Ring \(ring) coming off, seen from the \(view.title)", appearance: request.appearance, to: url)
                    print("capture: wrote \(url.path)")
                }
            }
            exit(0)
        } catch {
            print("capture: failed: \(error)")
            exit(1)
        }
    }

    private static func format(_ progress: Double) -> String {
        progress.formatted(.number.precision(.fractionLength(3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func parse(_ arguments: [String]) -> Request? {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let progress: [Double]
        if let list = value("-capture-progress") {
            progress = list.split(separator: ",").compactMap { Double($0) }
        } else if let count = value("-capture-frames").flatMap({ Int($0) }), count >= 2 {
            progress = (0..<count).map { Double($0) / Double(count - 1) }
        } else {
            return nil
        }
        let views = (value("-capture-views") ?? "side,top,tip").split(separator: ",").compactMap { View(String($0)) }
        let focusNumbers = value("-capture-focus")?.split(separator: ",").compactMap { Float($0) } ?? []
        let focus = focusNumbers.count == 4 ? (SIMD3(focusNumbers[0], focusNumbers[1], focusNumbers[2]), focusNumbers[3]) : nil
        let directory = value("-capture-dir").map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory.appending(path: "captures")
        let dimensions = (value("-capture-size") ?? "1600x1000").split(separator: "x").compactMap { Double($0) }
        let size = dimensions.count == 2 ? CGSize(width: dimensions[0], height: dimensions[1]) : CGSize(width: 1600, height: 1000)
        let appearance = value("-capture-appearance").flatMap(Backdrop.Appearance.init(rawValue:)) ?? .light
        let ring = value("-capture-move").flatMap { Int($0) } ?? 1
        guard let move = Player.moves.first(where: { $0.ring == ring }) else { return nil }
        return Request(
            move: move, progress: progress, views: views, focus: focus, sheet: arguments.contains("-capture-sheet"),
            directory: directory, size: size, appearance: appearance
        )
    }

    /// Where a capture looks from.
    struct View {
        var name: String
        var title: String
        var yaw: Float
        var pitch: Float

        init?(_ text: String) {
            if let preset = CameraPreset(rawValue: text) {
                (name, title, yaw, pitch) = (text, preset.title.lowercased(), preset.angles.yaw, preset.angles.pitch)
                return
            }
            let degrees = text.split(separator: ":").compactMap { Float($0) }
            guard degrees.count == 2 else { return nil }
            name = "yaw\(Int(degrees[0]))-pitch\(Int(degrees[1]))"
            title = "yaw \(Int(degrees[0]))°, pitch \(Int(degrees[1]))°"
            (yaw, pitch) = (degrees[0] * .pi / 180, degrees[1] * .pi / 180)
        }
    }

    /// An offscreen RealityKit renderer holding the app's scene.
    private final class Renderer {
        private let scene: ToyScene
        private let renderer: RealityRenderer
        private let camera = Entity()
        private let texture: any MTLTexture
        private let output: RealityRenderer.CameraOutput
        private let size: CGSize

        init(size: CGSize, appearance: Backdrop.Appearance, floor: Float) async throws {
            self.size = size
            scene = try await ToyScene.make()
            scene.setFloor(floor)
            renderer = try RealityRenderer()
            renderer.entities.append(scene.root)
            camera.components.set(OrbitCamera.component())
            renderer.entities.append(camera)
            renderer.activeCamera = camera
            renderer.cameraSettings.colorBackground = .color(appearance.backgroundColor)
            renderer.cameraSettings.antialiasing = .multisample4X

            guard let device = MTLCreateSystemDefaultDevice() else { throw CaptureError.noMetal }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: Int(size.width), height: Int(size.height), mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw CaptureError.noTexture }
            self.texture = texture
            output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        }

        /// Draws `pose`, writes it to `url` and returns the image.
        func render(_ pose: ToyPose, view: View, framing box: ToyBounds, to url: URL) async throws -> CGImage {
            scene.apply(pose)
            camera.transform = OrbitCamera.framing(yaw: view.yaw, pitch: view.pitch, of: box, in: Viewport(size: size)).transform
            // The first frame after a change can still be settling resources; draw twice and keep the second.
            for _ in 0..<2 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    do {
                        try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in
                            continuation.resume()
                        })
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            // The texture is sRGB-encoded, so Metal hands Core Image linear values when it reads it.
            guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]) else {
                throw CaptureError.noImage
            }
            // Metal's rows run top to bottom, Core Image's bottom to top.
            let upright = image.oriented(.downMirrored)
            let context = CIContext()
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
            try context.writePNGRepresentation(of: upright, to: url, format: .RGBA8, colorSpace: sRGB)
            guard let picture = context.createCGImage(upright, from: upright.extent, format: .RGBA8, colorSpace: sRGB) else {
                throw CaptureError.noImage
            }
            return picture
        }
    }

    enum CaptureError: Error {
        case noMetal, noTexture, noImage, noSheet
    }
}
#endif
