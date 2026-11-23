// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The engine is a prebuilt binary. Customers get it from the GitHub release attached to this tag;
// inside this repository, set FACEPLUGIN_LOCAL_ENGINE=1 to build against
// Frameworks/facerecognitionsdk.xcframework instead, so you can test an engine before releasing it.
//
// After building a new engine, update both lines below. Get the checksum with:
//   swift package compute-checksum facerecognitionsdk.xcframework.zip
let engineVersion = "1.0.0"
let engineChecksum = "0000000000000000000000000000000000000000000000000000000000000000"

let useLocalEngine = ProcessInfo.processInfo.environment["FACEPLUGIN_LOCAL_ENGINE"] == "1"

let engineTarget: Target = useLocalEngine
    ? .binaryTarget(
        name: "FaceRecognitionEngine",
        path: "Frameworks/facerecognitionsdk.xcframework"
    )
    : .binaryTarget(
        name: "FaceRecognitionEngine",
        url: "https://github.com/Faceplugin-ltd/Face-Recognition-LivenessDetection-iOS/releases/download/v\(engineVersion)/facerecognitionsdk.xcframework.zip",
        checksum: engineChecksum
    )

let package = Package(
    name: "FaceRecognition",
    platforms: [.iOS(.v15)],
    products: [
        // Engine lifecycle, serialized calls, camera frames, the on-device gallery and 1:N identify.
        .library(name: "FaceRecognitionKit", targets: ["FaceRecognitionKit"]),
        // The capture coach screen. Depends on the kit.
        .library(name: "FaceRecognitionCapture", targets: ["FaceRecognitionCapture"]),
    ],
    targets: [
        engineTarget,
        .target(
            name: "FaceRecognitionKit",
            dependencies: ["FaceRecognitionEngine"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "FaceRecognitionCapture",
            dependencies: ["FaceRecognitionKit"]
        ),
        .testTarget(
            name: "FaceRecognitionKitTests",
            dependencies: ["FaceRecognitionKit"]
        ),
    ]
)
