// swift-tools-version: 5.9
import PackageDescription

// Supported path for Swift Package users: place a local engine under Frameworks/, then
// open/resolve this package. The GitHub Release for this repo ships **runtime.zip** for the
// Xcode demo (facerecognitionsdk.framework + vendor xcframeworks), not a checksummed
// facerecognitionsdk.xcframework.zip — so there is no remote binaryTarget URL yet.
//
// From runtime.zip on a Mac:
//   unzip runtime.zip -d /tmp/fp-runtime
//   xcodebuild -create-xcframework \
//     -framework /tmp/fp-runtime/facerecognitionsdk.framework \
//     -output Frameworks/facerecognitionsdk.xcframework
//
// The FaceRecognitionSDK.xcodeproj demo embeds the unzipped runtime.zip contents directly
// and does not require this Package.swift binary target.

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
        .binaryTarget(
            name: "FaceRecognitionEngine",
            path: "Frameworks/facerecognitionsdk.xcframework"
        ),
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
