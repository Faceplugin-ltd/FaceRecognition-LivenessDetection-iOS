import Foundation
import UIKit

/// The on-device gallery: enrol, identify 1:N, read attributes, and search the enrolled people.
///
/// Every engine call is serialized through `FaceRecognitionSDKQueue`. Call these off the main
/// thread — `FaceEngine.shared.worker` is one.
public final class FaceGallery {

    public static let shared = FaceGallery()

    /// Posted on the main queue whenever the gallery changes.
    public static let didChange = Notification.Name("com.faceplugin.FaceGallery.didChange")

    /// The name a face gets when none was typed: it matches the ID shown beside it.
    public static func autoName(_ id: Int64) -> String { "Person \(id)" }

    public static let topK = 100
    public static let maxAttributeFaces = 10
    public static let noFace = "No face found. Use a clear, front-facing photo."
    /// Rejection reason when a probe fails the liveness threshold.
    public static let livenessFailed = "Liveness check failed. Use a live face, not a photo or screen."

    private let store: GalleryStore
    private let imagesDirectory: URL
    private let lock = NSLock()
    private var cachedTemplates: [GalleryStore.Template]?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        imagesDirectory = support.appendingPathComponent("gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        store = GalleryStore(path: support.appendingPathComponent("identity.sqlite").path)
    }

