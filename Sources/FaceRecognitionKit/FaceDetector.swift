import Foundation
import UIKit

/// One-shot detection and template extraction on a still image.
///
/// The engine is not concurrent, so every call here goes through `FaceRecognitionSDKQueue`.
/// Call these off the main thread — `FaceEngine.shared.worker` is one.
///
/// ```swift
/// FaceEngine.shared.worker.async {
///     let faces = FaceDetector.detect(photo, param: .allAttributes())
///     let template = faces.first.flatMap { FaceDetector.template(photo, face: $0) }
/// }
/// ```
public enum FaceDetector {

    /// Every face in `image`, with the attributes `param` asks for. Largest face first.
    public static func detect(_ image: UIImage, param: FaceDetectionParam = FaceDetectionParam()) -> [FaceBox] {
        guard FaceEngine.shared.isReady else { return [] }
        return FaceRecognitionSDKQueue.sync {
            guard let frame = FaceRecognitionImage.fromUIImage(image) else { return [] }
            defer { frame.close() }
            return frame.detect(param.options())
                .map(FaceBox.init)
                .sorted { $0.box.width * $0.box.height > $1.box.width * $1.box.height }
        }
    }

    /// The template for `face`, or nil when the engine could not read it.
    public static func template(_ image: UIImage, face: FaceBox) -> Data? {
        guard FaceEngine.shared.isReady else { return nil }
        return FaceRecognitionSDKQueue.sync {
            FaceRecognitionSDK.template(from: image, face: face.source)
        }
    }

    /// The template for the largest face in `image`.
    public static func template(_ image: UIImage) -> Data? {
        detect(image).first.flatMap { template(image, face: $0) }
    }

    /// Similarity of two templates, 0..1.
    public static func similarity(_ a: Data, _ b: Data) -> Float {
        FaceRecognitionSDKQueue.sync {
            FaceRecognitionSDK.similarity(withFeature1: a, feature2: b)
        }
    }
}
