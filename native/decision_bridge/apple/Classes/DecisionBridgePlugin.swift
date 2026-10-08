#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import Foundation
import ImageIO

@_silgen_name("d1_create") private func createEngine() -> UnsafeMutableRawPointer
@_silgen_name("d1_destroy") private func destroyEngine(_ engine: UnsafeMutableRawPointer)
@_silgen_name("d1_load") private func loadEngine(_ engine: UnsafeMutableRawPointer, _ json: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("d1_run") private func runEngine(_ engine: UnsafeMutableRawPointer, _ json: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("d1_free") private func freeResult(_ pointer: UnsafeMutablePointer<CChar>)
@_silgen_name("d1_cancel") private func cancelEngine(_ engine: UnsafeMutableRawPointer)
@_silgen_name("d1_unload") private func unloadEngine(_ engine: UnsafeMutableRawPointer)

public final class DecisionBridgePlugin: NSObject, FlutterPlugin {
    private let engine = createEngine()
    private let queue = DispatchQueue(label: "app.d1lab.runtime", qos: .userInitiated)
    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let channel = FlutterMethodChannel(name: "d1_lab/runtime", binaryMessenger: messenger)
        registrar.addMethodCallDelegate(DecisionBridgePlugin(), channel: channel)
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "cancel" { cancelEngine(engine); result(nil); return }
        guard ["load", "run", "unload", "prepareImage"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
        let method = call.method
        let text = call.arguments as? String ?? "{}"
        queue.async { [self] in
            if method == "prepareImage" {
                do {
                    guard let args = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                          let input = args["input"] as? String, let output = args["output"] as? String,
                          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil)
                    else { throw NSError(domain: "d1", code: 1, userInfo: [NSLocalizedDescriptionKey: "画像を読み込めませんでした"]) }
                    let requestedSize = args["maxPixelSize"] as? Int ?? 2048
                    guard [256, 512, 768, 1024, 1536, 2048].contains(requestedSize)
                    else { throw NSError(domain: "d1", code: 3, userInfo: [NSLocalizedDescriptionKey: "画像サイズを選び直してください"]) }
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                    var sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
                    var sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
                    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                    if [5, 6, 7, 8].contains(orientation) { swap(&sourceWidth, &sourceHeight) }
                    // Keep aspect ratio and never enlarge a smaller source image.
                    let sourceEdge = max(sourceWidth, sourceHeight)
                    let outputEdge = sourceEdge > 0 ? min(requestedSize, sourceEdge) : requestedSize
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: outputEdge,
                          ] as CFDictionary),
                          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)
                    else { throw NSError(domain: "d1", code: 1, userInfo: [NSLocalizedDescriptionKey: "画像を読み込めませんでした"]) }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "d1", code: 2) }
                    let response = try JSONSerialization.data(withJSONObject: ["width": image.width, "height": image.height, "maxPixelSize": requestedSize, "sourceWidth": sourceWidth, "sourceHeight": sourceHeight, "orientationCorrected": true])
                    let json = String(decoding: response, as: UTF8.self)
                    DispatchQueue.main.async { result(json) }
                } catch {
                    let message = error.localizedDescription
                    DispatchQueue.main.async { result(FlutterError(code: "image", message: message, details: nil)) }
                }
                return
            }
            if method == "unload" {
                unloadEngine(engine)
                DispatchQueue.main.async { result(nil) }
                return
            }
            let pointer = text.withCString { method == "load" ? loadEngine(engine, $0) : runEngine(engine, $0) }
            let response = pointer.map { String(cString: $0) }
            if let pointer = pointer { freeResult(pointer) }
            DispatchQueue.main.async {
                if let response = response { result(response) }
                else { result(FlutterError(code: "allocation", message: "結果のメモリを確保できませんでした", details: nil)) }
            }
        }
    }
    deinit { destroyEngine(engine) }
}