    private func changed() {
        lock.lock()
        cachedTemplates = nil
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: FaceGallery.didChange, object: nil)
        }
    }

    private func templates() -> [GalleryStore.Template] {
        lock.lock()
        if let cachedTemplates {
            lock.unlock()
            return cachedTemplates
        }
        lock.unlock()
        let loaded = store.allTemplates()
        lock.lock()
        cachedTemplates = loaded
        lock.unlock()
        return loaded
    }

    // MARK: - Read

    public func count(query: String = "") -> Int { store.count(query: query) }
    public func get(_ id: Int64) -> FaceRecord? { store.get(id) }
    public func page(query: String, limit: Int, offset: Int) -> [FaceRecord] {
        store.page(query: query, limit: limit, offset: offset)
    }

    // MARK: - Enrol

    /// Exactly-one-face enrolment.
    /// Steps: detection, template, duplicate check (1:N against the gallery), save.
    public func enroll(
        name: String,
        note: String,
        photo: UIImage,
        limits: FaceLimits = .default
    ) -> EnrollOutcome {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !FaceEngine.shared.isReady {
            return .rejected(reason: FaceEngine.shared.stateMessage(), report: nil)
        }

        var steps: [CallStep] = []
        let (faces, detectStep) = timed("faceDetection", { Self.facesDetail($0.count) }, { $0.count == 1 }) {
            FaceDetector.detect(photo, param: .allAttributes())
        }
        steps.append(detectStep)

        if faces.isEmpty {
            return .rejected(reason: FaceGallery.noFace, report: report("enroll", steps, "No face", success: false))
        }
        if faces.count > 1 {
            return .rejected(
                reason: "\(faces.count) faces found. Use a photo that shows only one person.",
                report: report("enroll", steps, "\(faces.count) faces", success: false)
            )
        }

        let (feature, templateStep) = timed(
            "templateExtraction",
            { $0 == nil || $0!.isEmpty ? "no template" : "\($0!.count) bytes" },
            { $0 != nil && !$0!.isEmpty }
        ) {
            FaceDetector.template(photo, face: faces[0])
        }
        steps.append(templateStep)

        guard let feature, !feature.isEmpty else {
            return .rejected(
                reason: "Could not read this face. Use a clear, front-facing photo.",
                report: report("enroll", steps, "template failed", success: false)
            )
        }

        let gallery = templates()
        let (ranked, duplicateStep) = timed("duplicateCheck", { (list: [Candidate]) in
            let over = list.filter { $0.similarity >= limits.match }
            if list.isEmpty { return "gallery empty" }
            if over.isEmpty {
                return "closest \(list[0].name) · ID \(list[0].id) · \(Self.format(list[0].similarity))"
            }
            let names = over
                .map { "\($0.name) · ID \($0.id) · \(Self.format($0.similarity))" }
                .joined(separator: ", ")
            return names + " · possible duplicate" + (over.count > 1 ? "s" : "")
        }) { () -> [Candidate] in
            gallery
                .map { Candidate(id: $0.id, name: $0.name, note: $0.note, similarity: FaceDetector.similarity(feature, $0.feature)) }
                .sorted { $0.similarity > $1.similarity }
        }
        steps.append(duplicateStep)

        let (newId, saveStep) = timed("save", { "ID \($0) · \(gallery.count + 1) enrolled" }) { () -> Int64 in
            let id = store.insert(name: cleanName, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                  createdAt: Self.isoNow(), feature: feature)
            guard id >= 0 else { return id }
            let crop = ImageUtils.cropFace(photo, box: faces[0].box) ?? photo
            let cropURL = imagesDirectory.appendingPathComponent("\(id)_crop.jpg")
            let originalURL = imagesDirectory.appendingPathComponent("\(id)_original.jpg")
            try? ImageUtils.jpeg(crop)?.write(to: cropURL)
            try? ImageUtils.jpeg(photo, quality: 0.9)?.write(to: originalURL)
            store.setPaths(id, crop: cropURL.path, original: originalURL.path)
            return id
        }
        steps.append(saveStep)

        // A blank name is named after the id it was just given, so the People list and the
        // identify headline never show an empty space where a name belongs. This runs before
        // the record is read back, or the outcome would carry the blank name.
        let finalName = cleanName.isEmpty ? Self.autoName(newId) : cleanName
        if newId >= 0, finalName != cleanName {
            _ = store.update(newId, name: finalName,
                             note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard newId >= 0, let saved = store.get(newId) else {
            return .rejected(reason: "Could not save this face.", report: report("enroll", steps, "save failed", success: false))
        }

        let duplicates = ranked.filter { $0.similarity >= limits.match }
        let detail = duplicates.isEmpty
            ? "Saved \(finalName) as ID \(newId)"
            : "Saved \(finalName) as ID \(newId) · looks like " +
              duplicates.map { "\($0.name) (ID \($0.id))" }.joined(separator: ", ")
        let finished = report("enroll", steps, detail, progress: "\(steps.count) of \(steps.count) · saved")
        store.setReport(newId, json: finished.toJson())
        changed()
        return .enrolled(record: saved, report: finished, duplicates: duplicates)
    }

    // MARK: - Identify

    public func identify(_ probe: UIImage, limits: FaceLimits, livenessOn: Bool) -> IdentifyOutcome {
        if !FaceEngine.shared.isReady {
            return .rejected(reason: FaceEngine.shared.stateMessage(), report: nil)
        }
        let threshold = limits.match
        var steps: [CallStep] = []

        var param = FaceDetectionParam()
        param.eyes = true
        if livenessOn { param.liveness = true }
        let (faces, detectStep) = timed("faceDetection", { Self.facesDetail($0.count) }, { !$0.isEmpty }) {
            FaceDetector.detect(probe, param: param)
        }
        steps.append(detectStep)

        if faces.isEmpty {
            return .rejected(reason: FaceGallery.noFace, report: report("identify", steps, "No face", success: false))
        }

        if livenessOn {
            let live = faces.filter { limits.isLive($0.liveness) }.count
            let lowest = faces.map(\.liveness).min() ?? 0
            // Liveness is scored during detection; this step applies the threshold.
            steps.append(CallStep(
                name: "livenessCheck",
                ms: 0,
                detail: "\(live) of \(faces.count) live · lowest \(Self.format(lowest)) / \(Self.format(limits.liveness))",
                ok: live == faces.count
            ))
            if live < faces.count {
                return .rejected(
                    reason: FaceGallery.livenessFailed,
                    report: report("identify", steps, "Liveness failed", success: false)
                )
            }
        }

        var extracted: [(FaceBox, Data)] = []
        let (_, templateStep) = timed("templateExtraction", { _ in "\(extracted.count) templates" }, { _ in !extracted.isEmpty }) {
            for face in faces {
                if let template = FaceDetector.template(probe, face: face), !template.isEmpty {
                    extracted.append((face, template))
                }
            }
        }
        steps.append(templateStep)

        if extracted.isEmpty {
            return .rejected(
                reason: "Could not read this face. Use a clear, front-facing photo.",
                report: report("identify", steps, "template failed", success: false)
            )
        }

        let gallery = templates()
        let (probeFaces, searchStep) = timed(
            "similarity",
            { _ in "\(gallery.count) enrolled · \(extracted.count) probes" }
        ) { () -> [ProbeFace] in
            extracted.enumerated().map { index, pair in
                let scored = gallery.map {
                    Candidate(id: $0.id, name: $0.name, note: $0.note, similarity: FaceDetector.similarity(pair.1, $0.feature))
                }
                return ProbeFace(
                    index: index,
                    box: pair.0.box,
                    ranked: Array(scored.sorted { $0.similarity > $1.similarity }.prefix(FaceGallery.topK))
                )
            }
        }
        steps.append(searchStep)

        let best = probeFaces.compactMap { $0.best?.similarity }.max()
        let detail = best == nil
            ? "Gallery empty"
            : "Best similarity \(Self.format(best!)) · threshold \(Self.format(threshold))"
        let finished = report("identify", steps, detail, progress: "\(steps.count) of \(steps.count) · similarity")
        let extractMs = steps.filter { $0.name != "similarity" }.reduce(0) { $0 + $1.ms }
        let searchMs = steps.filter { $0.name == "similarity" }.reduce(0) { $0 + $1.ms }

        return .done(IdentifyResult(
            probe: probe,
            faces: probeFaces,
            threshold: threshold,
            extractMs: extractMs,
            searchMs: searchMs,
            gallerySize: gallery.count,
            report: finished
        ))
    }

    // MARK: - Attributes

    /// Attribute detection on every face, then a template and a 1:N gallery search per face
    /// (up to `maxAttributeFaces`), timing each call. Never rejects.
    public func attributes(_ probe: UIImage, limits: FaceLimits = .default) -> AttributeResult {
        var steps: [CallStep] = []
        let threshold = limits.match
        if !FaceEngine.shared.isReady {
            return AttributeResult(
                probe: probe,
                report: report("attribute", steps, FaceEngine.shared.stateMessage(), success: false),
                faces: [], threshold: threshold, gallerySize: 0
            )
        }

        let gallery = templates()
        let (boxes, detectStep) = timed("faceDetection", { "\(Self.facesDetail($0.count)) · attributes" }, { !$0.isEmpty }) {
            FaceDetector.detect(probe, param: .allAttributes())
        }
        steps.append(detectStep)

        var features: [Data?] = []
        if !boxes.isEmpty {
            let (list, templateStep) = timed(
                "templateExtraction",
                { "\($0.filter { $0 != nil && !$0!.isEmpty }.count) of \($0.count) templates" },
                { $0.contains { $0 != nil && !$0!.isEmpty } }
            ) { () -> [Data?] in
                boxes.prefix(FaceGallery.maxAttributeFaces).map { FaceDetector.template(probe, face: $0) }
            }
            features = list
            steps.append(templateStep)
        }

        var closest: [Candidate?] = []
        if features.contains(where: { $0 != nil && !$0!.isEmpty }) {
            let (hits, searchStep) = timed(
                "similarity",
                { _ in "\(gallery.count) enrolled · \(features.filter { $0 != nil && !$0!.isEmpty }.count) probes" }
            ) { () -> [Candidate?] in
                features.map { feature in
                    guard let feature, !feature.isEmpty, !gallery.isEmpty else { return nil }
                    return gallery
                        .map { Candidate(id: $0.id, name: $0.name, note: $0.note, similarity: FaceDetector.similarity(feature, $0.feature)) }
                        .max { $0.similarity < $1.similarity }
                }
            }
            closest = hits
            steps.append(searchStep)
        }

        let faces = boxes.enumerated().map { index, box in
            FaceAttributes(
                index: index,
                box: box,
                templateBytes: (index < features.count ? features[index]?.count : nil) ?? 0,
                closest: index < closest.count ? closest[index] : nil
            )
        }
        let bestHit = faces.compactMap(\.closest).max { $0.similarity < $1.similarity }
        let detail = faces.isEmpty
            ? "No face"
            : Self.facesDetail(faces.count) + (bestHit.map { " · closest \($0.name) \(Self.format($0.similarity))" } ?? "")

        return AttributeResult(
            probe: probe,
            report: report("attribute", steps, detail, success: !faces.isEmpty),
            faces: faces,
            threshold: threshold,
            gallerySize: gallery.count
        )
    }

    // MARK: - Edit and delete

    @discardableResult
    public func update(_ id: Int64, name: String, note: String) -> Bool {
        let ok = store.update(
            id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if ok { changed() }
        return ok
    }

    @discardableResult
    public func delete(_ id: Int64) -> Bool {
        guard let record = store.get(id) else { return false }
        let ok = store.delete(id)
        if ok {
            [record.cropPath, record.originalPath]
                .filter { !$0.isEmpty }
                .forEach { try? FileManager.default.removeItem(atPath: $0) }
            changed()
        }
        return ok
    }

    /// Removes every record and every stored crop and original. Returns how many were deleted.
    @discardableResult
    public func deleteAll() -> Int {
        let deleted = store.deleteAll()
        let files = (try? FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        changed()
        return deleted
    }

    // MARK: - Helpers

    private func timed<T>(
        _ name: String,
        _ detail: @escaping (T) -> String,
        _ ok: @escaping (T) -> Bool = { _ in true },
        _ work: () -> T
    ) -> (T, CallStep) {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = work()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return (value, CallStep(name: name, ms: ms, detail: detail(value), ok: ok(value)))
    }

    private func report(
        _ function: String,
        _ steps: [CallStep],
        _ detail: String,
        progress: String = "",
        success: Bool = true
    ) -> CallReport {
        let shown: String
        if !progress.isEmpty {
            shown = progress
        } else if success {
            shown = "\(steps.count) of \(steps.count) · \(steps.last?.name ?? "done")"
        } else {
            let done = steps.filter(\.ok).count
            shown = "\(done) of \(steps.count) · stopped at \(steps.first { !$0.ok }?.name ?? "start")"
        }
        return CallReport(function: function, steps: steps, progress: shown, detail: detail, success: success)
    }

    private static func facesDetail(_ n: Int) -> String { n == 1 ? "1 face" : "\(n) faces" }

    private static func format(_ value: Float) -> String { String(format: "%.2f", value) }

    public static func isoNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }

    public static func parseIso(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.date(from: iso)
    }
}
