import Foundation

/// The thresholds every check in this library uses. Hold one per app — build it from your own
/// settings store and pass it in; the library never reads user defaults itself.
///
/// The defaults are the engine's operating points: identify at 0.80 and liveness at 0.5.
///
/// ```swift
/// let limits = FaceLimits(match: 0.82, liveness: 0.6)
/// let outcome = FaceGallery.shared.identify(photo, limits: limits, livenessOn: true)
/// ```
public struct FaceLimits: Equatable {
    /// Lowest similarity that counts as the same person (1:N identify and the duplicate check).
    public let match: Float
    /// Lowest liveness score that counts as a live face.
    public let liveness: Float
    /// Largest head turn allowed, in degrees.
    public let yaw: Float
    public let roll: Float
    public let pitch: Float

    public static let defaultMatch: Float = 0.80
    public static let defaultLiveness: Float = 0.50
    public static let defaultAngle: Float = 20

    private static let epsilon: Float = 0.0001

    /// The engine's operating points.
    public static let `default` = FaceLimits()

    public init(
        match: Float = FaceLimits.defaultMatch,
        liveness: Float = FaceLimits.defaultLiveness,
        yaw: Float = FaceLimits.defaultAngle,
        roll: Float = FaceLimits.defaultAngle,
        pitch: Float = FaceLimits.defaultAngle
    ) {
        self.match = match
        self.liveness = liveness
        self.yaw = yaw
        self.roll = roll
        self.pitch = pitch
    }

    /// True when `score` counts as a live face. A NaN score (liveness not run) is not live.
    public func isLive(_ score: Float) -> Bool {
        !score.isNaN && score + FaceLimits.epsilon >= liveness
    }

    /// True when the head is within `yaw`, `roll` and `pitch` of facing the camera.
    public func poseOk(yaw yawDeg: Float, roll rollDeg: Float, pitch pitchDeg: Float) -> Bool {
        abs(yawDeg) <= yaw && abs(rollDeg) <= roll && abs(pitchDeg) <= pitch
    }

    /// True when `similarity` counts as the same person.
    public func matches(_ similarity: Float) -> Bool {
        similarity >= match
    }
}
