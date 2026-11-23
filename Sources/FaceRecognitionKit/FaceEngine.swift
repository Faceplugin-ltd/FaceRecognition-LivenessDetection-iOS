import Foundation
import UIKit

/// Process-wide engine owner: activation and init on a background queue, the serial queue every
/// SDK call goes through, and a small state observable for the UI.
///
/// Call `start` once, for example from `application(_:didFinishLaunchingWithOptions:)`.
public final class FaceEngine {

    public enum State: Equatable {
        case loading
        case ready
        case notActivated
        case licenseInvalid
        case licenseExpired
        case failed
        case sdkMissing
    }

    public static let shared = FaceEngine()

    /// Posted on the main queue whenever `state` changes.
    public static let stateDidChange = Notification.Name("com.faceplugin.FaceEngine.stateDidChange")

    private let lock = NSLock()
    private var listeners: [UUID: (State) -> Void] = [:]
    private var storedState: State = .loading

    private init() {}

    public private(set) var state: State {
        get { lock.lock(); defer { lock.unlock() }; return storedState }
        set { lock.lock(); storedState = newValue; lock.unlock() }
    }

    public var isReady: Bool { state == .ready }

    /// Background queue for enroll, identify and import. Every SDK call is serialized separately
    /// by `FaceRecognitionSDKQueue`, so work queued here never runs two engine calls at once.
    public let worker = DispatchQueue(label: "com.faceplugin.facerecognition.worker", qos: .userInitiated)

    @discardableResult
    public func addListener(_ listener: @escaping (State) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        listeners[token] = listener
        lock.unlock()
        return token
    }

    public func removeListener(_ token: UUID) {
        lock.lock()
        listeners.removeValue(forKey: token)
        lock.unlock()
    }

    private func publish(_ next: State) {
        state = next
        lock.lock()
        let current = Array(listeners.values)
        lock.unlock()
        DispatchQueue.main.async {
            current.forEach { $0(next) }
            NotificationCenter.default.post(name: FaceEngine.stateDidChange, object: next)
        }
    }

    /// Activate with `license`, then load the models. Both run off the main thread.
    public func start(license: String, onDone: ((Int) -> Void)? = nil) {
        publish(.loading)
        worker.async {
            let code = FaceRecognitionSDKQueue.sync { () -> Int in
                var result = Int(FaceRecognitionSDK.activate(license))
                if result == Int(FaceRecognitionSDK.sdk_SUCCESS()) {
                    result = Int(FaceRecognitionSDK.initSDK())
                }
                return result
            }
            let detail = FaceRecognitionSDK.lastLicenseError()
            if detail.isEmpty {
                NSLog("FaceEngine start code=%d", code)
            } else {
                NSLog("FaceEngine start code=%d %@", code, detail)
            }
            self.publish(FaceEngine.state(for: code))
            if let onDone {
                DispatchQueue.main.async { onDone(code) }
            }
        }
    }

    private static func state(for code: Int) -> State {
        switch FaceRecognitionSDKError(rawValue: Int32(code)) {
        case .success: return .ready
        case .notActivated: return .notActivated
        case .licenseInvalid: return .licenseInvalid
        case .licenseExpired: return .licenseExpired
        case .initFailed: return .failed
        default: return .failed
        }
    }

    public func machineCode() -> String {
        FaceRecognitionSDKQueue.sync { FaceRecognitionSDK.machineCode() }
    }

    public func licenseStatus() -> LicenseStatus {
        FaceRecognitionSDKQueue.sync { LicenseStatus.current() }
    }

    public func stateMessage(_ value: State? = nil) -> String {
        switch value ?? state {
        case .loading: return "Loading engine"
        case .ready: return "Ready"
        case .notActivated: return "Not activated"
        case .licenseInvalid: return "License key is invalid"
        case .licenseExpired: return "License expired"
        case .failed:
            let detail = FaceRecognitionSDK.lastLicenseError()
            return detail.isEmpty ? "Engine failed to start" : "Engine failed to start (\(detail))"
        case .sdkMissing: return "Recognition SDK missing"
        }
    }
}
