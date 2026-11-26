# Building and verifying

The libraries are a Swift package. The demo app is the Xcode project beside it.

## What is here now

| Target | State |
| ------ | ----- |
| `FaceRecognitionKit` | Written (stage 1) |
| `FaceRecognitionCapture` | Written (stage 2) |
| The demo app | Rewritten as the five-tab app (stage 3) |

### The Xcode project needs one manual step

`FaceRecognitionSDK.xcodeproj` still lists the old file paths, and a project file cannot be
edited safely by hand. In Xcode, once:

1. Delete the red (missing) file references under `FaceRecognitionSDK`.
2. Drag `FaceRecognitionSDK/Shell` into the project, ticking the app target.
3. **File → Add Package Dependencies → Add Local…** and choose this repository's root, then add
   `FaceRecognitionKit` and `FaceRecognitionCapture` to the app target.
4. Put your license key in `BuiltInLicense.key` in `Shell/Data/AppSettings.swift`.
5. Make sure `Info.plist` has `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.

The package itself builds without any of that, so start with the two schemes below.

### The engine binary

The engine is a prebuilt binary that is not in git. For local work, put the xcframework at:

```text
Frameworks/facerecognitionsdk.xcframework
```

and build with `FACEPLUGIN_LOCAL_ENGINE=1`, which makes `Package.swift` use that file instead of
the GitHub release. If you only have the old `.framework`, wrap it first:

```bash
xcodebuild -create-xcframework -framework facerecognitionsdk.framework -output Frameworks/facerecognitionsdk.xcframework
```

### Build it

The package is iOS-only, so `swift build` will not work — it targets macOS by default. Use
`xcodebuild` with an iOS destination:

```bash
FACEPLUGIN_LOCAL_ENGINE=1 xcodebuild build \
  -scheme FaceRecognitionKit \
  -destination 'generic/platform=iOS'
```

### Run the tests

`FaceLimitsTests` and `CallReportTests` are pure logic and need a simulator, not a device:

```bash
FACEPLUGIN_LOCAL_ENGINE=1 xcodebuild test \
  -scheme FaceRecognitionKit \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Please send me the full output of both build commands.** It was written on Windows with no Swift
compiler available, so the first build is the first time any of it is checked.

## Releasing

A release uploads `facerecognitionsdk.xcframework.zip` to the GitHub release for the tag, then
`Package.swift` points at it:

```bash
swift package compute-checksum facerecognitionsdk.xcframework.zip
```

Put that checksum and the version in `engineVersion` and `engineChecksum` at the top of
`Package.swift`, commit, and tag. Customers then add the repository URL in Xcode and pick the tag,
and SPM fetches the engine for them.
