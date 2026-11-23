import UIKit

/// Serial access to the native `FaceRecognitionSDK` ObjC API (`facerecognitionsdk.framework`).
/// The engine is not safe for concurrent use — overlapping detect/template work from the camera
/// and gallery can freeze or crash on device.
public enum FaceRecognitionSDKQueue {
    private static let key = DispatchSpecificKey<Void>()
    private static let queue: DispatchQueue = {
        let q = DispatchQueue(label: "com.faceplugin.facerecognitionsdk.sdk", qos: .userInitiated)
        q.setSpecific(key: key, value: ())
        return q
    }()

    public static func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    public static func sync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: key) != nil {
            return work()
        }
        return queue.sync(execute: work)
    }
}
