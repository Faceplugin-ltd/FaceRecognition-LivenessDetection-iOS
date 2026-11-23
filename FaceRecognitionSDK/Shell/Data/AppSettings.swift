import FaceRecognitionKit
import Foundation

/// Persisted demo settings. Match and liveness defaults are the engine's operating points:
/// 0.80 for identity verification, live when the liveness score is at or above 0.5.
enum AppSettings {

    static let defaultThreshold: Float = 0.80
    static let minThreshold: Float = 0.70
    static let maxThreshold: Float = 0.90

    static let defaultLiveness: Float = 0.50
    static let defaultAngle: Float = 20

    private static let defaults = UserDefaults.standard
    private static let keyThreshold = "threshold"
    private static let keyLivenessOn = "liveness"
    private static let keyLivenessThreshold = "liveness_threshold"
    private static let keyYaw = "yaw"
    private static let keyRoll = "roll"
    private static let keyPitch = "pitch"
    private static let keyAuto = "auto_capture"
    private static let keySkipReview = "skip_review"
    private static let keySchema = "schema"
    private static let schema = 5

    /// Moves old installs onto the current defaults once.
    static func migrateIfNeeded() {
        guard defaults.integer(forKey: keySchema) < schema else { return }
        defaults.set(defaultThreshold, forKey: keyThreshold)
        defaults.set(defaultLiveness, forKey: keyLivenessThreshold)
        defaults.set(defaultAngle, forKey: keyYaw)
        defaults.set(defaultAngle, forKey: keyRoll)
        defaults.set(defaultAngle, forKey: keyPitch)
        defaults.set(false, forKey: keyLivenessOn)
        defaults.set(schema, forKey: keySchema)
    }

    /// Every threshold the library checks against, read from these settings.
    static var limits: FaceLimits {
        FaceLimits(match: threshold, liveness: livenessThreshold, yaw: yaw, roll: roll, pitch: pitch)
    }

    static var threshold: Float {
        get { clampThreshold(float(keyThreshold, defaultThreshold)) }
        set { defaults.set(clampThreshold(newValue), forKey: keyThreshold) }
    }

    static func clampThreshold(_ value: Float) -> Float {
        (min(max(value, minThreshold), maxThreshold) * 100).rounded() / 100
    }

    static var livenessOn: Bool {
        get { defaults.object(forKey: keyLivenessOn) as? Bool ?? false }
        set { defaults.set(newValue, forKey: keyLivenessOn) }
    }

    static var livenessThreshold: Float {
        get { unit(keyLivenessThreshold, defaultLiveness) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: keyLivenessThreshold) }
    }

    static var yaw: Float {
        get { angle(keyYaw) }
        set { defaults.set(min(max(newValue, 0), 90), forKey: keyYaw) }
    }

    static var roll: Float {
        get { angle(keyRoll) }
        set { defaults.set(min(max(newValue, 0), 90), forKey: keyRoll) }
    }

    static var pitch: Float {
        get { angle(keyPitch) }
        set { defaults.set(min(max(newValue, 0), 90), forKey: keyPitch) }
    }

    static var autoCapture: Bool {
        get { defaults.bool(forKey: keyAuto) }
        set { defaults.set(newValue, forKey: keyAuto) }
    }

    /// Skip the post-capture review when every check passes. Off by default: the review is
    /// where the SDK is seen refusing a bad capture, which is worth showing a customer.
    static var skipReview: Bool {
        get { defaults.bool(forKey: keySkipReview) }
        set { defaults.set(newValue, forKey: keySkipReview) }
    }

    static func reset() {
        threshold = defaultThreshold
        livenessOn = false
        livenessThreshold = defaultLiveness
        yaw = defaultAngle
        roll = defaultAngle
        pitch = defaultAngle
    }

    private static func float(_ key: String, _ fallback: Float) -> Float {
        defaults.object(forKey: key) == nil ? fallback : defaults.float(forKey: key)
    }

    private static func unit(_ key: String, _ fallback: Float) -> Float {
        min(max(float(key, fallback), 0), 1)
    }

    private static func angle(_ key: String) -> Float {
        min(max(float(key, defaultAngle), 0), 90)
    }
}

/// The license key compiled into the demo. Tied to bundle id `com.faceplugin.facerecognition.app`.
enum BuiltInLicense {
    static let key =
        "FP1.RlBMMQMAAQBRd7YXphKTsuScCyMJAgAAhoo0FQMD14LDxdAIXnGb9YY3j6ixGJEBguNlNIZ0lK9W6m0b97Mo5mnxfgyX9ln71am4N0PEb5NDRGqT2fWDJwq4MF+H7fc4q3x1Fjox5BikKKWVfaKtQhviOMyPXoha1LIZQXJkTocEXJHQg3V/AKXOcdGcgv8OQ0R6UV7sPCCu66b9jtAR7ZBhJIeKze9xFGKM81tQsxaswvLxHGMl+1sbQpXPA/+7D/qnDM9nzEJn2TD4YKQcmhVhZFcKB0aMqME0yQhQlKvTEfR9dHLmSfIuQxkMvSGWXZWOLS5OYiBVRt4hVVPgVc0bwzvHm0CsMiYAKZ861ubMWdGT/lNiXPxgsifMEdXsqzv09RD0p7JjdhXD4nYgv3mNJwYbCls30UzkBq9IUu3Y5hZfYEGnnoK2zI1tDmnObAT4l+bNBbERshHEnKtL0Ht03ZEB9NN/dqOjsmPiLf8J7WTclVscWV3aOFDzQJMmjHh2bDT30RBjSsIRdlaJNyU3iLKXE3jelKmnOU6No7JInb4f+EPLUpDyghOouJL4pdiCgxkroRYG7VUc8RO2i2r4BMDcgkSj13JBij9g9G/UHUFjkh+rpzIzRR8jUm2OvqEoumwCuFInnEbv2X889Mi/Y/Fq0PuWTwZ72tSHYsMc3lmANbPeBVZgOcppiiLwMVKol5T6zhcYPWgSPRRiytiLADCBiAJCAWPTjrXmiHhtgG+Kb/mFDrSn3ECPz2dhe6JWAlTYFvvGcGI8UL7iEYfnABq747W8ADpsSwTmFekDd5T/fjdF4MLxAkIByJ0V6SL5nsg1Ms1jtoBwed190hwTi7vKsPlePitp22HbTzYmvg3LpNb/X0ktQkKBKsN51OSCac3+QS4waP86ook="
}

/// Hands the last identify or attribute result to the next screen without copying images around.
enum ResultStore {
    static var identify: IdentifyResult?
    static var attribute: AttributeResult?
}
