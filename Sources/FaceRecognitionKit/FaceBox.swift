import CoreGraphics
import Foundation

/// One detected face with every attribute the engine returned, in the shape the screens use.
public struct FaceBox {
    public let box: CGRect
    /// Engine detection score, NaN when not reported.
    public let score: Float
    public let liveness: Float
    public let livenessLabel: String
    public let faceQuality: Float
    public let qualityLabel: String
    public let yaw: Float
    public let roll: Float
    public let pitch: Float
    public let age: Int
    public let genderLabel: String
    public let emotionLabel: String
    public let maskLabel: String
    /// Smile confidence 0..1, NaN when not computed.
    public let smile: Float
    /// Inner-lip gap over mouth width, 0..1, NaN when not computed.
    public let mouthOpened: Float
    public let leftEyeClosed: Float
    public let rightEyeClosed: Float
    public let eyesLeftLabel: String
    public let eyesRightLabel: String
    public let landmarks: [CGPoint]
    /// Everything the engine reported, including keys this struct does not name.
    public let attributes: [String: FaceAttribute]
    /// The engine face used for a later template.
    public let source: FaceRecognitionFace

    public var landmarkCount: Int { landmarks.count }
    public var width: CGFloat { box.width }
    public var height: CGFloat { box.height }
    public var boxRect: CGRect { box }

    public init(_ face: FaceRecognitionFace) {
        box = face.bounds
        score = face.score
        liveness = face.liveness
        if face.liveness.isNaN {
            livenessLabel = ""
        } else {
            livenessLabel = face.liveness > FaceRecognitionSDK.liveness_THRESHOLD() ? "Live" : "Fake"
        }
        faceQuality = face.quality.isNaN ? face.score : face.quality
        qualityLabel = ""
        yaw = face.yaw.isNaN ? 0 : face.yaw
        roll = face.roll.isNaN ? 0 : face.roll
        pitch = face.pitch.isNaN ? 0 : face.pitch
        age = Int(face.age)
        genderLabel = face.genderLabel
        if face.smile.isNaN {
            emotionLabel = ""
            smile = Float.nan
        } else {
            smile = face.smile
            emotionLabel = face.smile >= 0.5 ? "Smiling" : "Neutral"
        }
        maskLabel = ""
        mouthOpened = face.mouthOpen
        if face.eyesOpen.isNaN {
            leftEyeClosed = 0
            rightEyeClosed = 0
            eyesLeftLabel = ""
            eyesRightLabel = ""
        } else {
            let closed = 1 - face.eyesOpen
            leftEyeClosed = closed
            rightEyeClosed = closed
            let label = face.eyesOpen >= 0.5 ? "Open" : "Closed"
            eyesLeftLabel = label
            eyesRightLabel = label
        }
        landmarks = FaceBox.points(face.points)
        attributes = [:]
        source = face
    }

    private static func points(_ raw: [NSNumber]) -> [CGPoint] {
        var out: [CGPoint] = []
        var i = 0
        while i + 1 < raw.count {
            out.append(CGPoint(x: CGFloat(truncating: raw[i]), y: CGFloat(truncating: raw[i + 1])))
            i += 2
        }
        return out
    }
}

/// Which estimators to run. Fewer flags means a faster frame.
public struct FaceDetectionParam {
    public var liveness = false
    public var quality = false
    public var pose = true
    public var landmarks = true
    public var ageGender = false
    public var eyes = false
    public var expression = false
    public var mask = false
    public var glasses = false

    public init() {}

    /// Everything the engine can report. Used for the still after a capture and for Attribute.
    public static func allAttributes() -> FaceDetectionParam {
        var p = FaceDetectionParam()
        p.liveness = true
        p.quality = true
        p.ageGender = true
        p.eyes = true
        p.expression = true
        p.mask = true
        p.glasses = true
        return p
    }

    public func options() -> FaceRecognitionDetectOptions {
        let options = FaceRecognitionDetectOptions()
        options.liveness = liveness
        options.quality = quality
        options.pose = pose
        options.ageGender = ageGender
        options.eyes = eyes
        options.expression = expression
        options.points = landmarks
        return options
    }
}
