<div align="center">
<img alt="FacePlugin" src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/brand/logo.png" width="400"/>
</div>

#### 🌐 Company Site - [Here](https://faceplugin.com)
#### 🤗 Hugging Face - [Here](https://huggingface.co/FacePlugin-Ltd)
#### 🛟 Help Center - [Here](https://doc.faceplugin.com)
#### 🐳 Docker Hub - [Here](https://hub.docker.com/r/faceplugin/face-recognition)

# FacePlugin Face Recognition + Liveness Detection — iOS (Fully On-Premise)

Jump: [Quick start](#quick-start) · [Get the library](#get-the-library-facerecognitionsdkxcframework) · [Run the demo](#run-the-demo) · [SDK License](#sdk-license) · [Setup on your own app](#setup-on-your-own-app) · [About SDK](#about-sdk)

## Quick start

- [ ] Clone [FaceRecognition-LivenessDetection-iOS](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS)
- [ ] Download `facerecognitionsdk.xcframework.zip` from [Releases](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/releases/tag/latest) — [Get the library](#get-the-library-facerecognitionsdkxcframework)
- [ ] Open `FaceRecognitionSDK.xcodeproj` in Xcode, set your signing Team, and run on a **physical** iPhone
- [ ] The demo ships with a license key for `com.faceplugin.facerecognition.app`; [contact us](#contact) for your own bundle id

## Introduction

FacePlugin **Face Recognition + Liveness Detection for iOS** runs face recognition and passive liveness entirely on the device. Nothing is sent to a FacePlugin server, which is what banking, access control, and privacy-first identity apps need.

This repository is the whole product: the **engine** (`facerecognitionsdk.xcframework`), two **Swift libraries** you add to your project — `FaceRecognitionKit` and `FaceRecognitionCapture` — and a **demo app** built from those same libraries, so what you read here is what the demo runs.

### Main Functionalities

| Feature | API |
| ------- | --- |
| Face detection (bounding box, landmarks, pose, attributes) | `FaceDetector.detect` |
| passive liveness (anti-spoofing) | `face.liveness` · `FaceLimits.isLive` |
| Face image quality | `face.faceQuality` |
| Face template extraction and similarity | `FaceDetector.template` · `FaceDetector.similarity` |
| **1:N identification** against the on-device gallery | `FaceGallery.shared.identify` |
| Enrollment with duplicate check | `FaceGallery.shared.enroll` |
| Guided camera capture (oval overlay, live coaching) | `FaceRecognitionCapture` |
| License and engine lifecycle | `FaceEngine.shared.start` · `licenseStatus` · `machineCode` |

### Product List

| Platform | Repository |
| -------- | ---------- |
| Android | [FaceRecognition-LivenessDetection-Android](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-Android) |
| **iOS** | **[FaceRecognition-LivenessDetection-iOS](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS)** **(this repo)** |
| React Native | [FaceRecognition-LivenessDetection-ReactNative](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-ReactNative) |
| Flutter | [FaceRecognition-LivenessDetection-Flutter](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-Flutter) |
| .NET MAUI | [FaceRecognition-LivenessDetection-DotNet-MAUI](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-DotNet-MAUI) |
| Ionic Cordova | [FaceRecognition-LivenessDetection-Ionic-Cordova](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-Ionic-Cordova) |
| Ionic Capacitor | [FaceRecognition-LivenessDetection-Ionic-Capacitor](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-Ionic-Capacitor) |

### Related products

- **Face Liveness Detection — Android** — [FaceLivenessDetection-Android](https://github.com/Faceplugin-ltd/FaceLivenessDetection-Android) — liveness only
- **Face Liveness Detection — iOS** — [FaceLivenessDetection-iOS](https://github.com/Faceplugin-ltd/FaceLivenessDetection-iOS) — liveness only
- **Face Recognition — Windows** — [FaceRecognition-Windows](https://github.com/Faceplugin-ltd/FaceRecognition-Windows) — on-premise server
- **Face Recognition — Docker** — [FaceRecognition-Docker](https://github.com/Faceplugin-ltd/FaceRecognition-Docker) — on-premise server

## Before you start

| Step | What you need |
| ---- | ------------- |
| 1 | macOS with Xcode 15 or newer, and an Apple Developer Team for signing |
| 2 | The engine xcframework from the release page — see [Get the library](#get-the-library-facerecognitionsdkxcframework) |
| 3 | A **physical** iPhone. The simulator has no usable camera for liveness |
| 4 | A license key for your bundle id ([contact us](#contact)). The demo already has one for `com.faceplugin.facerecognition.app` |

### System requirements

| Item | Minimum | Recommended |
| ---- | ------- | ----------- |
| iOS | 15.0 | 16 or newer |
| Device | iPhone with arm64 | iPhone 11 or newer |
| Xcode | 15 | Latest release |
| Camera | Front camera | 1080p |

## Get the library (`facerecognitionsdk.xcframework`)

The engine binary is not in git, because it is too large for GitHub.

**[Download the engine from Releases](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/releases/tag/latest)**

```bash
git clone https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS.git
cd FaceRecognition-LivenessDetection-iOS
```

`Package.swift` resolves the engine from the release attached to this tag, so a normal build needs no manual step.

To build against an engine you already have on disk, put it here and set `FACEPLUGIN_LOCAL_ENGINE=1`:

```text
FaceRecognition-LivenessDetection-iOS/
└── Frameworks/
    └── facerecognitionsdk.xcframework
```

If you only have the older `.framework`, wrap it first:

```bash
xcodebuild -create-xcframework -framework facerecognitionsdk.framework -output Frameworks/facerecognitionsdk.xcframework
```

## Run the demo

1. Open **FaceRecognitionSDK.xcodeproj** in Xcode.
2. Set your signing **Team**, and keep the bundle id `com.faceplugin.facerecognition.app` — the bundled license key is tied to it.
3. Run on a physical iPhone and wait for the engine to report **Ready**. The camera and gallery stay disabled until then.

The demo has five tabs:

| Tab | What it shows |
| --- | ------------- |
| **Identity** | Live 1:N against everyone enrolled, with liveness, then a result screen with the ranked matches |
| **People** | Add one person with the capture coach, add many from photos, search, edit, delete |
| **Attribute** | Every face in a photo: liveness, quality, detection score, pose, expression, age, gender, landmarks, closest match |
| **Liveness** | Live anti-spoofing check on the camera feed |
| **Settings** | Match, liveness, and pose thresholds; license status |

If the app crashes at launch in dyld (`SIGABRT`), Xcode may have embedded a small Swift link stub instead of the real engine. **Product → Clean Build Folder** (⇧⌘K), then run again.

### Screenshots

<p align="center">
<img src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/screenshots/face-recognition/mobile/identify.gif" width="240" alt="FacePlugin Face Recognition — live 1:N identification with liveness"/>
&nbsp;
<img src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/screenshots/face-recognition/mobile/people.gif" width="240" alt="FacePlugin Face Recognition — enroll people with the guided capture coach"/>
&nbsp;
<img src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/screenshots/face-recognition/mobile/attribute.gif" width="240" alt="FacePlugin Face Recognition — face attributes, quality and landmarks from a photo"/>
</p>

<p align="center">
<img src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/screenshots/face-recognition/mobile/liveness.gif" width="240" alt="FacePlugin Face Recognition — passive liveness check on the camera feed"/>
&nbsp;
<img src="https://raw.githubusercontent.com/Faceplugin-ltd/faceplugin-assets/main/screenshots/face-recognition/mobile/settings.png" width="240" alt="FacePlugin Face Recognition — match, liveness and pose thresholds in Settings"/>
</p>

## SDK License

Licenses are **offline** and bound to your bundle identifier.

The demo app already includes a valid key for `com.faceplugin.facerecognition.app`. You only need a new key when you use a different bundle id.

### How to get a license

The code below shows how the license is used:

[https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/blob/main/FaceRecognitionSDK/Shell/Data/AppSettings.swift#L112-L116](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/blob/main/FaceRecognitionSDK/Shell/Data/AppSettings.swift#L112-L116)

[https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/blob/main/FaceRecognitionSDK/App/AppDelegate.swift#L11-L14](https://github.com/Faceplugin-ltd/FaceRecognition-LivenessDetection-iOS/blob/main/FaceRecognitionSDK/App/AppDelegate.swift#L11-L14)

Please [contact us](#contact) to get a license for **your own app**. Send us the bundle id you will ship, and `FaceEngine.shared.machineCode()` if we ask for it.

### License capabilities (Recognition + Liveness)

After activation, `FaceEngine.shared.licenseStatus()` reports what the key unlocks. Settings shows the same summary.

| Capability | Meaning |
| ---------- | ------- |
| **Recognition** | Detection, attributes, quality, templates, 1:1 similarity, and 1:N identification |
| **Liveness** | passive anti-spoofing on camera frames and stills |

## Setup on your own app

You integrate from **this repository** — there is no package server, no CocoaPods spec to publish, and no remote dependency to add. The engine binary comes from this repository's GitHub release.

1. Clone this repository next to your own project.
2. In Xcode: **File → Add Package Dependencies → Add Local…**, choose the cloned folder, then add to your app target:
   - **FaceRecognitionKit** — engine, gallery, detector, image and camera helpers
   - **FaceRecognitionCapture** — the capture coach screen (optional)
3. Camera and photo permissions in `Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Camera is used to capture and identify faces.</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Photo library is used to enroll and analyze faces.</string>
   ```

4. Activate once at launch with **your** license key, then use the kit APIs.

You do **not** need the demo's `FaceRecognitionSDK/Shell` screens. Full wiring and result JSON: [https://doc.faceplugin.com](https://doc.faceplugin.com)

## About SDK

Activate once at start-up, then call the engine. The first start loads the on-device models, so it takes a few seconds. After that, calls from your code are safe.

**1. Activate and initialize**

```swift
import FaceRecognitionKit

// AppDelegate.application(_:didFinishLaunchingWithOptions:)
FaceEngine.shared.start(license: "FP1.…") { code in
    // code == 0 when the engine is ready
}

FaceEngine.shared.addListener { state in /* .loading, .ready, .notActivated, … */ }
FaceEngine.shared.isReady
FaceEngine.shared.licenseStatus()
FaceEngine.shared.machineCode()
```

**2. Read a face**

```swift
let prepared = CameraFrameUtils.enginePreparedImage(image)
let faces = FaceDetector.detect(prepared, param: .allAttributes())
guard let face = faces.first else { return }
face.liveness; face.faceQuality; face.yaw; face.roll; face.pitch

let template = FaceDetector.template(prepared, face: face)       // Data
let score = FaceDetector.similarity(templateA, templateB)
```

Feed **upright, unmirrored** frames to the detector, and mirror boxes on the overlay only. Stills go to a long side of 1280; live frames at ~640 are enough. `CameraFrameUtils` does both for you.

**3. Enroll and identify (1:N)**

```swift
let gallery = FaceGallery.shared

let outcome = gallery.enroll(name: "Mina Ortiz", note: "Front desk", image: photo, limits: limits)
let result = gallery.identify(probe, limits: limits, livenessOn: true)
```

Enrolled people live in SQLite inside the app container, with their photos beside it. Ids are never reused.

**4. Thresholds**

```swift
let limits = FaceLimits(match: 0.80, liveness: 0.50, yaw: 20, roll: 20, pitch: 20)
```

`FaceLimits.default` is the engine's operating points, and the helpers `isLive`, `poseOk`, and `matches` apply the same rule everywhere.

**5. What each action did**

`enroll`, `identify`, and the attribute screen return a `CallReport`: every engine call, what it returned, whether it passed, and how long it took (`report.success`, `report.totalMs`, `report.steps`).

**6. Status codes**

| Code | Meaning |
| ---- | ------- |
| 0 | Activate / init OK |
| 1 | Invalid license |
| 2 | Expired license |
| 3 | Not activated |
| 4 | Init failed |

## Contact

<div align="left">
<a target="_blank" href="mailto:info@faceplugin.com"><img src="https://img.shields.io/badge/email-info@faceplugin.com-blue.svg?logo=gmail" alt="faceplugin.com"></a>&emsp;
<a target="_blank" href="https://t.me/FacePluginSupport"><img src="https://img.shields.io/badge/telegram-@FacePluginSupport-blue.svg?logo=telegram" alt="Telegram @FacePluginSupport"></a>&emsp;
<a target="_blank" href="https://wa.me/+14692784822"><img src="https://img.shields.io/badge/whatsapp-faceplugin-blue.svg?logo=whatsapp" alt="faceplugin.com"></a>
</div>
