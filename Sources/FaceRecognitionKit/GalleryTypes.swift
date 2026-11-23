import CoreGraphics
import Foundation
import UIKit

/// One gallery hit for a probe face.
public struct Candidate: Equatable {
    public let id: Int64
    public let name: String
    public let note: String
    public let similarity: Float
}

public struct ProbeFace {
    public let index: Int
    public let box: CGRect
    /// Top 100 by similarity, highest first.
    public let ranked: [Candidate]

    public var best: Candidate? { ranked.first }

    public func matches(_ threshold: Float) -> [Candidate] {
        ranked.filter { $0.similarity >= threshold }
    }

    public func matched(_ threshold: Float) -> Bool {
        (best?.similarity ?? -1) >= threshold
    }
}

public struct IdentifyResult {
    public let probe: UIImage
    public let faces: [ProbeFace]
    public let threshold: Float
    public let extractMs: Double
    public let searchMs: Double
    public let gallerySize: Int
    public let report: CallReport

    /// The face whose best candidate scores highest. Drives the headline and the Rank 1 tile.
    public var primary: ProbeFace {
        faces.max { ($0.best?.similarity ?? -1) < ($1.best?.similarity ?? -1) } ?? faces[0]
    }

    public var matched: Bool { faces.contains { $0.matched(threshold) } }

    /// Matches at or above the threshold across all probe faces, best score per person, highest first.
    public var matches: [Candidate] {
        var best: [Int64: Candidate] = [:]
        for face in faces {
            for candidate in face.matches(threshold) {
                if let existing = best[candidate.id], existing.similarity >= candidate.similarity { continue }
                best[candidate.id] = candidate
            }
        }
        return best.values.sorted { $0.similarity > $1.similarity }
    }
}

public enum EnrollOutcome {
    /// `duplicates` holds every already-enrolled person scoring at or above the identify
    /// threshold, highest first — not just the closest. One new face can match several
    /// existing ones, and hiding the rest makes the gallery look cleaner than it is.
    case enrolled(record: FaceRecord, report: CallReport, duplicates: [Candidate])
    case rejected(reason: String, report: CallReport?)
}

public enum IdentifyOutcome {
    case done(IdentifyResult)
    case rejected(reason: String, report: CallReport?)
}

/// One detected face on the Attribute screen. `closest` is the best gallery hit, nil when the
/// gallery is empty or no template could be read.
public struct FaceAttributes {
    public let index: Int
    public let box: FaceBox
    public let templateBytes: Int
    public let closest: Candidate?
}

public struct AttributeResult {
    public let probe: UIImage
    public let report: CallReport
    /// Every detected face, largest first. Empty when detection found nobody.
    public let faces: [FaceAttributes]
    public let threshold: Float
    public let gallerySize: Int

    /// Largest face, for callers that only want one.
    public var face: FaceBox? { faces.first?.box }
}
